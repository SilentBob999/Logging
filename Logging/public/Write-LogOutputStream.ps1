<#
.SYNOPSIS
Capture stream and write-to log the corresponding record.

.DESCRIPTION
Catch VerboseRecord, DebugRecord, WarningRecord, ErrorRecord from the stream and log it.
In vscode, *>&1 also catch write host, so InformationRecord are pass back to write-host (but we lossing color information)
The rest is pass to the regular output stream.

Use :
Log all Warning to eventlog.
Log all Verbose or Debug to eventlog.
Log Error to event log without using try/catch when ErrorAction is set to continu.
Etc...

.PARAMETER InputObject
Anything pass from the pipeline.

To redirect all the output of your script to the input of this function, use it this way :
 "*>&1 | Write-LogOutputStream"
Note that InformationRecord does not contain color information.

.PARAMETER LogHost
With this [SWITCH], every InformationRecord are write as information to log instead of just write back to host.

.PARAMETER ForegroundColor
The write-host Foreground Color to use when writting InformationRecord to host.
Cannot be use in combinaison with LogHost switch.

.EXAMPLE
Write-Verbose "verbose message test" -Verbose *>&1 | Write-LogOutputStream

.EXAMPLE
$Scriptblock = [scriptblock]{
        Write-Verbose "verbose message test" -Verbose
        Write-Output "Regular output"
        write-host "write to Host" -ForegroundColor Green
}
$Output = (. $Scriptblock *>&1 | Write-LogOutputStream -ForegroundColor DarkMagenta)
write-host "Output is : $Output" -ForegroundColor Cyan

.EXAMPLE
$VerbosePreference = "Continue"
switch ($VerbosePreference) {
    "Continue" { $Verbose = $true }
    Default { $Verbose = $false }
}
$Scriptblock = [scriptblock]{
        [CmdletBinding()]
        param()
        Write-Verbose "verbose message test"
        Write-Output "Regular output"
        write-host "write to Host" -ForegroundColor Green
}
$Output = (. $Scriptblock -Verbose:$Verbose *>&1 | Write-LogOutputStream)
write-host "Output is : $Output" -ForegroundColor Cyan

.NOTES
See this link for more information regarding Streams redirection :
https://devblogs.microsoft.com/scripting/understanding-streams-redirection-and-write-host-in-powershell/
#>

Function Write-LogOutputStream {
    [CmdletBinding(DefaultParameterSetName='ToLog')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [Alias('input')]
        $InputObject,
        [Parameter(ParameterSetName='ToLog')]
        [switch]$LogHost,
        [Parameter(ParameterSetName='ToLog')]
        [System.ConsoleColor]$ForegroundColor,
        [Parameter(ParameterSetName='ToLog')]
        [System.ConsoleColor]$BackgroundColor
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('ForegroundColor')) {
            try {
                if ($null -ne $host.UI -and $null -ne $host.UI.RawUI) {
                    $ForegroundColor = $host.UI.RawUI.ForegroundColor
                } else {
                    $ForegroundColor = [System.ConsoleColor]::White
                }
            } catch {
                $ForegroundColor = [System.ConsoleColor]::White
            }
        }
        if (-not $PSBoundParameters.ContainsKey('BackgroundColor')) {
            try {
                if ($null -ne $host.UI -and $null -ne $host.UI.RawUI) {
                    $BackgroundColor = $host.UI.RawUI.BackgroundColor
                } else {
                    $BackgroundColor = [System.ConsoleColor]::Black
                }
            } catch {
                $BackgroundColor = [System.ConsoleColor]::Black
            }
        }
    }
    process {
        foreach ($i in @($InputObject)) {
            if ($null -eq $i) { continue }
            if ([string]::IsNullOrEmpty("$i")) { continue }

            try {
                if ($i -is [System.Management.Automation.VerboseRecord]) {
                    $foreColor = if ($null -ne $i.MessageData -and $i.MessageData -is [System.Management.Automation.HostInformationMessage] -and $null -ne $i.MessageData.ForegroundColor) {
                        $i.MessageData.ForegroundColor
                    } else { [System.ConsoleColor]::Cyan }
                    Write-LogCustom -Message "$i" -Level INFO -BumpCallerScope 1 -ForegroundColor $foreColor
                } elseif ($i -is [System.Management.Automation.DebugRecord]) {
                    Write-LogCustom -Message "$i" -Level DEBUG -BumpCallerScope 1
                } elseif ($i -is [System.Management.Automation.ErrorRecord]) {
                    Write-LogCustom -Message "$i" -ExceptionInfo $i -Level ERROR -BumpCallerScope 1
                } elseif ($i -is [System.Management.Automation.WarningRecord]) {
                    Write-LogCustom -Message "$i" -Level WARNING -BumpCallerScope 1
                } elseif ($i -is [System.Management.Automation.InformationRecord]) {
                    # Safely extract color info from MessageData if available
                    $hasMsgColors = ($null -ne $i.MessageData -and $i.MessageData -is [System.Management.Automation.HostInformationMessage] -and $null -ne $i.MessageData.ForegroundColor)
                    if ($LogHost) {
                        if ($hasMsgColors) {
                            $logParams = @{ Message = $i.MessageData.Message; Level = 'INFO'; BumpCallerScope = 1; ForegroundColor = $i.MessageData.ForegroundColor }
                            if ($null -ne $i.MessageData.BackgroundColor) { $logParams['BackgroundColor'] = $i.MessageData.BackgroundColor }
                            Write-LogCustom @logParams
                        } else {
                            Write-LogCustom -Message "$i" -Level INFO -BumpCallerScope 1 -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
                        }
                    } else {
                        Wait-Logging
                        if ($hasMsgColors) {
                            $hostParams = @{ Object = $i.MessageData.Message; ForegroundColor = $i.MessageData.ForegroundColor }
                            if ($null -ne $i.MessageData.BackgroundColor) { $hostParams['BackgroundColor'] = $i.MessageData.BackgroundColor }
                            Write-Host @hostParams
                        } else {
                            Write-Host -Object $i -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
                        }
                    }
                } elseif ($i -is [System.String]) {
                    if ($LogHost) {
                        Write-LogCustom -Message $i -Level INFO -BumpCallerScope 1 -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
                    } else {
                        Wait-Logging
                        Write-Host -Object $i -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
                    }
                } else {
                    Wait-Logging
                    Write-Output $i
                }
            }
            catch {
                Write-Warning "Write-LogOutputStream: Error processing pipeline item: $_"
            }
       }
    }
    end {
        Wait-Logging
    }
}
