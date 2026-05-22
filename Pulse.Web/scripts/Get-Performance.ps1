#Requires -Version 5.1
<#
.SYNOPSIS
    Collects live performance metrics for VPU diagnostics.
.DESCRIPTION
    Gathers CPU load, memory usage, disk usage, and temperature.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # CPU usage
    $cpuAvg = (Get-CimInstance Win32_Processor |
        Measure-Object -Property LoadPercentage -Average).Average
    $cpuPercent = [math]::Round($cpuAvg, 1)

    # Memory
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMemKB = $os.TotalVisibleMemorySize
    $freeMemKB  = $os.FreePhysicalMemory
    $usedMemKB  = $totalMemKB - $freeMemKB
    $memPercent = [math]::Round(($usedMemKB / $totalMemKB) * 100, 1)

    # Disk usage (all fixed drives)
    $logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    $totalDiskBytes = ($logicalDisks | Measure-Object -Property Size -Sum).Sum
    $freeDiskBytes  = ($logicalDisks | Measure-Object -Property FreeSpace -Sum).Sum
    $usedDiskBytes  = $totalDiskBytes - $freeDiskBytes
    $diskPercent = if ($totalDiskBytes -gt 0) {
        [math]::Round(($usedDiskBytes / $totalDiskBytes) * 100, 1)
    } else { 0 }

    $diskDetails = $logicalDisks | ForEach-Object {
        $pct = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
        [ordered]@{
            drive       = $_.DeviceID
            sizeGB      = [math]::Round($_.Size / 1GB, 2)
            freeGB      = [math]::Round($_.FreeSpace / 1GB, 2)
            usedPercent = $pct
        }
    }

    # Temperature — multi-source fallback
    $tempCelsius = $null
    $tempSource  = 'unavailable'

    # Try 1: MSAcpi_ThermalZoneTemperature (values in tenths of Kelvin)
    try {
        $thermal = Get-CimInstance -Namespace root\WMI -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
        if ($thermal) {
            $readings = $thermal | ForEach-Object {
                [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
            } | Where-Object { $_ -gt 0 -and $_ -lt 110 }
            if ($readings) {
                $tempCelsius = ($readings | Measure-Object -Maximum).Maximum
                $tempSource = 'MSAcpi_ThermalZoneTemperature'
            }
        }
    }
    catch { }

    # Try 2: ThermalZoneInformation perf counter
    if ($null -eq $tempCelsius) {
        try {
            $perfThermal = Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop
            if ($perfThermal) {
                $maxTemp = ($perfThermal | Measure-Object -Property Temperature -Maximum).Maximum
                $converted = [math]::Round($maxTemp - 273.15, 1)
                if ($converted -gt 0 -and $converted -lt 110) {
                    $tempCelsius = $converted
                    $tempSource = 'Win32_PerfFormattedData_Counters_ThermalZoneInformation'
                }
            }
        }
        catch { }
    }

    $result = [ordered]@{
        cpu = [ordered]@{
            usagePercent = $cpuPercent
        }
        memory = [ordered]@{
            totalMB      = [math]::Round($totalMemKB / 1024, 0)
            usedMB       = [math]::Round($usedMemKB / 1024, 0)
            freeMB       = [math]::Round($freeMemKB / 1024, 0)
            usedPercent  = $memPercent
        }
        disk = [ordered]@{
            totalGB     = [math]::Round($totalDiskBytes / 1GB, 2)
            usedGB      = [math]::Round($usedDiskBytes / 1GB, 2)
            freeGB      = [math]::Round($freeDiskBytes / 1GB, 2)
            usedPercent = $diskPercent
            drives      = @($diskDetails)
        }
        temperature = [ordered]@{
            celsius = $tempCelsius
            source  = $tempSource
        }
    }

    $result | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-Performance.ps1'
    } | ConvertTo-Json -Compress
}
