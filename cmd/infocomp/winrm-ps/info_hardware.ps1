<#
.SYNOPSIS
    Собирает детальную информацию об оборудовании и выводит валидный JSON.
    В случае ошибки выводит сообщение в stderr и завершается с кодом 1.
#>

# --- Helper Functions ---
chcp 65001 | Out-Null
function Convert-KBToBytes {
    param([uint64]$KB)
    if ($null -eq $KB) { return $null }
    return [uint64]($KB * 1024)
}

function Get-SizeRecord {
    param(
        [uint64]$TotalKB,
        [uint64]$FreeKB
    )
    if ($null -eq $TotalKB -or $null -eq $FreeKB) {
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
        UsedBytes  = if ($null -ne $total -and $null -ne $free) { [uint64]($total - $free) } else { $null }
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
            UsedBytes   = if ($null -ne $total -and $null -ne $free) { [uint64]($total - $free) } else { $null }
            FreeBytes   = $free
        }
    }
}

# --- Main Execution Block ---

try {
    # 1. Operating System & Memory
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    
    # 2. Processors
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name              = $_.Name
            PhysicalCores     = $_.NumberOfCores
            LogicalProcessors = $_.NumberOfLogicalProcessors
            Manufacturer      = $_.Manufacturer
            Architecture      = $_.Architecture
        }
    })

    # 3. Motherboard
    $motherboard = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
    $moboInfo = [PSCustomObject]@{
        Manufacturer = if ($motherboard) { $motherboard.Manufacturer } else { $null }
        Product      = if ($motherboard) { $motherboard.Product } else { $null }
        Name         = if ($motherboard) { $motherboard.Name } else { $null }
        SerialNumber = if ($motherboard) { $motherboard.SerialNumber } else { $null }
    }

    # 4. Memory Details
    $physicalMemory = Get-SizeRecord -TotalKB $os.TotalVisibleMemorySize -FreeKB $os.FreePhysicalMemory
    $virtualMemory  = Get-SizeRecord -TotalKB $os.TotalVirtualMemorySize -FreeKB $os.FreeVirtualMemory

    $pageFileUsage = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop | Select-Object -First 1
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

    # 5. Physical Disks & Volumes
    $physicalDisks = @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | ForEach-Object {
        $mediaType = if ($_.MediaType) { $_.MediaType } else { $_.InterfaceType }
        [PSCustomObject]@{
            DeviceID     = $_.DeviceID
            Model        = $_.Model
            MediaType    = $mediaType
            SerialNumber = $_.SerialNumber
            SizeBytes    = if ($_.Size) { [uint64]$_.Size } else { $null }
            Volumes      = @(Get-LogicalVolumesForDisk -Disk $_)
        }
    })

    # 6. Removable Storage
    $removableStorage = @(Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -in 2, 5 } | ForEach-Object {
        $total = if ($_.Size) { [uint64]$_.Size } else { $null }
        $free  = if ($_.FreeSpace) { [uint64]$_.FreeSpace } else { $null }
        [PSCustomObject]@{
            Name        = $_.DeviceID
            VolumeName  = $_.VolumeName
            TotalBytes  = $total
            UsedBytes   = if ($null -ne $total -and $null -ne $free) { [uint64]($total - $free) } else { $null }
            FreeBytes   = $free
        }
    })

    # 7. Video Controllers
    $videoControllers = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name            = $_.Name
            AdapterRAMBytes = if ($_.AdapterRAM) { [uint64]$_.AdapterRAM } else { $null }
            DriverVersion   = $_.DriverVersion
            VideoProcessor  = $_.VideoProcessor
        }
    })

    # --- Assembly ---
    $result = [PSCustomObject]@{
        Processors       = $processors
        Motherboard      = $moboInfo
        Memory           = [PSCustomObject]@{
            PhysicalMemory = $physicalMemory
            VirtualMemory  = $virtualMemory
            PageFile       = $pageFile
        }
        PhysicalDisks    = $physicalDisks
        RemovableStorage = $removableStorage
        VideoControllers = $videoControllers
    }

    # Convert to JSON with strict error handling
    $jsonOutput = $result | ConvertTo-Json -Depth 6 -ErrorAction Stop
    
    # Output ONLY valid JSON to stdout
    Write-Output $jsonOutput
    exit 0

} catch {
    # On any error, write to stderr and exit with code 1
    Write-Error "Hardware inventory failed: $($_.Exception.Message)"
    exit 1
}