<#
Group Policy update information in JSON.
#>
[CmdletBinding()]
param()

function Format-DateTimeString {
    param([datetime]$dateTime)
    if (-not $dateTime) { return $null }
    return $dateTime.ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-GroupPolicyUpdateInfo {
    $computerEvent = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-GroupPolicy'; Id=1500} -MaxEvents 1 -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message
    $userEvent = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-GroupPolicy'; Id=@(1501,1502)} -MaxEvents 1 -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, Message
    $lastUpdate = @($computerEvent, $userEvent) | Where-Object { $_ } | Sort-Object TimeCreated -Descending | Select-Object -First 1
    [PSCustomObject]@{
        ComputerPolicy = if ($computerEvent) {
            [PSCustomObject]@{
                LastUpdate = Format-DateTimeString $computerEvent.TimeCreated
                EventId    = $computerEvent.Id
                Result     = if ($computerEvent.Id -in 1500,1501,1502) { 'Success' } else { 'Unknown' }
                Message    = $computerEvent.Message
            }
        } else { $null }
        UserPolicy = if ($userEvent) {
            [PSCustomObject]@{
                LastUpdate = Format-DateTimeString $userEvent.TimeCreated
                EventId    = $userEvent.Id
                Result     = if ($userEvent.Id -in 1500,1501,1502) { 'Success' } else { 'Unknown' }
                Message    = $userEvent.Message
            }
        } else { $null }
        LastPolicyUpdate = if ($lastUpdate) { Format-DateTimeString $lastUpdate.TimeCreated } else { $null }
    }
}

$result = Get-GroupPolicyUpdateInfo
$result | ConvertTo-Json -Depth 5
