<#
Basic system information in JSON.
#>
[CmdletBinding()]
param()

$system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$result = [PSCustomObject]@{
    ComputerName = if ($system) { $system.Name } else { $null }
    DomainName   = if ($system) { if ($system.PartOfDomain) { $system.Domain } else { $system.Workgroup } } else { $null }
}
$result | ConvertTo-Json -Depth 4
