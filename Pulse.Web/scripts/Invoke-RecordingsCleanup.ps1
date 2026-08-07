#Requires -Version 5.1
<#
.SYNOPSIS
    Deletes old event folders from D:\recordedevents. DESTRUCTIVE.
.DESCRIPTION
    Pulse's storage cleanup action. Re-enumerates the deletable folders
    with the same shared rules as the preview (_CleanupCommon.ps1) at
    execution time -- it never accepts a folder list from the caller, so a
    stale preview or a tampered request can't widen what gets deleted:

      * daily test clips (name contains DAILYTEST) older than the recent
        guard (default 90 days)
      * game recordings (name is date_p_<24-hex event id>) older than the
        retention limit (default 365 days)

    Nothing newer than the recent guard is ever touched, unrecognized
    folder names are never touched, and each folder's name, age, and
    reparse status are re-verified immediately before its Remove-Item.
    Deletion is permanent (no recycle bin), so the UI must show the
    preview and get an explicit confirmation first.
.PARAMETER Acknowledge
    Must be the literal string DELETE. Refuses to run otherwise -- a
    belt-and-braces guard so the script can't fire from a bare endpoint
    hit or a mistyped manual invocation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Acknowledge,
    [int]$RecentGuardDays = 90,
    [int]$RecordingMaxAgeDays = 365,
    [string]$Root = 'D:\recordedevents'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_CleanupCommon.ps1')

try {
    if ($Acknowledge -cne 'DELETE') {
        throw "Refusing to run: -Acknowledge must be the literal string DELETE."
    }
    $rootError = Test-CleanupRoot -Root $Root
    if ($null -ne $rootError) { throw $rootError }

    $runStart = Get-Date
    $before = Get-CleanupDriveStats

    $scan = Get-CleanupCandidates -Root $Root -RecentGuardDays $RecentGuardDays `
        -RecordingMaxAgeDays $RecordingMaxAgeDays -IncludeSizes $true

    $guardCutoff = (Get-Date).AddDays(-1 * $RecentGuardDays)
    $deleted = New-Object 'System.Collections.Generic.List[object]'
    $failed  = New-Object 'System.Collections.Generic.List[object]'
    $freedBytes = 0L

    foreach ($c in $scan.candidates) {
        try {
            # Re-verify per folder right before deleting: it must still
            # exist, still not be a reparse point, and still be older than
            # the recent guard. Anything that changed since enumeration is
            # skipped, not deleted.
            if (-not (Test-Path -LiteralPath $c.path -PathType Container)) { continue }
            $item = Get-Item -LiteralPath $c.path
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                $failed.Add([pscustomobject]@{ name = $c.name; error = 'became a reparse point; skipped' })
                continue
            }
            if ($item.CreationTime -ge $guardCutoff -or $item.LastWriteTime -ge $guardCutoff) {
                $failed.Add([pscustomobject]@{ name = $c.name; error = 'modified since enumeration; skipped' })
                continue
            }

            Remove-Item -LiteralPath $c.path -Recurse -Force -ErrorAction Stop
            if (Test-Path -LiteralPath $c.path) {
                # 5.1's Remove-Item -Recurse can hit a transient
                # directory-not-empty race on deep trees; one retry.
                Start-Sleep -Milliseconds 200
                Remove-Item -LiteralPath $c.path -Recurse -Force -ErrorAction Stop
            }

            $freedBytes += [long]$c.sizeBytes
            $deleted.Add([pscustomobject]@{
                name     = $c.name
                category = $c.category
                date     = $c.date
                sizeMB   = [math]::Round($c.sizeBytes / 1MB, 1)
            })
        } catch {
            $failed.Add([pscustomobject]@{ name = $c.name; error = "$($_.Exception.Message)" })
        }
    }

    $after = Get-CleanupDriveStats
    $deletedDaily = @($deleted | Where-Object { $_.category -eq 'dailytest' })
    $deletedRecs  = @($deleted | Where-Object { $_.category -eq 'recording' })

    [pscustomobject]@{
        success           = ($failed.Count -eq 0)
        deletedCount      = $deleted.Count
        deletedDailyTest  = $deletedDaily.Count
        deletedRecordings = $deletedRecs.Count
        failedCount       = $failed.Count
        freedGB           = [math]::Round($freedBytes / 1GB, 1)
        before            = $before
        after             = $after
        durationMs        = [int]((Get-Date) - $runStart).TotalMilliseconds
        # .ToArray(), never @(...): on PS 5.1 a Generic List wrapped in @()
        # inside a [pscustomobject] literal dies with "Argument types do not
        # match" (found on the bench VPU; pwsh 7 and demo mode both hide it).
        deleted           = $deleted.ToArray()
        failed            = $failed.ToArray()
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [pscustomobject]@{
        error   = $true
        message = "$($_.Exception.Message)"
        script  = 'Invoke-RecordingsCleanup.ps1'
    } | ConvertTo-Json -Compress
}
