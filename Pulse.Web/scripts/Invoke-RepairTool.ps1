#Requires -Version 5.1
<#
.SYNOPSIS
    Runs a Windows image / file repair command and tails CBS.log on completion.
.DESCRIPTION
    Per Pixellot Troubleshooting Tips PDF #1, the documented system-image
    repair sequence is:
        DISM /Online /Cleanup-Image /CheckHealth      (fast -- ~30s)
        DISM /Online /Cleanup-Image /RestoreHealth    (slow -- 5-20 min)
        sfc /scannow                                  (slow -- 10-30 min)
        chkdsk /f /r C:                               (schedules for next boot)

    The CBS log at C:\Windows\Logs\CBS\CBS.log captures the detailed
    progress of all four; we tail the last N lines after each run so the
    UI can show what the tool actually did.
.PARAMETER Action
    One of: CheckHealth | RestoreHealth | SfcScan | ChkdskSchedule
.PARAMETER CbsTailLines
    Lines of CBS.log to return after completion. Default 75.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('CheckHealth', 'RestoreHealth', 'SfcScan', 'ChkdskSchedule')]
    [string]$Action,
    [int]$CbsTailLines = 75
)

$ErrorActionPreference = 'Stop'
$cbsLogPath = 'C:\Windows\Logs\CBS\CBS.log'

function _TailCbs([int]$lines) {
    if (-not (Test-Path -LiteralPath $cbsLogPath)) { return @() }
    try {
        # CBS.log can be open by TrustedInstaller -- read with shared mode.
        $fs = [System.IO.File]::Open($cbsLogPath, 'Open', 'Read', 'ReadWrite')
        try {
            $sr = New-Object System.IO.StreamReader($fs)
            try {
                $all = $sr.ReadToEnd() -split "`r?`n"
                if ($all.Count -le $lines) { return $all }
                return $all[($all.Count - $lines)..($all.Count - 1)]
            } finally { $sr.Dispose() }
        } finally { $fs.Dispose() }
    } catch {
        return @("(unable to read CBS.log: $($_.Exception.Message))")
    }
}

function _RunProcess([string]$exe, [string[]]$args, [int]$timeoutSec) {
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $args `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr

        # Don't use Start-Process -Wait -- we want a timeout cap.
        if (-not $proc.WaitForExit($timeoutSec * 1000)) {
            try { $proc.Kill() } catch {}
            return @{
                exitCode = -1
                stdout = (Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) -as [string]
                stderr = (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue) -as [string]
                timedOut = $true
            }
        }
        @{
            exitCode = $proc.ExitCode
            stdout   = (Get-Content -LiteralPath $tmpOut -Raw -ErrorAction SilentlyContinue) -as [string]
            stderr   = (Get-Content -LiteralPath $tmpErr -Raw -ErrorAction SilentlyContinue) -as [string]
            timedOut = $false
        }
    } finally {
        Remove-Item -LiteralPath $tmpOut -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpErr -ErrorAction SilentlyContinue
    }
}

try {
    $cmd     = $null
    $args    = @()
    $timeout = 60
    switch ($Action) {
        'CheckHealth' {
            $cmd     = 'dism.exe'
            $args    = @('/Online', '/Cleanup-Image', '/CheckHealth')
            $timeout = 180
        }
        'RestoreHealth' {
            $cmd     = 'dism.exe'
            $args    = @('/Online', '/Cleanup-Image', '/RestoreHealth')
            $timeout = 1800  # up to 30 min
        }
        'SfcScan' {
            $cmd     = 'sfc.exe'
            $args    = @('/scannow')
            $timeout = 1800
        }
        'ChkdskSchedule' {
            # `chkdsk /f /r C:` on the system drive can't run live --
            # Windows responds by asking "Schedule for next reboot?".
            # Piping "Y`n" answers yes; the command then returns
            # immediately and the actual check runs on next boot.
            $cmd     = 'cmd.exe'
            $args    = @('/c', 'echo Y | chkdsk C: /f /r')
            $timeout = 60
        }
    }

    $runStart = Get-Date
    $r = _RunProcess -exe $cmd -args $args -timeoutSec $timeout
    $runMs = [int]((Get-Date) - $runStart).TotalMilliseconds

    [ordered]@{
        action       = $Action
        success      = (-not $r.timedOut) -and ($r.exitCode -eq 0 -or ($Action -eq 'ChkdskSchedule' -and $r.exitCode -ne $null))
        exitCode     = $r.exitCode
        timedOut     = $r.timedOut
        durationMs   = $runMs
        command      = "$cmd $($args -join ' ')"
        stdout       = if ($r.stdout) { $r.stdout.Trim() } else { '' }
        stderr       = if ($r.stderr) { $r.stderr.Trim() } else { '' }
        cbsTail      = @(_TailCbs -lines $CbsTailLines)
        cbsLogPath   = $cbsLogPath
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        success = $false
        message = $_.Exception.Message
        action  = $Action
        script  = 'Invoke-RepairTool.ps1'
    } | ConvertTo-Json -Compress
}
