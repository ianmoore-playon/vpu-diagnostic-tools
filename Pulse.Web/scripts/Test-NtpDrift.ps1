#Requires -Version 5.1
<#
.SYNOPSIS
    Checks NTP time drift against time.windows.com.
.DESCRIPTION
    Runs w32tm stripchart, parses offset, and classifies result.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $source = 'time.windows.com'
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
        ok            = $ok
        status        = $status
        offsetSeconds = $offsetSeconds
        source        = $source
        rawOutput     = $rawOutput
    } | ConvertTo-Json -Depth 3 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-NtpDrift.ps1'
    } | ConvertTo-Json -Compress
}
