#Requires -Version 5.1
<#
.SYNOPSIS
    Checks NTP time drift against the VPU's configured time source.
.DESCRIPTION
    Measures clock offset using w32tm /stripchart. The reference server is
    the source the VPU is actually configured to sync with (w32tm /query
    /source) so the reported drift matches the "NTP server" shown in the UI.

    If the box isn't syncing from a network time source (Local CMOS Clock /
    Free-running System Clock), we fall back to an independent reference
    (time.windows.com) so we can still report whether the clock is accurate,
    and set networkSynced=false so the UI can flag the misconfiguration.

    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # ── Determine the configured time source ─────────────────────
    # Drift should be measured against the server the VPU actually syncs
    # with, not a hardcoded reference — otherwise a box pointed at a bad
    # NTP server would still report "in sync" against time.windows.com.
    $configuredSource = $null
    try {
        $srcOut = & w32tm /query /source 2>&1 | Out-String
        if ($srcOut) {
            # Strip any trailing ",0x9"-style config flag so the value is a
            # clean hostname usable as the /stripchart /computer: target.
            $configuredSource = ($srcOut.Trim() -replace ',0x[0-9A-Fa-f]+\s*$', '').Trim()
        }
    }
    catch { }

    # "Local CMOS Clock" / "Free-running System Clock" mean the box isn't
    # syncing from any network source. Those aren't valid stripchart targets,
    # so fall back to an independent reference and flag it.
    $fallbackRef = 'time.windows.com'
    $networkSynced = $true
    $source = $configuredSource
    if (-not $source -or
        $source -match 'Local CMOS Clock' -or
        $source -match 'Free-running' -or
        $source -match 'unspecified') {
        $networkSynced = $false
        $source = $fallbackRef
    }

    $rawOutput = $null
    $offsetSeconds = $null
    $ok = $false
    $status = 'fail'

    try {
        # Run w32tm with a 5-second timeout to avoid hanging on unreachable NTP
        $job = Start-Job -ScriptBlock {
            & w32tm /stripchart /computer:$using:source /samples:1 /dataonly 2>&1 | Out-String
        }
        $completed = Wait-Job -Job $job -Timeout 5
        if ($completed) {
            $rawOutput = (Receive-Job -Job $job).Trim()
        }
        else {
            Stop-Job -Job $job
            $rawOutput = 'Timeout waiting for NTP response'
        }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

        # Parse offset from output line like: "12:34:56, +00.1234567s"
        # or "12:34:56, -02.5000000s"
        if ($rawOutput -match '[+-]\d+\.\d+s') {
            $offsetMatch = [regex]::Match($rawOutput, '([+-]\d+\.\d+)s')
            if ($offsetMatch.Success) {
                $offsetSeconds = [math]::Round([double]$offsetMatch.Groups[1].Value, 4)
            }
        }
    }
    catch {
        $rawOutput = $_.Exception.Message
    }

    # Determine status
    if ($null -ne $offsetSeconds) {
        $absOffset = [math]::Abs($offsetSeconds)
        if ($absOffset -lt 1) {
            $ok = $true
            $status = 'ok'
        }
        elseif ($absOffset -lt 5) {
            $ok = $true
            $status = 'warn'
        }
        else {
            $ok = $false
            $status = 'fail'
        }
    }

    [ordered]@{
        ok               = $ok
        status           = $status
        offsetSeconds    = $offsetSeconds
        source           = $source            # server drift was measured against
        configuredSource = $configuredSource  # what the VPU is set to sync from
        networkSynced    = $networkSynced
        rawOutput        = $rawOutput
    } | ConvertTo-Json -Depth 3 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-NtpDrift.ps1'
    } | ConvertTo-Json -Compress
}
