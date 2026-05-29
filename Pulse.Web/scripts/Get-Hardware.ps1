#Requires -Version 5.1
<#
.SYNOPSIS
    Collects hardware inventory for VPU diagnostics.
.DESCRIPTION
    Gathers CPU, RAM, GPU, disk, and hotfix data. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # CPU
    $cpus = Get-CimInstance Win32_Processor | ForEach-Object {
        [ordered]@{
            name                     = $_.Name
            maxClockSpeedMHz         = $_.MaxClockSpeed
            numberOfCores            = $_.NumberOfCores
            numberOfLogicalProcessors = $_.NumberOfLogicalProcessors
            socketDesignation        = $_.SocketDesignation
            l2CacheSizeKB            = $_.L2CacheSize
            l3CacheSizeKB            = $_.L3CacheSize
        }
    }

    # Memory type map
    $memTypeMap = @{
        20 = 'DDR'
        21 = 'DDR2'
        24 = 'DDR3'
        26 = 'DDR4'
        34 = 'DDR5'
    }

    # Physical memory
    $ram = Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $typeCode = $_.SMBIOSMemoryType
        [ordered]@{
            capacityGB    = [math]::Round($_.Capacity / 1GB, 2)
            speedMHz      = $_.Speed
            manufacturer  = $_.Manufacturer
            deviceLocator = $_.DeviceLocator
            partNumber    = if ($_.PartNumber) { $_.PartNumber.Trim() } else { $null }
            memoryType    = if ($memTypeMap.ContainsKey([int]$typeCode)) { $memTypeMap[[int]$typeCode] } else { "Unknown ($typeCode)" }
        }
    }

    # GPU — adapted from Canopy/Leaf/checkDedicatedGpu.ps1.
    # Pixellot VPUs require a dedicated NVIDIA or AMD GPU for encoding.
    # Intel iGPUs alone won't run the encoder — surface vendor + an
    # isDedicated flag so _compute_findings can flag wrong-hardware hosts.
    $gpus = Get-CimInstance Win32_VideoController | ForEach-Object {
        $compat = $_.AdapterCompatibility
        $vendor = switch -Regex ($compat) {
            '^NVIDIA'       { 'NVIDIA';    break }
            '^(AMD|ATI)'    { 'AMD';       break }
            '^Intel'        { 'Intel';     break }
            '^Microsoft'    { 'Microsoft'; break }
            default         { if ($compat) { $compat } else { 'Unknown' } }
        }
        [ordered]@{
            name                 = $_.Name
            adapterRAMMB         = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1MB, 0) } else { $null }
            driverVersion        = $_.DriverVersion
            driverDate           = if ($_.DriverDate) { $_.DriverDate.ToString('o') } else { $null }
            adapterCompatibility = $compat
            vendor               = $vendor
            # Dedicated = NVIDIA or AMD with actual VRAM. Intel iGPUs and
            # Microsoft Basic Display / Remote Desktop adapters report as
            # not-dedicated regardless of AdapterRAM.
            isDedicated          = ($vendor -in @('NVIDIA', 'AMD')) -and ($_.AdapterRAM -gt 0)
        }
    }

    # Monitors
    $monitorCount = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction SilentlyContinue).Count

    # Disk drives (WMI)
    $disks = Get-CimInstance Win32_DiskDrive | ForEach-Object {
        [ordered]@{
            index            = $_.Index
            sizeGB           = [math]::Round($_.Size / 1GB, 2)
            interfaceType    = $_.InterfaceType
            model            = $_.Model
            serialNumber     = if ($_.SerialNumber) { $_.SerialNumber.Trim() } else { $null }
            firmwareRevision = $_.FirmwareRevision
        }
    }

    # Physical disks (Storage namespace)
    $physicalDisks = @()
    try {
        $physicalDisks = Get-CimInstance -Namespace root/Microsoft/Windows/Storage -ClassName MSFT_PhysicalDisk -ErrorAction Stop | ForEach-Object {
            [ordered]@{
                friendlyName    = $_.FriendlyName
                busType         = $_.BusType
                mediaType       = $_.MediaType
                firmwareVersion = $_.FirmwareVersion
                serialNumber    = if ($_.SerialNumber) { $_.SerialNumber.Trim() } else { $null }
            }
        }
    }
    catch { }

    # Last hotfix
    $lastKB = $null
    try {
        $hf = Get-CimInstance Win32_QuickFixEngineering |
            Where-Object { $_.InstalledOn } |
            Sort-Object InstalledOn -Descending |
            Select-Object -First 1
        if ($hf) {
            $lastKB = [ordered]@{
                hotFixID    = $hf.HotFixID
                installedOn = $hf.InstalledOn.ToString('o')
                description = $hf.Description
            }
        }
    }
    catch { }

    $result = [ordered]@{
        processors    = @($cpus)
        memory        = @($ram)
        gpus          = @($gpus)
        monitorCount  = $monitorCount
        diskDrives    = @($disks)
        physicalDisks = @($physicalDisks)
        lastHotfix    = $lastKB
    }

    $result | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-Hardware.ps1'
    } | ConvertTo-Json -Compress
}
