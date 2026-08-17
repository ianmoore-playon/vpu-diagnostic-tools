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

    # Physical disks via Storage namespace, enriched with SMART/reliability data.
    # Get-PhysicalDisk only reports a coarse Healthy/Unhealthy rollup; for an SSD
    # fleet the early-warning signals (wear %, uncorrectable errors, power-on
    # hours, drive temperature) come from Get-StorageReliabilityCounter, piped
    # per disk so it matches the drive cleanly without parsing the raw SMART blob.
    $physicalDisks = @()
    try {
        $physicalDisks = Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            $pd = $_
            $smart = $null
            try {
                $rc = $pd | Get-StorageReliabilityCounter -ErrorAction Stop
                if ($rc) {
                    $smart = [ordered]@{
                        wearPercent            = $rc.Wear
                        powerOnHours           = $rc.PowerOnHours
                        temperatureC           = $rc.Temperature
                        readErrorsUncorrected  = $rc.ReadErrorsUncorrected
                        writeErrorsUncorrected = $rc.WriteErrorsUncorrected
                    }
                }
            }
            catch { }
            [ordered]@{
                friendlyName      = $pd.FriendlyName
                mediaType         = $pd.MediaType
                busType           = $pd.BusType
                healthStatus      = "$($pd.HealthStatus)"
                operationalStatus = ($pd.OperationalStatus -join ', ')
                sizeGB            = [math]::Round($pd.Size / 1GB, 2)
                smart             = $smart
            }
        }
    }
    catch { }

    # OS-level SMART pre-failure flag. MSStorageDriver_FailurePredictStatus is the
    # inbox WMI class that surfaces each drive's own "predict failure" boolean -- no
    # kernel driver or raw register access involved. Any drive predicting failure
    # flips the top-level flag the dashboard finding keys on.
    $predictFailure = $false
    try {
        $fp = Get-CimInstance -Namespace root\WMI -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop
        foreach ($f in @($fp)) {
            if ($f.PredictFailure) { $predictFailure = $true }
        }
    }
    catch { }

    # Disk event errors (last 24 hours)
    $diskEvents = @()
    try {
        $startTime = (Get-Date).AddHours(-24)
        # Include the filesystem/volume providers (Ntfs/volmgr/partmgr), not just
        # the controller/driver ones -- chkdsk-corruption and bad-block events
        # (e.g. Ntfs eventId 55) live there and were previously never collected.
        $events = Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'disk', 'nvme', 'iaStorAC', 'Ntfs', 'volmgr', 'partmgr'
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
        logicalDisks   = @($logicalDisks)
        physicalDisks  = @($physicalDisks)
        predictFailure = $predictFailure
        diskEvents     = @($diskEvents)
        pixellotPaths  = @($pathSizes)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-DiskHealth.ps1'
    } | ConvertTo-Json -Compress
}
