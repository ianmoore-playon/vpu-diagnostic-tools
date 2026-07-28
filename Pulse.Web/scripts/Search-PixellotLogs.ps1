#Requires -Version 5.1
<#
.SYNOPSIS
    Scans Pixellot agent / VPU logs for errors, fatals, and process restarts.
.DESCRIPTION
    Per Pixellot Troubleshooting Tips PDF #5, searching the VPU logs for
    "error", "fatal", and "start new log" is the first step in identifying
    runtime issues. The last marker is especially valuable — it indicates
    a process restart after a crash.

    Searches the last N hours of log files matching:
        vpu*.log
        agent_vpu2_*.log
    in C:\Pixellot\Data\Log\

    Uses findstr.exe (native, encoding-tolerant — same pattern proven safe
    in Get-SystemIdentity.ps1 for these Pixellot log files).

    Also flags known dependency-failure signatures (CUDNN_STATUS_*,
    TensorFlow) so the UI can offer the documented dependency-reinstall
    remedy (PDF #2).

    Outputs JSON to stdout.
.PARAMETER HoursBack
    Hours of log history to scan. Default 24.
.PARAMETER MaxMatches
    Cap on total matches returned (to keep responses bounded on busy hosts).
    Default 500.
#>
[CmdletBinding()]
param(
    [int]$HoursBack = 24,
    [int]$MaxMatches = 500
)

$ErrorActionPreference = 'Stop'

$logDir = 'C:\Pixellot\Data\Log'

try {
    if (-not (Test-Path -LiteralPath $logDir)) {
        [ordered]@{
            entries = @()
            stats = [ordered]@{ error = 0; fatal = 0; restart = 0; total = 0 }
            depsErrorDetected = $false
            scannedFiles = 0
            hoursBack = $HoursBack
            warning = "Log directory not found: $logDir. Pixellot may not be installed."
        } | ConvertTo-Json -Depth 5 -Compress
        return
    }

    $cutoff = (Get-Date).AddHours(-$HoursBack)

    # Find candidate log files — recent + matching name patterns
    $files = Get-ChildItem -Path $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -like 'vpu*' -or $_.Name -like 'agent_vpu2_*') -and
            $_.LastWriteTime -gt $cutoff
        } |
        Sort-Object LastWriteTime -Descending

    $entries = New-Object System.Collections.ArrayList
    $stats = @{ error = 0; fatal = 0; restart = 0 }
    $depsDetected = $false

    # Patterns that mean "Pixellot dependencies are broken — reinstall" (PDF #2)
    $depsErrorRegex = '(CUDNN_STATUS_EXECUTION_FAILED|CUDNN_STATUS|TensorFlow|tensorflow\.python|cudart|libcudnn)'

    foreach ($f in $files) {
        if ($entries.Count -ge $MaxMatches) { break }

        # findstr — case-insensitive, line-numbered, multiple needles.
        # /N adds line numbers, /I makes it case-insensitive, /C: takes a literal needle.
        # 2>$null swallows the "file not found" noise on permission edge cases.
        $matches = & findstr.exe /N /I /C:"error" /C:"fatal" /C:"start new log" $f.FullName 2>$null
        if (-not $matches) { continue }

        # findstr returns string or string[] depending on count — normalize.
        if ($matches -isnot [array]) { $matches = @($matches) }

        foreach ($line in $matches) {
            if ($entries.Count -ge $MaxMatches) { break }

            # Format: "<lineNumber>:<content>"
            if ($line -notmatch '^(\d+):(.*)$') { continue }
            $lineNum = [int]$Matches[1]
            $content = $Matches[2]

            # Classify level — order matters because "fatal" lines also contain "error" sometimes
            $level = 'unknown'
            if     ($content -match '(?i)start new log') { $level = 'restart'; $stats.restart++ }
            elseif ($content -match '(?i)fatal')         { $level = 'fatal';   $stats.fatal++ }
            elseif ($content -match '(?i)error')         { $level = 'error';   $stats.error++ }
            else                                          { continue }  # not actually a match we care about

            # Extract embedded timestamp if present (Pixellot logs use various formats)
            $ts = $null
            if ($content -match '(\d{4}-\d{2}-\d{2}[\sT]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?)') {
                $ts = $Matches[1]
            }

            # Tag dependency-failure signatures (PDF #2 trigger)
            $isDepsError = $false
            if ($content -match $depsErrorRegex) {
                $isDepsError = $true
                $depsDetected = $true
            }

            [void]$entries.Add([ordered]@{
                file       = $f.Name
                lineNumber = $lineNum
                level      = $level
                timestamp  = $ts
                content    = $content.Trim()
                fileMTime  = $f.LastWriteTime.ToString('o')
                depsError  = $isDepsError
            })
        }
    }

    [ordered]@{
        entries           = @($entries)
        stats             = [ordered]@{
            error   = $stats.error
            fatal   = $stats.fatal
            restart = $stats.restart
            total   = $stats.error + $stats.fatal + $stats.restart
        }
        depsErrorDetected = $depsDetected
        scannedFiles      = $files.Count
        hoursBack         = $HoursBack
        truncated         = ($entries.Count -ge $MaxMatches)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Search-PixellotLogs.ps1'
    } | ConvertTo-Json -Compress
}
