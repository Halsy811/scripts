<#
Operating system information in JSON.
#>

$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$result = [PSCustomObject]@{
    OSName        = if ($os) { $os.Caption } else { $null }
    Version       = if ($os) { $os.Version } else { $null }
    BuildNumber   = if ($os) { $os.BuildNumber } else { $null }
    Architecture  = if ($os) { $os.OSArchitecture } else { $null }
    ServicePack   = if ($os) { "$($os.ServicePackMajorVersion).$($os.ServicePackMinorVersion)" } else { $null }
}
$result | ConvertTo-Json -Depth 4
