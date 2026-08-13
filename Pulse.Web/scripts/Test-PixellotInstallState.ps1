#Requires -Version 5.1
<#
.SYNOPSIS
    Detects half-finished Pixellot installer runs (PDF #3).
.DESCRIPTION
    Pixellot's installer downloads its payload as numbered part files
    (part_1, part_2, part_3, ...) into c:\pixellot\downloadedversion\
    and writes a log file in the same directory. A successful install
    ends with "Rebooting..." as the final non-empty line of that log.

    If part files are present AND the most recent installer log's last
    line is NOT "Rebooting...", the install is incomplete and should be
    resumed.

    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$dir = 'C:\pixellot\downloadedversion'

try {
    if (-not (Test-Path -LiteralPath $dir)) {
        [ordered]@{
            dirExists  = $false
            incomplete = $false
            message    = "Directory not present: $dir"
            partFiles  = @()
            log        = $null
        } | ConvertTo-Json -Depth 4 -Compress
        return
    }

    # Collect part files -- matches .part_1, .part_2, .part_3, and the
    # common .part1/.part2 variants some Pixellot versions emit.
    $partFiles = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.part_?\d+($|\.)' } |
        Sort-Object Name |
        ForEach-Object {
            [ordered]@{
                name       = $_.Name
                sizeMB     = [math]::Round($_.Length / 1MB, 1)
                lastWrite  = $_.LastWriteTime.ToString('o')
            }
        })

    # Find the most recent log file in the directory. Match common
    # installer log naming patterns (.log, install_log_*.txt).
    $logCandidate = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.log', '.txt' -or $_.Name -match 'install.*log' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    $logInfo = $null
    $lastLine = $null
    $rebooting = $false

    if ($logCandidate) {
        # Read with shared mode in case the installer still has it open
        try {
            $fs = [System.IO.File]::Open($logCandidate.FullName, 'Open', 'Read', 'ReadWrite')
            try {
                $sr = New-Object System.IO.StreamReader($fs)
                try {
                    $content = $sr.ReadToEnd()
                } finally { $sr.Dispose() }
            } finally { $fs.Dispose() }

            # Get the last non-empty line
            $lines = $content -split "`r?`n" | Where-Object { $_.Trim() -ne '' }
            if ($lines.Count -gt 0) {
                $lastLine = $lines[-1].Trim()
                $rebooting = $lastLine -match '(?i)^reboot(ing)?\.{0,3}$'
            }
        } catch {
            $lastLine = "(unable to read log: $($_.Exception.Message))"
        }

        $logInfo = [ordered]@{
            path       = $logCandidate.FullName
            name       = $logCandidate.Name
            sizeKB     = [math]::Round($logCandidate.Length / 1KB, 1)
            lastWrite  = $logCandidate.LastWriteTime.ToString('o')
            lastLine   = $lastLine
        }
    }

    # Incomplete if part files exist AND (no log OR last line is not "Rebooting...")
    $incomplete = ($partFiles.Count -gt 0) -and (-not $rebooting)

    [ordered]@{
        dirExists  = $true
        dir        = $dir
        incomplete = $incomplete
        rebooting  = $rebooting
        partFiles  = @($partFiles)
        partCount  = $partFiles.Count
        log        = $logInfo
        message    = if ($incomplete) {
            "Half-finished install: $($partFiles.Count) part file(s) present and log does not end with 'Rebooting...'."
        } elseif ($rebooting) {
            "Last install completed (log ends with 'Rebooting...')."
        } else {
            "No part files; nothing to resume."
        }
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-PixellotInstallState.ps1'
    } | ConvertTo-Json -Compress
}
