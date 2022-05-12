@{
    Name          = 'Email'
    Description   = 'Send log message to email recipients'
    Configuration = @{
        SMTPServer     = @{Required = $true; Type = [string]; Default = $null }
        From           = @{Required = $true; Type = [string]; Default = $null }
        To             = @{Required = $true; Type = [string]; Default = $null }
        Subject        = @{Required = $false; Type = [string]; Default = '[%{level:-7}] %{message}' }
        Credential     = @{Required = $false; Type = [pscredential]; Default = $null }
        Level          = @{Required = $false; Type = [string]; Default = $Logging.Level }
        Port           = @{Required = $false; Type = [int]; Default = 25 }
        UseSsl         = @{Required = $false; Type = [bool]; Default = $false }
        Format         = @{Required = $false; Type = [string]; Default = $Logging.Format }
        PrintException = @{Required = $false; Type = [bool]; Default = $false }
    }
    Logger        = {
        param(
            [hashtable] $Log,
            [hashtable] $Configuration
        )

        $Body = '<h3>{0}</h3>' -f $Log.Message

        if (![String]::IsNullOrWhiteSpace($Log.ExecInfo)) {
            $Body += '<pre>'
            $Body += "`n{0}" -f $Log.ExecInfo.Exception.Message
            $Body += "`n{0}" -f (($Log.ExecInfo.ScriptStackTrace -split "`r`n" | % { "`t{0}" -f $_ }) -join "`n")
            $Body += '</pre>'
        }

        $Params = @{
            SmtpServer = $Configuration.SMTPServer
            From       = $Configuration.From
            To         = $Configuration.To.Split(',').Trim()
            Port       = $Configuration.Port
            UseSsl     = $Configuration.UseSsl
            Subject    = Format-Pattern -Pattern $Configuration.Subject -Source $Log
            Body       = $Body
            BodyAsHtml = $true
        }

        if ($Configuration.Credential) {
            $Params['Credential'] = $Configuration.Credential
        }

        if ($Log.Body) {
            $Params.Body += "`n`n{0}" -f ($Log.Body | ConvertTo-Json)
        }
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

            if ( [string]::IsNullOrEmpty($Params['Body']) ){
                $Params['Body'] = $ExceptionFormat -f $ExceptionFields
            } else {
                $Params['Body'] += "`n`n" + ($ExceptionFormat -f $ExceptionFields)
            }
        }

        Send-MailMessage @Params
    }
}
