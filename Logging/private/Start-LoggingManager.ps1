function Start-LoggingManager {
    [CmdletBinding()]
    param(
        [TimeSpan]$ConsumerStartupTimeout = "00:00:10"
    )

    New-Variable -Name LoggingEventQueue    -Scope Script -Value ([System.Collections.Concurrent.BlockingCollection[hashtable]]::new(100))
    New-Variable -Name LoggingRunspace      -Scope Script -Option ReadOnly -Value ([hashtable]::Synchronized(@{ }))
    New-Variable -Name TargetsInitSync      -Scope Script -Option ReadOnly -Value ([System.Threading.ManualResetEventSlim]::new($false))

    # 1. Création d'un état par défaut ISOLÉ du processus hôte actuel (Bloque les hooks de MC2Tools)
    $Script:InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()

    if ($Script:InitialSessionState.psobject.Properties['ApartmentState']) {
        $Script:InitialSessionState.ApartmentState = [System.Threading.ApartmentState]::MTA
    }

    # 2. Importation des fonctions sous forme de texte brut
    foreach ($Function in 'Format-Pattern', 'Initialize-LoggingTarget', 'Get-LevelNumber') {
        Write-Verbose "Importing function $($Function) into runspace"
        $FuncCmd = Get-Command -Name $Function -CommandType Function -ErrorAction Stop
        $Body = $FuncCmd.ScriptBlock.ToString()
        $f = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $Function, $Body
        $Script:InitialSessionState.Commands.Add($f)
    }

    # 3. Initialisation et ouverture du Runspace isolé
    $Script:LoggingRunspace.Runspace = [runspacefactory]::CreateRunspace($Script:InitialSessionState)
    $Script:LoggingRunspace.Runspace.Name = 'LoggingQueueConsumer'
    $Script:LoggingRunspace.Runspace.Open()

    # 4. Injection directe des variables de module via le Proxy (Évite la sérialisation lourde pré-ouverture)
    Write-Verbose "Injecting live module variables via SessionStateProxy..."
    $Proxy = $Script:LoggingRunspace.Runspace.SessionStateProxy
    
    $Proxy.SetVariable('ScriptRoot',          (Get-Variable -Name 'ScriptRoot' -Scope Script -ValueOnly))
    $Proxy.SetVariable('LevelNames',          (Get-Variable -Name 'LevelNames' -Scope Script -ValueOnly))
    $Proxy.SetVariable('Logging',             (Get-Variable -Name 'Logging' -Scope Script -ValueOnly))
    $Proxy.SetVariable('LoggingEventQueue',    (Get-Variable -Name 'LoggingEventQueue' -Scope Script -ValueOnly))
    $Proxy.SetVariable('TargetsInitSync',     (Get-Variable -Name 'TargetsInitSync' -Scope Script -ValueOnly))
    
    # Références pour l'hôte et l'affichage des verbeux
    $Proxy.SetVariable('ParentHost', $Host)
    $Proxy.SetVariable('VerbosePreference', $VerbosePreference)

    # 5. Définition du consommateur de la file d'attente (Scriptblock d'arrière-plan)
    $Consumer = {
        Initialize-LoggingTarget

        $TargetsInitSync.Set(); # Signale au runspace parent que l'initialisation est un succès

        foreach ($Log in $Script:LoggingEventQueue.GetConsumingEnumerable()) {
            if ($Script:Logging.EnabledTargets) {
                $ParentHost.NotifyBeginApplication()

                try {
                    for ($targetEnum = $Script:Logging.EnabledTargets.GetEnumerator(); $targetEnum.MoveNext(); ) {
                        [string] $LoggingTarget = $targetEnum.Current.key
                        [hashtable] $TargetConfiguration = $targetEnum.Current.Value
                        $Logger = [scriptblock] $Script:Logging.Targets[$LoggingTarget].Logger

                        $targetLevelNo = Get-LevelNumber -Level $TargetConfiguration.Level

                        if ($Log.LevelNo -ge $targetLevelNo) {
                            Invoke-Command -ScriptBlock $Logger -ArgumentList @($Log.PSObject.Copy(), $TargetConfiguration)
                        }
                    }
                }
                catch {
                    $ParentHost.UI.WriteErrorLine($_)
                }
                finally {
                    $ParentHost.NotifyEndApplication()
                }
            }
        }
    }

    # 6. Exécution asynchrone du traitement de log
    $Script:LoggingRunspace.Powershell = [Powershell]::Create().AddScript($Consumer, $true)
    $Script:LoggingRunspace.Powershell.Runspace = $Script:LoggingRunspace.Runspace
    $Script:LoggingRunspace.Handle = $Script:LoggingRunspace.Powershell.BeginInvoke()

    #region Handle Module Removal
    $OnRemoval = {
        $Module = Get-Module Logging

        if ($Module) {
            $Module.Invoke({
                Wait-Logging
                Stop-LoggingManager
            })
        }

        [System.GC]::Collect()
    }

    $ExecutionContext.SessionState.Module.OnRemove += $OnRemoval
    $Script:LoggingRunspace.EngineEventJob = Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $OnRemoval
    #endregion Handle Module Removal

    # 7. Attente de la confirmation de démarrage (Ne devrait plus expirer)
    if(-not $TargetsInitSync.Wait($ConsumerStartupTimeout)){
        throw 'Timed out while waiting for logging consumer to start up'
    }
    Write-Verbose "Start-LoggingManager completed"
}