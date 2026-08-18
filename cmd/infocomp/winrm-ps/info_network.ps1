<#
Network adapter information in JSON.
#>
chcp 65001 | Out-Null

$networkConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Address -or $_.IPv6Address }
$interfaces = foreach ($config in $networkConfigs) {
    $ipInterface = Get-NetIPInterface -InterfaceIndex $config.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $dnsServers = if ($config.DnsServer) { $config.DnsServer.ServerAddresses } else { @() }
    $adapter = Get-NetAdapter -InterfaceIndex $config.InterfaceIndex -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        AdapterName  = $config.InterfaceAlias
        Description  = $config.InterfaceDescription
        DHCPEnabled  = if ($ipInterface) { $ipInterface.Dhcp -eq 'Enabled' } else { $false }
        DHCPServer   = if ($config.DhcpServer) { $config.DhcpServer.IPAddressToString } else { $null }
        DNSServers   = $dnsServers
        IPAddresses  = if ($config.IPv4Address) { $config.IPv4Address | ForEach-Object { [PSCustomObject]@{ Address = $_.IPAddress; PrefixLength = $_.PrefixLength } } } else { @() }
        Gateways     = if ($config.IPv4DefaultGateway) { $config.IPv4DefaultGateway | ForEach-Object { $_.NextHop } } else { @() }
        MacAddress   = if ($adapter) { $adapter.MacAddress } else { $null }
        Status       = if ($adapter) { $adapter.Status } else { if ($config.NetAdapter) { $config.NetAdapter.Status } else { $null } }
    }
}

$result = [PSCustomObject]@{
    NetworkAdapters = $interfaces
}
$result | ConvertTo-Json -Depth 5
