# Copy both functions into your script, or dot-source this file.
function Initialize-LogScale {
    param([string]$ConfigPath, [string]$ScriptName)

    try {
        if ($ScriptName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$') {
            throw 'Use a simple, unique script name without path separators.'
        }
        $configFile = Get-Item -LiteralPath $ConfigPath -ErrorAction Stop
        $config = Get-Content -LiteralPath $configFile.FullName -Raw -Encoding UTF8 -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
        if ($config.direct_logging_enabled -isnot [bool] -or $config.local_logging_enabled -isnot [bool]) {
            throw 'Logging switches must be JSON booleans.'
        }
        $logger = [pscustomobject]@{
            ScriptName = $ScriptName; RunId = [guid]::NewGuid().ToString()
            DirectEnabled = $false; LocalEnabled = $false
            Endpoint = $null; Token = $null; TimeoutSeconds = 5; LogDirectory = $null
        }
    } catch {
        Write-Warning 'LogScale initialization failed. Check the JSON file and script name; logging is disabled.' -WarningAction Continue
        return
    }

    if ($config.direct_logging_enabled) {
        try {
            $url = [uri]$config.url
            if (-not $url.IsAbsoluteUri -or $url.Scheme -ne 'https' -or
                $url.UserInfo -or $url.Query -or $url.Fragment -or $url.AbsolutePath -ne '/') {
                throw 'Use an HTTPS origin without credentials, path, query or fragment.'
            }
            if ($config.ingest_token -isnot [string] -or $config.ingest_token -notmatch '^\S+$') {
                throw 'An ingest token is required.'
            }
            if (($config.timeout_seconds -isnot [int] -and $config.timeout_seconds -isnot [long]) -or
                $config.timeout_seconds -lt 1 -or $config.timeout_seconds -gt 60) {
                throw 'timeout_seconds must be an integer from 1 to 60.'
            }
            $logger.Endpoint = $url.AbsoluteUri.TrimEnd('/') + '/api/v1/ingest/humio-structured'
            $logger.Token = $config.ingest_token
            $logger.TimeoutSeconds = [int]$config.timeout_seconds
            $logger.DirectEnabled = $true
        } catch {
            Write-Warning 'LogScale direct logging disabled. Check the HTTPS origin, ingest token and timeout_seconds (1-60).' -WarningAction Continue
        }
    }

    if ($config.local_logging_enabled) {
        try {
            if (($config.retention_days -isnot [int] -and $config.retention_days -isnot [long]) -or
                $config.retention_days -lt 1 -or $config.retention_days -gt 36500) {
                throw 'retention_days must be an integer from 1 to 36500.'
            }
            if ($config.log_directory -isnot [string] -or [string]::IsNullOrWhiteSpace($config.log_directory)) {
                throw 'A log directory is required.'
            }
            $directory = $config.log_directory
            if (-not [IO.Path]::IsPathRooted($directory)) {
                $directory = Join-Path $configFile.DirectoryName $directory
            }
            $directory = [IO.Path]::GetFullPath($directory)
            $null = [IO.Directory]::CreateDirectory($directory)
            $item = Get-Item -LiteralPath $directory -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked log directory is not supported.' }
            $logger.LogDirectory = $directory
            $logger.LocalEnabled = $true
        } catch {
            Write-Warning 'LogScale local logging disabled. Check log_directory permissions and retention_days (1-36500).' -WarningAction Continue
        }
        if ($logger.LocalEnabled) {
            try {
                # Keep today and the previous retention_days - 1 UTC dates. Never recurse.
                $oldest = [datetime]::UtcNow.Date.AddDays(1 - [int]$config.retention_days)
                $pattern = '^' + [regex]::Escape($ScriptName) + '-(\d{4}-\d{2}-\d{2})\.jsonl$'
                foreach ($file in Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction Stop) {
                    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Name -cnotmatch $pattern) { continue }
                    $date = [datetime]::MinValue
                    if ([datetime]::TryParseExact($Matches[1], 'yyyy-MM-dd', [cultureinfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::None, [ref]$date) -and $date -lt $oldest) {
                        try { Remove-Item -LiteralPath $file.FullName -ErrorAction Stop }
                        catch { Write-Warning 'LogScale could not delete an expired log file; continuing.' -WarningAction Continue }
                    }
                }
            } catch {
                Write-Warning 'LogScale startup cleanup failed; logging will continue.' -WarningAction Continue
            }
        }
    }
    return $logger
}

function Write-LogScale {
    param($Logger, [string]$Level, [string]$Message, $Fields = @{})

    if ($null -eq $Logger -or (-not $Logger.DirectEnabled -and -not $Logger.LocalEnabled)) { return }
    try {
        if ($Level -cnotin @('INFO', 'WARN', 'ERROR') -or [string]::IsNullOrWhiteSpace($Message)) {
            throw 'Use INFO, WARN or ERROR and a nonempty message.'
        }
        $now = [datetime]::UtcNow
        $event = @{
            timestamp = $now.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [cultureinfo]::InvariantCulture)
            level = $Level; message = $Message; script_name = $Logger.ScriptName; run_id = $Logger.RunId
        }
        if ($Fields -isnot [Collections.IDictionary]) { throw 'Fields must be a dictionary.' }
        foreach ($key in $Fields.Keys) {
            if ($key -isnot [string] -or $key -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$' -or $event.ContainsKey($key)) {
                throw 'Invalid or reserved field name.'
            }
            $value = $Fields[$key]
            if ($null -ne $value -and $value -isnot [string] -and $value -isnot [bool] -and
                $value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) {
                throw 'Use scalar extra fields.'
            }
            if ($value -is [double] -and ([double]::IsNaN($value) -or [double]::IsInfinity($value))) {
                throw 'Numbers must be finite.'
            }
            $event[$key] = $value
        }
        $json = ConvertTo-Json -InputObject $event -Compress -Depth 4 -ErrorAction Stop
    } catch {
        Write-Warning 'LogScale event rejected. Check level, message and scalar extra fields; do not overwrite reserved fields.' -WarningAction Continue
        return
    }

    if ($Logger.LocalEnabled) {
        try {
            $file = Join-Path $Logger.LogDirectory ($Logger.ScriptName + '-' + $now.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) + '.jsonl')
            if (Test-Path -LiteralPath $file) {
                $item = Get-Item -LiteralPath $file -Force -ErrorAction Stop
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked log file is not supported.' }
            }
            # ponytail: one writer per script/path; use per-run files if overlapping runs are needed.
            [IO.File]::AppendAllText($file, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        } catch {
            Write-Warning 'LogScale local write failed. Check the log directory, permissions and free space; continuing.' -WarningAction Continue
        }
    }

    if ($Logger.DirectEnabled) {
        try {
            $body = ConvertTo-Json -InputObject @(@{ events = @(@{ timestamp = $event.timestamp; attributes = $event }) }) -Compress -Depth 6 -ErrorAction Stop
            $request = @{
                Uri = $Logger.Endpoint; Method = 'Post'
                Headers = @{ Authorization = 'Bearer ' + $Logger.Token }
                Body = [Text.Encoding]::UTF8.GetBytes($body); ContentType = 'application/json; charset=utf-8'
                TimeoutSec = $Logger.TimeoutSeconds; MaximumRedirection = 0; ErrorAction = 'Stop'
            }
            if ($PSVersionTable.PSVersion -ge [version]'7.4') {
                $request.OperationTimeoutSeconds = $Logger.TimeoutSeconds
            }
            $null = Invoke-RestMethod @request
        } catch {
            # Do not echo server responses or exception text: they can contain tokens or event data.
            Write-Warning 'LogScale HTTP delivery failed. Check connectivity, TLS, the Cloud URL and ingest token; event not retried.' -WarningAction Continue
        }
    }
}
