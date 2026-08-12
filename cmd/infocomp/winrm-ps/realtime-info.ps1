<#
Realtime system uptime and session information in JSON.
#>
[CmdletBinding()]
param()

function Clean-SessionString {
    param([string]$value)
    if (-not $value) { return $null }
    $clean = $value -replace '[\x00-\x1F\x7F]+', ''
    $clean = $clean.Trim()
    $clean = $clean -replace '^[>\s]+', ''
    if ($clean -ne '') { return $clean }
    return $null
}

function Format-DateTimeString {
    param([datetime]$dateTime)
    if (-not $dateTime) { return $null }
    return $dateTime.ToString('yyyy-MM-dd HH:mm:ss')
}

function Convert-LogonIdToDecimal {
    param([string]$logonId)
    if (-not $logonId) { return $null }
    if ($logonId -match '^0x([0-9A-Fa-f]+)$') {
        return [Convert]::ToInt64($matches[1], 16).ToString()
    }
    return $logonId.ToString()
}

function Get-LoggedOnUsers {
    $users = @()
    try {
        $associations = Get-CimInstance -ClassName Win32_LoggedOnUser -ErrorAction SilentlyContinue
        foreach ($assoc in $associations) {
            $antecedentText = [string]$assoc.Antecedent
            $dependentText  = [string]$assoc.Dependent
            if (-not $antecedentText -or -not $dependentText) { continue }

            $accountMatch = [regex]::Match($antecedentText, 'Name = "(?<Name>[^"]+)"(?:, Domain = "(?<Domain>[^"]+)")?')
            $logonIdMatch  = [regex]::Match($dependentText, 'LogonId = "(?<LogonId>[^"]+)"')
            if (-not $accountMatch.Success -or -not $logonIdMatch.Success) { continue }

            $accountName = $accountMatch.Groups['Name'].Value
            $domain      = $accountMatch.Groups['Domain'].Value
            $logonId     = $logonIdMatch.Groups['LogonId'].Value

            $session = Get-CimInstance -ClassName Win32_LogonSession -Filter "LogonId='$logonId'" -ErrorAction SilentlyContinue | Select-Object -First 1
            $logonType = if ($session -and $session.LogonType -ne $null) { [int]$session.LogonType } else { $null }
            $startTime = $null
            if ($session -and $session.StartTime) {
                $formats = @('dd.MM.yyyy H:mm:ss', 'dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy H:mm', 'dd.MM.yyyy HH:mm')
                foreach ($format in $formats) {
                    try {
                        $startTime = [datetime]::ParseExact($session.StartTime, $format, [System.Globalization.CultureInfo]::InvariantCulture)
                        break
                    } catch {
                        $startTime = $null
                    }
                }
                if (-not $startTime) {
                    try {
                        $startTime = [datetime]::Parse($session.StartTime, [System.Globalization.CultureInfo]::GetCultureInfo('ru-RU'))
                    } catch {
                        $startTime = $null
                    }
                }
            }

            $users += [PSCustomObject]@{
                AccountName = $accountName
                Domain      = $domain
                LogonId     = Convert-LogonIdToDecimal $logonId
                LogonType   = $logonType
                StartTime   = Format-DateTimeString $startTime
            }
        }
    } catch {
        # ignore failures and continue without logged-on user details
    }
    return $users | Sort-Object Domain, AccountName, LogonId -Unique
}

$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$bootTimeRaw = if ($os) { $os.LastBootUpTime } else { $null }
if ($bootTimeRaw -is [datetime]) {
    $bootTime = $bootTimeRaw
} elseif ($bootTimeRaw -is [string]) {
    try {
        $bootTime = [Management.ManagementDateTimeConverter]::ToDateTime($bootTimeRaw)
    } catch {
        $bootTime = [datetime]::Parse($bootTimeRaw)
    }
} else {
    $bootTime = $null
}
$uptimeSpan = if ($bootTime) { (Get-Date) - $bootTime } else { $null }

$sessions = @()
$quserFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "quser-$(Get-Random).txt")
try {
    $cmd = "chcp 866>nul & quser > `"$quserFile`" 2>nul"
    Start-Process -FilePath cmd.exe -ArgumentList '/c', $cmd -NoNewWindow -Wait | Out-Null
    $quserOutput = Get-Content -Path $quserFile -Encoding OEM -ErrorAction SilentlyContinue
    if ($quserOutput) {
        $lines = $quserOutput | Where-Object { $_ -match '\S' }
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()
            $pattern = '^(?<SessionName>\S+)\s+(?<UserName>\S+)\s+(?<Id>\d+)\s+(?<State>.+?)\s+(?<IdleTime>\S+)\s+(?<LogonDate>\d{2}\.\d{2}\.\d{4})\s+(?<LogonClock>\S+)$'
            $match = [regex]::Match($line, $pattern)
            if ($match.Success) {
                $sessions += [PSCustomObject]@{
                    SessionId   = if ($match.Groups['Id'].Value -ne '') { [int]$match.Groups['Id'].Value } else { $null }
                    SessionName = Clean-SessionString $match.Groups['SessionName'].Value
                    UserName    = Clean-SessionString $match.Groups['UserName'].Value
                    State       = Clean-SessionString $match.Groups['State'].Value
                    IdleTime    = Clean-SessionString $match.Groups['IdleTime'].Value
                    LogonTime   = "$(Clean-SessionString $match.Groups['LogonDate'].Value) $(Clean-SessionString $match.Groups['LogonClock'].Value)"
                }
            }
        }
    }
} finally {
    if (Test-Path -Path $quserFile) { Remove-Item -Path $quserFile -Force -ErrorAction SilentlyContinue }
}

$loggedOnUsers = Get-LoggedOnUsers

$result = [PSCustomObject]@{
    Uptime = [PSCustomObject]@{
        SinceBoot     = Format-DateTimeString $bootTime
        TotalSeconds  = if ($uptimeSpan) { [int]$uptimeSpan.TotalSeconds } else { $null }
        TotalDuration = if ($uptimeSpan) { $uptimeSpan.ToString() } else { $null }
    }
    Sessions = $sessions
    LoggedOnUsers = $loggedOnUsers
}
$result | ConvertTo-Json -Depth 5
