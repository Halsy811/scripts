<#
Basic system information in JSON.
#>
chcp 65001 | Out-Null

$system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$result = [PSCustomObject]@{
    ComputerName = if ($system) { $system.Name } else { $null }
    DomainName   = if ($system) { if ($system.PartOfDomain) { $system.Domain } else { $system.Workgroup } } else { $null }
}

$outResult = [PSCustomObject]@{
    Basic = $result
}

$outResult | ConvertTo-Json -Depth 4
