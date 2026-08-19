<#
Printer information in JSON.
#>
chcp 65001 | Out-Null

$printers = Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue

$result = if ($printers) {
    $printerData = @{}
    foreach ($printer in $printers) {
        $printerInfo = [PSCustomObject]@{
            DriverName      = $printer.DriverName
            PortName        = $printer.PortName
            # Default         = $printer.Default
            Shared          = $printer.Shared
            ShareName       = if ($printer.ShareName) { $printer.ShareName } else { $null }
            Published       = $printer.Published
            PrintProcessor  = if ($printer.PrintProcessor) { $printer.PrintProcessor } else { $null }
        }
        $printerData[$printer.Name] = $printerInfo
    }
    $printerData
} else {
    $null
}

$outResult = [PSCustomObject]@{
    Printers = $result
}

$outResult | ConvertTo-Json -Depth 4