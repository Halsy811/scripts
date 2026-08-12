<#
Hardware inventory information in JSON.
#>
[CmdletBinding()]
param()

function Convert-KBToBytes {
    param([uint64]$KB)
    return if ($KB -ne $null) { [uint64]($KB * 1024) } else { $null }
}

function Get-SizeRecord {
    param(
        [uint64]$TotalKB,
        [uint64]$FreeKB
    )
    if ($TotalKB -eq $null -or $FreeKB -eq $null) {
        return [PSCustomObject]@{
            TotalBytes = $null
            UsedBytes  = $null
            FreeBytes  = $null
        }
    }
    $total = Convert-KBToBytes -KB $TotalKB
    $free = Convert-KBToBytes -KB $FreeKB
    [PSCustomObject]@{
        TotalBytes = $total
        UsedBytes  = if ($total -ne $null -and $free -ne $null) { [uint64]($total - $free) } else { $null }
        FreeBytes  = $free
    }
}

function Get-LogicalVolumesForDisk {
    param($Disk)
    $partitions = Get-CimAssociatedInstance -InputObject $Disk -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue
    if (-not $partitions) { return @() }
    $volumes = foreach ($partition in $partitions) {
        Get-CimAssociatedInstance -InputObject $partition -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue
    }
    return $volumes | Where-Object { $_ } | ForEach-Object {
        $total = if ($_.Size) { [uint64]$_.Size } else { $null }
        $free  = if ($_.FreeSpace) { [uint64]$_.FreeSpace } else { $null }
        [PSCustomObject]@{
            VolumeName  = $_.VolumeName
            DeviceID    = $_.DeviceID
            FileSystem  = $_.FileSystem
            TotalBytes  = $total
            UsedBytes   = if ($total -ne $null -and $free -ne $null) { [uint64]($total - $free) } else { $null }
            FreeBytes   = $free
        }
    }
}

$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$processors = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Name                 = $_.Name
        PhysicalCores        = $_.NumberOfCores
        LogicalProcessors    = $_.NumberOfLogicalProcessors
        Manufacturer         = $_.Manufacturer
        Architecture         = $_.Architecture
    }
}

$motherboard = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
$physicalMemory = if ($os) { Get-SizeRecord -TotalKB $os.TotalVisibleMemorySize -FreeKB $os.FreePhysicalMemory } else { $null }
$virtualMemory  = if ($os) { Get-SizeRecord -TotalKB $os.TotalVirtualMemorySize -FreeKB $os.FreeVirtualMemory } else { $null }

$pageFileUsage = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue | Select-Object -First 1
$pageFile = if ($pageFileUsage) {
    [PSCustomObject]@{
        CurrentSizeMB = $pageFileUsage.AllocatedBaseSize
        UsedMB        = $pageFileUsage.CurrentUsage
        PercentUsed   = if ($pageFileUsage.AllocatedBaseSize -gt 0) { [math]::Round(($pageFileUsage.CurrentUsage / $pageFileUsage.AllocatedBaseSize) * 100, 2) } else { $null }
    }
} else {
    [PSCustomObject]@{
        CurrentSizeMB = $null
        UsedMB        = $null
        PercentUsed   = $null
    }
}

$physicalDisks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
    $mediaType = if ($_.MediaType) { $_.MediaType } else { $_.InterfaceType }
    [PSCustomObject]@{
        DeviceID     = $_.DeviceID
        Model        = $_.Model
        MediaType    = $mediaType
        SerialNumber = $_.SerialNumber
        SizeBytes    = if ($_.Size) { [uint64]$_.Size } else { $null }
        Volumes      = Get-LogicalVolumesForDisk -Disk $_
    }
}

$removableStorage = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2, 5 } | ForEach-Object {
    $total = if ($_.Size) { [uint64]$_.Size } else { $null }
    $free  = if ($_.FreeSpace) { [uint64]$_.FreeSpace } else { $null }
    [PSCustomObject]@{
        Name        = $_.DeviceID
        VolumeName  = $_.VolumeName
        TotalBytes  = $total
        UsedBytes   = if ($total -ne $null -and $free -ne $null) { [uint64]($total - $free) } else { $null }
        FreeBytes   = $free
    }
}

$videoControllers = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
    [PSCustomObject]@{
        Name            = $_.Name
        AdapterRAMBytes = if ($_.AdapterRAM) { [uint64]$_.AdapterRAM } else { $null }
        DriverVersion   = $_.DriverVersion
        VideoProcessor  = $_.VideoProcessor
    }
}

$result = [PSCustomObject]@{
    Processors      = $processors
    Motherboard     = [PSCustomObject]@{
        Manufacturer = if ($motherboard) { $motherboard.Manufacturer } else { $null }
        Product      = if ($motherboard) { $motherboard.Product } else { $null }
        Name         = if ($motherboard) { $motherboard.Name } else { $null }
        SerialNumber = if ($motherboard) { $motherboard.SerialNumber } else { $null }
    }
    Memory = [PSCustomObject]@{
        PhysicalMemory = $physicalMemory
        VirtualMemory  = $virtualMemory
        PageFile       = $pageFile
    }
    PhysicalDisks    = $physicalDisks
    RemovableStorage = $removableStorage
    VideoControllers = $videoControllers
}
$result | ConvertTo-Json -Depth 6
