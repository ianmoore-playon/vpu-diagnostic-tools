#Requires -Version 5.1
<#
.SYNOPSIS
    Validate that cameras are actually streaming video (not just pinging).
.DESCRIPTION
    For each camera IP, captures a short RTSP clip with ffmpeg (stream copy,
    no re-encode) and inspects it with ffprobe to confirm a real video
    stream — codec, frame rate, resolution. "Responds to ping" only proves
    the NIC link; this proves the camera is producing decodable video.

    ffmpeg/ffprobe ship with Pixellot at C:\Pixellot\Bin\ffmpeg. If they're
    missing we report available=false rather than erroring.

    Adapted from Canopy videoTest.ps1. Two changes for Pulse:
      - Camera IPs are passed in (-CameraIps) instead of read from the
        Banyan leaf_services.json — Pulse already detects them.
      - The localhost:8000 HTTP POST is stripped; results go to stdout JSON.

    This is SLOW (DurationSec per camera). Wire it to an explicit "Verify
    Video" button, never the live poll.
.PARAMETER CameraIps
    Comma-separated camera IPs to test, e.g. "169.254.16.50,169.254.16.51".
.PARAMETER Labels
    Optional comma-separated labels parallel to CameraIps (e.g. camera
    role) for friendlier output. Falls back to the IP.
.PARAMETER DurationSec
    Capture length per camera in seconds. Default 60 (Canopy default);
    shorter values trade confidence for speed.
.PARAMETER StreamPath
    RTSP stream path. Default "stream1" (Pixellot/Dynacolor primary).
.OUTPUTS
    { available, durationSec, results: [ { ip, label, ok, codec,
      frameRate, resolution, error } ] }
#>
[CmdletBinding()]
param(
    [string] $CameraIps   = "",
    [string] $Labels      = "",
    [int]    $DurationSec  = 60,
    [string] $StreamPath   = "stream1"
)

$ErrorActionPreference = 'Stop'

$ffmpeg  = 'C:\Pixellot\Bin\ffmpeg\ffmpeg.exe'
$ffprobe = 'C:\Pixellot\Bin\ffmpeg\ffprobe.exe'

function Out-Json($obj) { $obj | ConvertTo-Json -Depth 6 -Compress }

try {
    if (-not (Test-Path $ffmpeg) -or -not (Test-Path $ffprobe)) {
        Out-Json ([ordered]@{
            available = $false
            reason    = "ffmpeg/ffprobe not found at C:\Pixellot\Bin\ffmpeg. Cannot validate video."
            results   = @()
        })
        return
    }

    $ips = @($CameraIps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $lbls = @($Labels -split ',' | ForEach-Object { $_.Trim() })
    if ($ips.Count -eq 0) {
        Out-Json ([ordered]@{
            available = $true
            reason    = "No camera IPs supplied."
            results   = @()
        })
        return
    }

    # Convert ffprobe's avg_frame_rate fraction ("30000/1001") to a number.
    function Convert-FrameRate($fr) {
        if (-not $fr -or $fr -eq "0/0") { return $null }
        $parts = $fr -split '/'
        if ($parts.Count -eq 2 -and [double]$parts[1] -ne 0) {
            return [math]::Round([double]$parts[0] / [double]$parts[1], 2)
        }
        try { return [math]::Round([double]$fr, 2) } catch { return $null }
    }

    $tmpDir = Join-Path $env:TEMP "pulse-videotest"
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null

    $results = @()
    for ($i = 0; $i -lt $ips.Count; $i++) {
        $ip    = $ips[$i]
        $label = if ($i -lt $lbls.Count -and $lbls[$i]) { $lbls[$i] } else { $ip }
        $clip  = Join-Path $tmpDir ("cam_" + ($ip -replace '[^0-9A-Za-z]', '_') + ".mkv")
        $url   = "rtsp://$ip/$StreamPath"

        $entry = [ordered]@{
            ip = $ip; label = $label; ok = $false
            codec = $null; frameRate = $null; resolution = $null; error = $null
        }

        try {
            if (Test-Path $clip) { Remove-Item $clip -Force -ErrorAction SilentlyContinue }
            # Capture by stream copy (no re-encode) — fast and faithful.
            & $ffmpeg -rtsp_transport tcp -y -i $url -t $DurationSec -c copy $clip *>$null

            if (-not (Test-Path $clip) -or (Get-Item $clip).Length -eq 0) {
                $entry.error = "No video captured (camera not streaming on $url)."
                $results += $entry
                continue
            }

            $probeRaw = & $ffprobe -v quiet -show_entries `
                "stream=codec_type,codec_name,avg_frame_rate,width,height" `
                -of json -i $clip 2>$null
            $probe = $probeRaw | ConvertFrom-Json
            $vstream = $probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1

            if ($vstream) {
                $entry.codec     = $vstream.codec_name
                $entry.frameRate = Convert-FrameRate $vstream.avg_frame_rate
                if ($vstream.width -and $vstream.height) {
                    $entry.resolution = "$($vstream.width)x$($vstream.height)"
                }
                $entry.ok = [bool]($entry.codec -and $entry.frameRate -and $entry.frameRate -gt 0)
                if (-not $entry.ok) { $entry.error = "Video stream present but codec/frame rate invalid." }
            } else {
                $entry.error = "Captured file has no video stream."
            }
        }
        catch {
            $entry.error = $_.Exception.Message
        }
        finally {
            if (Test-Path $clip) { Remove-Item $clip -Force -ErrorAction SilentlyContinue }
        }
        $results += $entry
    }

    Out-Json ([ordered]@{
        available   = $true
        durationSec = $DurationSec
        results     = @($results)
    })
}
catch {
    Out-Json ([ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-CameraVideo.ps1'
    })
}
