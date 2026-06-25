#Requires -Version 5.1
<#
.SYNOPSIS
    Reports whether the VPU is actively encoding (recording/streaming) right now,
    so the proactive-monitoring loop can back off intrusive probes during a game.
.DESCRIPTION
    The #1 risk of background monitoring is perturbing live video, so before the
    loop runs an intrusive network probe it asks: is the encoder busy?

    Pixellot encodes on the NVIDIA GPU (the readiness engine treats an NVIDIA GPU
    as the required encoder). A live capture holds an NVENC session and drives
    the hardware encoder, so we read that directly with nvidia-smi — the same
    tool Get-GpuInfo.ps1 already depends on, no new footprint:

        encoder.stats.sessionCount  → active NVENC sessions
        utilization.encoder         → % the encoder is busy (sampled)

    "Recording" = the encoder is actually doing work. We prefer encoder
    utilization (a held-but-idle session reads 0%); if the driver doesn't expose
    utilization we fall back to sessionCount > 0. Values are taken as the MAX
    across GPUs (a multi-GPU box only needs one encoder busy to be "recording").

    Fail-open: if nvidia-smi is missing or errors we report recording=false with
    detectable=false — the loop then runs its normal recompute. (Freezing on
    "unknown" would mean the port probe never runs; on a real VPU nvidia-smi is
    present, and the soak validates the idle-vs-recording reading.)

    Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    # Encoder-utilization % at/above which we treat the box as actively
    # encoding. 0 means "any non-zero encoder work counts."
    [int]$UtilizationThreshold = 0
)

$ErrorActionPreference = 'Stop'

function _ParseNum([string]$raw) {
    # nvidia-smi emits "[Not Supported]" / "[N/A]" for unsupported fields.
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $t = $raw.Trim()
    if ($t -match '\[.*\]') { return $null }       # [Not Supported], [N/A]
    $n = 0
    if ([int]::TryParse($t, [ref]$n)) { return $n }
    return $null
}

try {
    $smiCmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if (-not $smiCmd) {
        [ordered]@{
            recording   = $false
            detectable  = $false
            source      = 'none'
            note        = 'nvidia-smi not found — cannot detect encoder activity'
        } | ConvertTo-Json -Compress
        return
    }

    $out = & $smiCmd.Source `
        --query-gpu=encoder.stats.sessionCount,utilization.encoder `
        --format=csv,noheader,nounits 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $out) {
        [ordered]@{
            recording   = $false
            detectable  = $false
            source      = 'nvidia-smi'
            note        = "nvidia-smi exited with code $LASTEXITCODE"
        } | ConvertTo-Json -Compress
        return
    }

    $lines = if ($out -is [array]) { $out } else { @($out) }
    $maxSessions = $null
    $maxUtil     = $null
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split ','
        if ($parts.Count -lt 2) { continue }
        $sessions = _ParseNum $parts[0]
        $util     = _ParseNum $parts[1]
        if ($null -ne $sessions -and ($null -eq $maxSessions -or $sessions -gt $maxSessions)) { $maxSessions = $sessions }
        if ($null -ne $util     -and ($null -eq $maxUtil     -or $util     -gt $maxUtil))     { $maxUtil = $util }
    }

    # Prefer utilization (idle held sessions read 0%); fall back to session count.
    if ($null -ne $maxUtil) {
        $recording = ($maxUtil -gt $UtilizationThreshold)
    } elseif ($null -ne $maxSessions) {
        $recording = ($maxSessions -gt 0)
    } else {
        # Encoder fields unsupported on this driver/GPU — can't tell.
        [ordered]@{
            recording   = $false
            detectable  = $false
            source      = 'nvidia-smi'
            sessionCount = $maxSessions
            encoderUtilizationPercent = $maxUtil
            note        = 'encoder stats not supported by this driver'
        } | ConvertTo-Json -Compress
        return
    }

    [ordered]@{
        recording                 = [bool]$recording
        detectable                = $true
        source                    = 'nvidia-smi'
        sessionCount              = $maxSessions
        encoderUtilizationPercent = $maxUtil
    } | ConvertTo-Json -Compress
}
catch {
    [ordered]@{
        recording  = $false
        detectable = $false
        source     = 'nvidia-smi'
        error      = $true
        message    = $_.Exception.Message
        script     = 'Get-RecordingState.ps1'
    } | ConvertTo-Json -Compress
}
