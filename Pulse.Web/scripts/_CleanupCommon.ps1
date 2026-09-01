#Requires -Version 5.1
<#
.SYNOPSIS
    Shared candidate enumeration for the D: recordings cleanup.
.DESCRIPTION
    Dot-sourced by Get-RecordingsCleanupPreview.ps1 (read-only) and
    Invoke-RecordingsCleanup.ps1 (destructive) so both scripts decide
    "what is deletable" with EXACTLY the same rules. The action script
    re-enumerates at execution time -- it never trusts a list computed
    earlier or sent by the client.

    Deletion rules (a folder must match ALL of these to be a candidate):
      * It is a direct child of the root (default D:\recordedevents).
      * Its name matches one of two strict patterns:
          - daily test clip:  YYYY-MM-DD_p_...DAILYTEST...
          - game recording:   YYYY-MM-DD_p_<24-hex event id>
        Anything else (including Pixellot artifacts like "0001-01-01_p_")
        is reported as unrecognized and never touched.
      * It is not a reparse point (junction/symlink) -- those could reach
        outside the root.
      * It is old enough. Age is judged on the NEWEST of the name date,
        CreationTime, and LastWriteTime, so a folder that is still being
        written to never qualifies. Daily test clips must be older than
        the recent guard (default 90 days); game recordings must be older
        than the retention limit (default 365 days). The guard always
        wins: nothing newer than RecentGuardDays is a candidate, ever.

    Keep this file pure ASCII (see the note in _AudioInterop.ps1).
#>

function Get-CleanupCandidates {
    param(
        [string]$Root = 'D:\recordedevents',
        [int]$RecentGuardDays = 90,
        [int]$RecordingMaxAgeDays = 365,
        [bool]$IncludeSizes = $true
    )

    $now = Get-Date
    $guardCutoff = $now.AddDays(-1 * $RecentGuardDays)
    $recordingCutoff = $now.AddDays(-1 * $RecordingMaxAgeDays)
    # The recent guard is a floor for BOTH categories: if someone passes a
    # RecordingMaxAgeDays shorter than the guard, the guard still wins.
    if ($recordingCutoff -gt $guardCutoff) { $recordingCutoff = $guardCutoff }

    $candidates = New-Object 'System.Collections.Generic.List[object]'
    $unrecognized = New-Object 'System.Collections.Generic.List[string]'
    $skippedRecent = 0
    $totalFolders = 0

    foreach ($dir in @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction Stop)) {
        $totalFolders++

        if ($dir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $unrecognized.Add($dir.Name)
            continue
        }

        $category = $null
        if ($dir.Name -match '^\d{4}-\d{2}-\d{2}_p_\w*DAILYTEST\w*$') {
            $category = 'dailytest'
        } elseif ($dir.Name -match '^\d{4}-\d{2}-\d{2}_p_[0-9a-f]{24}$') {
            $category = 'recording'
        } else {
            $unrecognized.Add($dir.Name)
            continue
        }

        $nameDate = [datetime]::MinValue
        $parsedOk = [datetime]::TryParseExact(
            $dir.Name.Substring(0, 10), 'yyyy-MM-dd',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None, [ref]$nameDate)
        if (-not $parsedOk) {
            # Regex-shaped but not a real date (e.g. month 13) -- refuse it.
            $unrecognized.Add($dir.Name)
            continue
        }

        $effective = $nameDate
        if ($dir.CreationTime -gt $effective) { $effective = $dir.CreationTime }
        if ($dir.LastWriteTime -gt $effective) { $effective = $dir.LastWriteTime }

        $cutoff = if ($category -eq 'dailytest') { $guardCutoff } else { $recordingCutoff }
        if ($effective -ge $cutoff) {
            $skippedRecent++
            continue
        }

        $sizeBytes = $null
        if ($IncludeSizes) {
            $sum = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sum) { $sum = 0 }
            $sizeBytes = [long]$sum
        }

        $candidates.Add([pscustomobject]@{
            name      = $dir.Name
            path      = $dir.FullName
            category  = $category
            date      = $effective.ToString('yyyy-MM-dd')
            sizeBytes = $sizeBytes
        })
    }

    # Lists become plain arrays here (.ToArray()) so no caller can trip PS
    # 5.1's "Argument types do not match" by re-wrapping a Generic List in
    # @() inside a [pscustomobject] literal.
    [pscustomobject]@{
        candidates          = $candidates.ToArray()
        totalFolders        = $totalFolders
        skippedRecent       = $skippedRecent
        skippedUnrecognized = $unrecognized.ToArray()
    }
}

function Get-CleanupDriveStats {
    param([string]$DriveLetter = 'D')
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${DriveLetter}:'" -ErrorAction SilentlyContinue
    if ($null -eq $disk -or $null -eq $disk.Size -or [long]$disk.Size -eq 0) { return $null }
    [pscustomobject]@{
        letter      = $DriveLetter
        sizeGB      = [math]::Round($disk.Size / 1GB, 1)
        freeGB      = [math]::Round($disk.FreeSpace / 1GB, 1)
        usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
    }
}

function Test-CleanupRoot {
    <# Root must be a real directory on D:, and never the drive root itself.
       Returns an error string, or $null when the root is acceptable. #>
    param([string]$Root)
    if ($Root -notmatch '^[Dd]:\\.+') {
        return "Cleanup root must be a folder on D: (got '$Root')."
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return "Cleanup root '$Root' does not exist."
    }
    $item = Get-Item -LiteralPath $Root -ErrorAction Stop
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        return "Cleanup root '$Root' is a junction/symlink, so cleanup refuses to run."
    }
    return $null
}
