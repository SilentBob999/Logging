@{
    Name          = 'Console'
    Description   = 'Writes messages to console with different colors.'
    Configuration = @{
        Level          = @{Required = $false; Type = [string]; Default = $Logging.Level }
        Format         = @{Required = $false; Type = [string]; Default = $Logging.Format }
        PrintException = @{Required = $false; Type = [bool]; Default = $true }
        ColorMapping   = @{Required = $false; Type = [hashtable]; Default = @{
                'DEBUG'   = 'Blue'
                'INFO'    = 'Green'
                'WARNING' = 'Yellow'
                'ERROR'   = 'Red'
            }
        }
    }
    Init          = {
        param(
            [hashtable] $Configuration
        )

        foreach ($Level in $Configuration.ColorMapping.Keys) {
            $Color = $Configuration.ColorMapping[$Level]

            if ($Color -notin ([System.Enum]::GetNames([System.ConsoleColor]))) {
                $ParentHost.UI.WriteErrorLine("ERROR: Cannot use custom color '$Color': not a valid [System.ConsoleColor] value")
                continue
            }
        }
    }
    Logger        = {
        param(
            [hashtable] $Log,
            [hashtable] $Configuration
        )

        try {
            if ( [string]::IsNullOrEmpty($log.message) -and ![String]::IsNullOrWhiteSpace($Log.ExecInfo)){
                $log.message = $Log.ExecInfo.Exception.Message
             }

            $logText = Format-Pattern -Pattern $Configuration.Format -Source $Log

            if (![String]::IsNullOrWhiteSpace($Log.ExecInfo) -and $Configuration.PrintException) {
                if ($logText -notlike "*$($Log.ExecInfo.Exception.Message)*" ) {
                    $logText += "`n{0}" -f $Log.ExecInfo.Exception.Message
                }
                $logText += "`n{0}" -f (($Log.ExecInfo.InvocationInfo.PositionMessage -split "`r`n" | %{"{0}" -f $_} )[1..2]  -join "`n")
                $logText += "`n  +`tCategoryInfo          : {0}" -f $Log.ExecInfo.CategoryInfo.ToString()
                $logText += "`n  +`tFullyQualifiedErrorId : {0}" -f $Log.ExecInfo.FullyQualifiedErrorId
                $logText += "`n{0}" -f (($Log.ExecInfo.ScriptStackTrace -split "`r`n" | %{"    +`t{0}" -f $_}) -join "`n")
            }

            $mtx = New-Object System.Threading.Mutex($false, 'ConsoleMtx')
            [void] $mtx.WaitOne()
            if ($null -ne $Log.ForegroundColor) {
                $ParentHost.UI.WriteLine( $Log.ForegroundColor, $ParentHost.UI.RawUI.BackgroundColor, $logText)
            } else {
                if ($Configuration.ColorMapping.ContainsKey($Log.Level)) {
                    $ParentHost.UI.WriteLine($Configuration.ColorMapping[$Log.Level], $ParentHost.UI.RawUI.BackgroundColor, $logText)
                } else {
                    $ParentHost.UI.WriteLine($logText)
                }
            }

            [void] $mtx.ReleaseMutex()
            $mtx.Dispose()
        }
        catch {
            $ParentHost.UI.WriteErrorLine($_)
        }
    }
}
