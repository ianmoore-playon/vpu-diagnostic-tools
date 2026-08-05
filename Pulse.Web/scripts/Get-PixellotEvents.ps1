# Get-PixellotEvents.ps1 -- LOCAL collector
#
# Enumerates the Pixellot recording folders under D:\recordedEvents to answer
# "what events has this box actually run recently, and did each one record?"
# Folder naming (verified on a real VPU, firmware 5.x):
#   YYYY-MM-DD_p_<24-hex pixellot event id>   -> a scheduled cloud event
#   YYYY-MM-DD_p_DAILYTEST<YYYYMMDD>          -> Pixellot's nightly self-test
# Each folder may contain:
#   event.log  -- first line carries the event name:
#                 "2026-08-04 02:13:07|Event_Name|Beta_mass_event_schedule 04.08.26|v3|PROD|"
#                 later lines log artifact PREPARED/UPLOADED steps
#   *.mkv/*.mp4 -- the actual recordings (size > 0 proves the box recorded)
# The event ids join to the NFHS cloud APIs (Unity pixellots/broadcasts/{id})
# server-side; this script is purely local filesystem reads.

param(
    [int]$DaysBack = 21,
    [int]$MaxEvents = 40
)

$ErrorActionPreference = 'Stop'

try {
    $root = 'D:\recordedEvents'
    $events = @()
    $dailyTests = @()
    $available = $false

    if (Test-Path $root) {
        $available = $true
        $cutoff = (Get-Date).Date.AddDays(-$DaysBack)

        $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $dirs) {
            if ($dir.Name -notmatch '^(\d{4}-\d{2}-\d{2})_p_(.+)$') { continue }
            $dateStr = $Matches[1]
            $idPart  = $Matches[2]

            $folderDate = $null
            try { $folderDate = [datetime]::ParseExact($dateStr, 'yyyy-MM-dd', $null) } catch { continue }
            if ($folderDate -lt $cutoff) { continue }

            if ($idPart -match '^DAILYTEST') {
                $dailyTests += [pscustomobject]@{
                    date   = $dateStr
                    folder = $dir.Name
                }
                continue
            }
            if ($idPart -notmatch '^[0-9a-f]{24}$') { continue }

            # Recording evidence: total bytes of video containers in the folder.
            $videoBytes = [long]0
            try {
                $vids = Get-ChildItem -Path $dir.FullName -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -eq '.mkv' -or $_.Extension -eq '.mp4' }
                foreach ($v in $vids) { $videoBytes += [long]$v.Length }
            } catch { }

            # Event name + upload steps from the per-event log.
            $eventName = $null
            $uploadedCount = 0
            try {
                $evLog = Join-Path $dir.FullName 'event.log'
                if (Test-Path $evLog) {
                    $lines = @(Get-Content -Path $evLog -ErrorAction SilentlyContinue)
                    foreach ($line in $lines) {
                        if ($null -eq $eventName -and $line -match '\|Event_Name\|([^|]+)\|') {
                            $eventName = $Matches[1].Trim()
                        }
                        if ($line -match '\|UPLOADED\|https') { $uploadedCount++ }
                    }
                }
            } catch { }

            $events += [pscustomobject]@{
                eventId       = $idPart
                date          = $dateStr
                name          = $eventName
                videoBytes    = $videoBytes
                uploadedCount = $uploadedCount
                folder        = $dir.Name
                lastWriteTime = $dir.LastWriteTime.ToString('o')
            }
        }

        # Newest first; cap to keep the payload bounded.
        $events = @($events | Sort-Object -Property date -Descending | Select-Object -First $MaxEvents)
        $dailyTests = @($dailyTests | Sort-Object -Property date -Descending | Select-Object -First 14)
    }

    $result = [ordered]@{
        available          = $available
        recordedEventsPath = $root
        daysBack           = $DaysBack
        events             = $events
        dailyTests         = $dailyTests
    }

    $result | ConvertTo-Json -Depth 4 -Compress
}
catch {
    $err = [ordered]@{
        error   = $true
        message = $_.Exception.Message
    }
    $err | ConvertTo-Json -Compress
}
