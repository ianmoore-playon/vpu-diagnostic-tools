#Requires -Version 5.1
<#
.SYNOPSIS
    Collects disk health data for VPU diagnostics.
.DESCRIPTION
    Gathers logical disk info, physical disk health, recent disk-related
    event log errors, and Pixellot directory sizes. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Logical disks (fixed drives only)
    $logicalDisks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [ordered]@{
            deviceID   = $_.DeviceID
            volumeName = $_.VolumeName
            fileSystem = $_.FileSystem
            sizeGB     = [math]::Round($_.Size / 1GB, 2)
            freeSpaceGB = [math]::Round($_.FreeSpace / 1GB, 2)
            usedPercent = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
        }
    }

    # Physical disks via Storage namespace
    $physicalDisks = @()
    try {
        $physicalDisks = Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            [ordered]@{
                friendlyName      = $_.FriendlyName
                mediaType         = $_.MediaType
                busType           = $_.BusType
                healthStatus      = $_.HealthStatus
                operationalStatus = $_.OperationalStatus
                sizeGB            = [math]::Round($_.Size / 1GB, 2)
            }
        }
    }
    catch { }

    # Disk event errors (last 24 hours)
    $diskEvents = @()
    try {
        $startTime = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'disk', 'nvme', 'iaStorAC'
            Level        = 1, 2, 3
            StartTime    = $startTime
        } -MaxEvents 20 -ErrorAction SilentlyContinue

        if ($events) {
            $diskEvents = @($events | ForEach-Object {
                [ordered]@{
                    timeCreated = $_.TimeCreated.ToString('o')
                    level       = switch ($_.Level) { 1 { 'Critical' } 2 { 'Error' } 3 { 'Warning' } default { $_.LevelDisplayName } }
                    source      = $_.ProviderName
                    eventId     = $_.Id
                    message     = if ($_.Message.Length -gt 500) { $_.Message.Substring(0, 500) } else { $_.Message }
                }
            })
        }
    }
    catch { }

    # Pixellot directory sizes
    $pathSizes = @()
    $pixellotPaths = @(
        'D:\Pixellot\Recordings'
        'D:\Pixellot\Storage'
        'D:\Pixellot\PixellotAgent\logs'
    )

    foreach ($dirPath in $pixellotPaths) {
        if (Test-Path $dirPath) {
            try {
                $measurement = Get-ChildItem -Path $dirPath -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum
                $sizeGB = if ($measurement.Sum) { [math]::Round($measurement.Sum / 1GB, 2) } else { 0 }
                $pathSizes += [ordered]@{
                    path   = $dirPath
                    sizeGB = $sizeGB
                    fileCount = $measurement.Count
                }
            }
            catch {
                $pathSizes += [ordered]@{
                    path  = $dirPath
                    error = $_.Exception.Message
                }
            }
        }
    }

    [ordered]@{
        logicalDisks  = @($logicalDisks)
        physicalDisks = @($physicalDisks)
        diskEvents    = @($diskEvents)
        pixellotPaths = @($pathSizes)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-DiskHealth.ps1'
    } | ConvertTo-Json -Compress
}
