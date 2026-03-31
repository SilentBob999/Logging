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

.PARAMETER input
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
    [CmdletBinding(DefaultParameterSetName='NONE')]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $input,
   #     [Parameter(ParameterSetName='LogHost')]
        [switch]$LogHost,
      #  [Parameter(ParameterSetName='NotLogHost')]
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor
    )

    begin {
        if ($null -eq $ForegroundColor -and $null -ne $host.UI.RawUI.ForegroundColor ) {
            $ForegroundColor = $host.UI.RawUI.ForegroundColor
        }
        if ($null -eq $BackgroundColor -and $null -ne $host.UI.RawUI.BackgroundColor ) {
            $BackgroundColor = $host.UI.RawUI.BackgroundColor
        }

    }
    process {
        # $i = $input
        foreach ($i in @($input)) {
            if ($null -ne $i -and "" -ne "$($i)") {
                if ( ($i -is [System.Management.Automation.VerboseRecord]) ) {
                    if ($null -eq $i.MessageData.ForegroundColor) {
                        Write-LogCustom -Message $i -Level INFO -BumpCallerScope 1 -Verbose:$VerbosePreference -ForegroundColor Cyan
                    } else {
                        Write-LogCustom -Message $i -Level INFO -BumpCallerScope 1 -Verbose:$VerbosePreference -ForegroundColor $i.MessageData.ForegroundColor
                    }
                } elseif ( ($i -is [System.Management.Automation.DebugRecord]) ) {
                    Write-LogCustom -Message $i -Level DEBUG -BumpCallerScope 1 -Verbose:$VerbosePreference
                } elseif ( ($i -is [System.Management.Automation.ErrorRecord]) ) {
                    Write-LogCustom -Message $i -ExceptionInfo $i -Level ERROR -BumpCallerScope 1 -Verbose:$VerbosePreference
                } elseif ( ($i -is [System.Management.Automation.WarningRecord]) ) {
                    Write-LogCustom -Message $i -Level WARNING -BumpCallerScope 1
                } elseif ( ($i -is [System.Management.Automation.InformationRecord]) -or ($i -is [System.String]) ) {
                    if ($LogHost) {
                        if ($null -eq $i.MessageData.ForegroundColor) {
                            Write-LogCustom -Message $i -Level INFO -BumpCallerScope 1 -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor -Verbose:$VerbosePreference
                        } else{
                            Write-LogCustom -Message $i -Level INFO -BumpCallerScope 1 -ForegroundColor $i.MessageData.ForegroundColor -BackgroundColor $i.MessageData.BackgroundColor -Verbose:$VerbosePreference
                        }
                    } else {
                        Wait-Logging
                        if ($null -eq $i.MessageData.ForegroundColor) {
                            Write-Host -Object $i -ForegroundColor  $ForegroundColor -BackgroundColor $BackgroundColor
                        } else {
                            Write-Host -Object $i -ForegroundColor $i.MessageData.ForegroundColor -BackgroundColor $i.MessageData.BackgroundColor
                        }
                    }
                } else {
                    Wait-Logging
                    Write-Output $i
                }
            }
       }
    }
    end {
        Wait-Logging
    }
}
