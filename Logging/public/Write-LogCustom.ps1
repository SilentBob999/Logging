<#
.SYNOPSIS
Write-LogCustom is a sort of overload of Write-Log (module Logging)

.DESCRIPTION
This function differ from Write-Log as it determine a Unique Event ID for each event (dynamictly).
All the event ID are save to LoggingConfigEventID.xml

.PARAMETER Message
Test to display.  The message is facultative if an exception is given to ExceptionInfo.

.PARAMETER Arguments
? Directly pass to Write-Log (module Logging). Refer to the module doc.

.PARAMETER Level
'ERROR','WARNING','INFO','DEBUG'
Set the color in the console and the level in the Event Log

.PARAMETER ExceptionInfo
Of type ErrorRecord. Pass the object to get more detail info in the log.

.EXAMPLE
Write-LogCustom -Level WARNING -Message "attention, we missing this..."
try {throw "error"} catch {Write-LogCustom -Level ERROR -Message "error encounter" -ExceptionInfo $_}

.NOTES
General notes
#>

Function Write-LogCustom {
    param (
        [Parameter(Position = 1,
        Mandatory = $false)]
        [alias('msg')]
        [string]$Message,
        [Parameter(Position = 2,
        Mandatory = $false)]
        [alias('arg')]
        [array] $Arguments,
        [Parameter(Position = 4,
            Mandatory = $false)]
        [ValidateSet('ERROR','WARNING','INFO','DEBUG')]
        [alias('lev')]
        [string]$Level,
        [Parameter(Position = 5,
            Mandatory = $false)]
        [alias('err')]
        [System.Management.Automation.ErrorRecord]$ExceptionInfo,
        [Parameter(Position = 6,
            Mandatory = $false)]
        [alias('bscope')]
        [int]$BumpCallerScope=0,
        [Parameter(Position = 7,
            Mandatory = $false)]
        [System.ConsoleColor]$ForegroundColor,
        [Parameter(Position = 8,
            Mandatory = $false)]
        [System.ConsoleColor]$BackgroundColor
    )
    $BumpCallerScope = $BumpCallerScope + 1 # Write-LogCustom his one more step away from Write-Log

    $Params = @{
       Body = @{ EventId = 0 }
    }
    if (-Not $ExceptionInfo -and -Not $Message) {
        # ignore if no message and no exception
        return
    }
    if ($ExceptionInfo) {
        $Params['ExceptionInfo'] = $ExceptionInfo
    }
    if ($Message) {
        $Params['Message'] = $Message
    }
    if ($Arguments) {
        $Params['Arguments'] = $Arguments
    }
    if ($Level) {
        $Params['Level'] = $Level
    }
    if ($BumpCallerScope) {
        $Params['BumpCallerScope'] = $BumpCallerScope
    }
    if ($ForegroundColor) {
        $Params['ForegroundColor'] = $ForegroundColor
    }
    if ($BackgroundColor) {
        $Params['BackgroundColor'] = $BackgroundColor
    }

    ### REGION set EventIdentifierName ###
    $invocationInfo = (Get-PSCallStack)[$($BumpCallerScope + 1)]
    try {$File = (Get-Item $($invocationInfo.ScriptName)).Name}
    catch {$File = ""}
    $Info = "[$($File) -> $($invocationInfo.Command)]"
    if ($ExceptionInfo) {
        $EventIdentifierName = "$Info" + "$($ExceptionInfo.Exception.Message)"
    } elseif ($null -ne $Level -and $Level -notlike "INFO") {
        $EventIdentifierName = "$Info" + "$Level"
    } else { $EventIdentifierName = "$Info" + "OK" }
    ### END REGION ###

    ### REGION INITIALIZE ID LIST ###
    if (-not (Test-Path Variable:Global:EventIdList )) {
        if (-not (Test-Path Variable:Global:EventIDPath )) {
            try {
                if ($null -ne $BumpCallerScope -and $null -ne (Get-PSCallStack)[$($BumpCallerScope  )].ScriptName ) {
                     $Global:EventIDPath = Join-Path (Split-Path -Parent (Get-PSCallStack)[$($BumpCallerScope  )].ScriptName) LoggingConfigEventID.xml
                     Write-Warning "New list of EventID save to $($Global:EventIDPath)`nPlease define the Global Variable 'EventIDPath' to use another path "
                }  else { <# Caller path not detected - No EvenIdList Found #> }
            }
            catch { <# Caller path not detected - No EvenIdList Found #> }
        }
        if ( $null -ne $Global:EventIDPath -and (Test-Path $Global:EventIDPath) ) {
            $data = Import-Clixml -Path $Global:EventIDPath
            $Global:EventIdList = [hashtable]::Synchronized($data)
        } else {
            $Global:EventIdList = [hashtable]::Synchronized(@{})
        }
    }
    ### END REGION ###

    ### REGION GET ID ###
    $currentId = $Global:EventIdList["$EventIdentifierName"]
    if ($null -ne $currentId) {
        $Params['Body'] = @{ EventId = $currentId }
    } else {
        ### SUB-REGION Create a new ID ###
        if ($null -ne $Global:EventIDPath) {
            # On définit l'objet de verrouillage
            $lockObj = $Global:EventIdList.SyncRoot
            $lockTaken = $false
            
            try {
                # On tente de prendre le verrou
                [System.Threading.Monitor]::Enter($lockObj, [ref]$lockTaken)

                # Double vérification à l'intérieur du verrou
                if (-not $Global:EventIdList.ContainsKey("$EventIdentifierName")) {
                    if ($Global:EventIdList.Count -eq 0) {
                        $id = 10
                    } else {
                        # Calcul de l'ID suivant
                        $id = ($Global:EventIdList.Values | Sort-Object -Descending | Select-Object -First 1) + 1
                    }
                    
                    $Global:EventIdList["$EventIdentifierName"] = $id
                    $Global:EventIdList | Export-Clixml -Path $Global:EventIDPath
                }
            }
            finally {
                # IMPORTANT : On libère TOUJOURS le verrou, même en cas d'erreur
                if ($lockTaken) {
                    [System.Threading.Monitor]::Exit($lockObj)
                }
            }
        } else {
            # All event save with ID 9 if the EventIdList is volatile
            $Global:EventIdList["$EventIdentifierName"] = 9
        }
       
        ### END SUB REGION ###
        $Params['Body'] = @{ EventId = $Global:EventIdList["$EventIdentifierName"] }
        Write-Verbose "Did not found event ""$($EventIdentifierName)"", give new ID $($Global:EventIdList["$EventIdentifierName"])"
    }
    ### END REGION ###

    try {
        Write-Debug ("{0};  Selected:{1} _ {2}`nPSCallStack:`n{3}`nEvent ""$($EventIdentifierName)"", ID $($Global:EventIdList["$EventIdentifierName"])`nEventIDPath: $($Global:EventIDPath)" -f  $EventIdentifierName , ((Get-PSCallStack)[$($BumpCallerScope)] ).Command , ((Get-PSCallStack)[$($BumpCallerScope)] ).ScriptName, (Get-PSCallStack | Select-Object command, ScriptName | Out-String) )
    } catch {    }

    return ( Write-Log @Params )
}
