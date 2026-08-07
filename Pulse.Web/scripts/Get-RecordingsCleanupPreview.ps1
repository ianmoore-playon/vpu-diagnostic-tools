#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only preview of what the D: recordings cleanup would delete.
.DESCRIPTION
    Enumerates D:\recordedevents with the shared rules in _CleanupCommon.ps1
    and reports the deletable folders in two buckets -- daily test clips
    older than the recent guard, and game recordings older than the
    retention limit -- with per-bucket counts, sizes, and date ranges, plus
    the projected free space if everything listed were deleted.

    This script NEVER deletes anything. The UI shows this preview and the
    tech confirms before Invoke-RecordingsCleanup.ps1 (which re-enumerates
    with the same rules) actually removes folders.
.PARAMETER RecentGuardDays
    Nothing newer than this many days is ever a candidate. Default 90.
.PARAMETER RecordingMaxAgeDays
    Game recordings must be older than this many days. Default 365.
#>
[CmdletBinding()]
param(
    [int]$RecentGuardDays = 90,
    [int]$RecordingMaxAgeDays = 365,
    [string]$Root = 'D:\recordedevents'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_CleanupCommon.ps1')

function _BucketSummary([object[]]$items) {
    $bytes = 0L
    foreach ($i in $items) { if ($null -ne $i.sizeBytes) { $bytes += $i.sizeBytes } }
    $dates = @($items | ForEach-Object { $_.date } | Sort-Object)
    [pscustomobject]@{
        count  = $items.Count
        sizeGB = [math]::Round($bytes / 1GB, 1)
        bytes  = $bytes
        oldest = if ($dates.Count) { $dates[0] } else { $null }
        newest = if ($dates.Count) { $dates[$dates.Count - 1] } else { $null }
    }
}

try {
    $rootError = Test-CleanupRoot -Root $Root
    if ($null -ne $rootError -and $rootError -like '*does not exist*') {
        # A missing recordings folder is a normal state (fresh image), not
        # an error -- report it so the UI can say "nothing to clean".
        [pscustomobject]@{
            rootExists = $false
            root       = $Root
            drive      = Get-CleanupDriveStats
        } | ConvertTo-Json -Depth 5 -Compress
        exit 0
    }
    if ($null -ne $rootError) { throw $rootError }

    $scan = Get-CleanupCandidates -Root $Root -RecentGuardDays $RecentGuardDays `
        -RecordingMaxAgeDays $RecordingMaxAgeDays -IncludeSizes $true

    $daily = @($scan.candidates | Where-Object { $_.category -eq 'dailytest' })
    $recs  = @($scan.candidates | Where-Object { $_.category -eq 'recording' })
    $dailySummary = _BucketSummary $daily
    $recsSummary  = _BucketSummary $recs
    $totalBytes = $dailySummary.bytes + $recsSummary.bytes

    $drive = Get-CleanupDriveStats
    $projectedFreeGB = $null
    $projectedUsedPercent = $null
    if ($null -ne $drive) {
        $projectedFreeGB = [math]::Round($drive.freeGB + ($totalBytes / 1GB), 1)
        if ($drive.sizeGB -gt 0) {
            $projectedUsedPercent = [math]::Round((($drive.sizeGB - $projectedFreeGB) / $drive.sizeGB) * 100, 1)
        }
    }

    [pscustomobject]@{
        rootExists           = $true
        root                 = $Root
        params               = [pscustomobject]@{
            recentGuardDays     = $RecentGuardDays
            recordingMaxAgeDays = $RecordingMaxAgeDays
        }
        drive                = $drive
        dailyTest            = [pscustomobject]@{
            count  = $dailySummary.count
            sizeGB = $dailySummary.sizeGB
            oldest = $dailySummary.oldest
            newest = $dailySummary.newest
        }
        recordings           = [pscustomobject]@{
            count  = $recsSummary.count
            sizeGB = $recsSummary.sizeGB
            oldest = $recsSummary.oldest
            newest = $recsSummary.newest
        }
        totalSizeGB          = [math]::Round($totalBytes / 1GB, 1)
        totalFolders         = $scan.totalFolders
        skippedRecent        = $scan.skippedRecent
        skippedUnrecognized  = @($scan.skippedUnrecognized)
        projectedFreeGB      = $projectedFreeGB
        projectedUsedPercent = $projectedUsedPercent
        candidates           = @($scan.candidates | ForEach-Object {
            [pscustomobject]@{
                name     = $_.name
                category = $_.category
                date     = $_.date
                sizeMB   = if ($null -ne $_.sizeBytes) { [math]::Round($_.sizeBytes / 1MB, 1) } else { $null }
            }
        })
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [pscustomobject]@{
        error   = $true
        message = "$($_.Exception.Message)"
        script  = 'Get-RecordingsCleanupPreview.ps1'
    } | ConvertTo-Json -Compress
}
