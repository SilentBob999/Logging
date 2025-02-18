<#
.SYNOPSIS
Write-LogCustom is a sort of overload of Write-Log (module Logging)

.DESCRIPTION
This function differ from Write-Log as it determine a Unique Event ID for each event (dynamictly).
All the event ID are save to LoggingConfigEventID.xml

.PARAMETER Message
Test to display

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
    $BumpCallerScope = $BumpCallerScope + 1

    $Params = @{
       Body = @{ EventId = 0 }
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
      #  $EventIdentifierName = "$Info" + "$($ExceptionInfo.Exception.GetType().fullname)"
    } elseif ($null -ne $Level -and $Level -notlike "INFO") {
        $EventIdentifierName = "$Info" + "$Level"
    } else { $EventIdentifierName = "$Info" + "OK" }
    ### END REGION ###

    ### REGION INITIALIZE ID LIST ###
    if (-not (Test-Path Variable:Global:EventIdList)) {
        if (-not (Test-Path Variable:Global:EventIDPath)) {
            $Global:EventIDPath = Join-Path (Split-Path -Parent (Get-PSCallStack)[$($BumpCallerScope  )].ScriptName) LoggingConfigEventID.xml
        }
        if (Test-Path $Global:EventIDPath) {
            $Global:EventIdList = Import-Clixml -Path $Global:EventIDPath
        } else {
            $Global:EventIdList = @{}
        }
    }
    Write-Verbose $Global:EventIDPath
    ### END REGION ###

    ### REGION GET ID ###
    if ($Global:EventIdList["$EventIdentifierName"]){
        $Params['Body'] = @{ EventId = $Global:EventIdList["$EventIdentifierName"] }
        #Write-Verbose "Found event ""$($EventIdentifierName)"" with ID $($Global:EventIdList["$EventIdentifierName"])"
    } else {
        ### SUB-REGION Create a new ID ###
        if ( (($Global:EventIdList).Count -eq 0) ){$id = 10} else {
           $id = (@($Global:EventIdList.Values  | Sort-Object -Descending)[0]) + 1
        }
        $Global:EventIdList["$EventIdentifierName"] = $id
        $Global:EventIdList | Export-Clixml -Path $Global:EventIDPath
        ### END SUB REGION ###
        $Params['Body'] = @{ EventId = $Global:EventIdList["$EventIdentifierName"] }
        Write-Verbose "Did not found event ""$($EventIdentifierName)"", give new ID $($Global:EventIdList["$EventIdentifierName"])"
    }
    ### END REGION ###

    return ( Write-Log @Params )
}
