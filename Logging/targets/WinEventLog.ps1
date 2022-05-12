@{
    Name = 'WinEventLog'
    Configuration = @{
        LogName  = @{Required = $true; Type = [string]; Default = $null}
        Source   = @{Required = $true; Type = [string]; Default = $null}
        Level    = @{Required = $false; Type = [string]; Default = $Logging.Level}
        Format   = @{Required = $false; Type = [string]; Default = $Logging.Format}
    }
    Logger = {
        param(
            [hashtable] $Log,
            [hashtable] $Configuration
        )

        $Params = @{
            EventId = 0
        }

        if ($Configuration.LogName) { $Params['LogName'] = $Configuration.LogName }
        if ($Configuration.Source)  { $Params['Source']  = $Configuration.Source }
        if ($Log.Body.EventId)      { $Params['EventId'] = $Log.Body.EventId }

        switch ($Log.LevelNo) {
            {$_ -ge 40}                { $Params['EntryType'] = 'Error' }
            {$_ -ge 30 -and $_ -lt 40} { $Params['EntryType'] = 'Warning' }
            {$_ -lt 30}                { $Params['EntryType'] = 'Information' }
        }

        $Params['Message'] = Format-Pattern -Pattern $Configuration.Format -Source $Log

        if ($Log.ExecInfo) {
            $ExceptionFormat = "{0}`n" +
                               "{1}`n" +
                               "+     CategoryInfo          : {2}`n" +
                               "+     FullyQualifiedErrorId : {3}`n" +
                               "+     Details message       : {6}`n" +
                               "+     RecommendedAction     : {7}`n" +
                               "`n`n" +
                               "ScriptStackTrace :`n" +
                               "{4}"+
                               "`n`n" +
                               "Exception details :" +
                               "{5}"

            $ExceptionFields = @($Log.ExecInfo.Exception.Message,
                               $Log.ExecInfo.InvocationInfo.PositionMessage,
                               $Log.ExecInfo.CategoryInfo.ToString(),
                               $Log.ExecInfo.FullyQualifiedErrorId,
                               $Log.ExecInfo.ScriptStackTrace,
                               ($Log.ExecInfo.Exception | format-list -force | Out-String),
                               $Log.ExecInfo.ErrorDetails.message,
                               $Log.ExecInfo.ErrorDetails.RecommendedAction)

            if ( [string]::IsNullOrEmpty($Params['Message']) ){
                $Params['Message'] = $ExceptionFormat -f $ExceptionFields
            } else {
                $Params['Message'] += "`n`n" + ($ExceptionFormat -f $ExceptionFields)
            }
        }

        Write-EventLog @Params
    }
}