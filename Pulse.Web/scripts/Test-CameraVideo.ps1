#Requires -Version 5.1
<#
.SYNOPSIS
    Confirm each camera is producing decodable video by grabbing a single frame.
.DESCRIPTION
    For each camera IP, grabs ONE JPEG frame from the RTSP stream with ffmpeg
    and reads codec/frame-rate/resolution with ffprobe. A successfully decoded
    frame proves the camera is streaming real video — far stronger than a ping,
    and near-instant compared to capturing a full clip.

    Returns the frame as a base64 data URI so the UI can show a thumbnail —
    a tech can see at a glance whether the image is black, lens-capped, or
    pointed wrong, not just whether bytes flow.

    ffmpeg/ffprobe ship with Pixellot at C:\Pixellot\Bin\ffmpeg. If they're
    missing we report available=false rather than erroring. Adapted from
    Canopy videoTest.ps1 (60s clip -> single frame; localhost POST stripped).
.PARAMETER CameraIps
    Comma-separated camera IPs, e.g. "169.254.16.50,169.254.16.51".
.PARAMETER Labels
    Optional comma-separated labels parallel to CameraIps.
.PARAMETER StreamPath
    RTSP stream path. Default "stream1" (Pixellot/Dynacolor primary).
.PARAMETER MaxWidth
    Thumbnail width in px (height auto). Default 480 — small payload, legible.
.OUTPUTS
    { available, results: [ { ip, label, ok, codec, frameRate, resolution,
      image, error } ] }   # image = "data:image/jpeg;base64,..." or null
#>
[CmdletBinding()]
param(
    [string] $CameraIps  = "",
    [string] $Labels     = "",
    [string] $StreamPath  = "stream1",
    [int]    $MaxWidth     = 480
)

$ErrorActionPreference = 'Stop'

$ffmpeg  = 'C:\Pixellot\Bin\ffmpeg\ffmpeg.exe'
$ffprobe = 'C:\Pixellot\Bin\ffmpeg\ffprobe.exe'

function Out-Json($obj) { $obj | ConvertTo-Json -Depth 6 -Compress }

try {
    if (-not (Test-Path $ffmpeg) -or -not (Test-Path $ffprobe)) {
        Out-Json ([ordered]@{
            available = $false
            reason    = "ffmpeg/ffprobe not found at C:\Pixellot\Bin\ffmpeg. Cannot capture frames."
            results   = @()
        })
        return
    }

    $ips  = @($CameraIps -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $lbls = @($Labels -split ',' | ForEach-Object { $_.Trim() })
    if ($ips.Count -eq 0) {
        Out-Json ([ordered]@{ available = $true; reason = "No camera IPs supplied."; results = @() })
        return
    }

    function Convert-FrameRate($fr) {
        if (-not $fr -or $fr -eq "0/0") { return $null }
        $parts = $fr -split '/'
        if ($parts.Count -eq 2 -and [double]$parts[1] -ne 0) {
            return [math]::Round([double]$parts[0] / [double]$parts[1], 2)
        }
        try { return [math]::Round([double]$fr, 2) } catch { return $null }
    }

    $tmpDir = Join-Path $env:TEMP "pulse-frametest"
    New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null

    $results = @()
    for ($i = 0; $i -lt $ips.Count; $i++) {
        $ip    = $ips[$i]
        $label = if ($i -lt $lbls.Count -and $lbls[$i]) { $lbls[$i] } else { $ip }
        $frame = Join-Path $tmpDir ("cam_" + ($ip -replace '[^0-9A-Za-z]', '_') + ".jpg")
        $url   = "rtsp://$ip/$StreamPath"

        $entry = [ordered]@{
            ip = $ip; label = $label; ok = $false
            codec = $null; frameRate = $null; resolution = $null
            image = $null; error = $null
        }

        try {
            # Stream metadata (fast header read; -stimeout bounds a hung camera).
            $probeRaw = & $ffprobe -rtsp_transport tcp -stimeout 6000000 -v quiet `
                -show_entries "stream=codec_type,codec_name,avg_frame_rate,width,height" `
                -of json -i $url 2>$null
            if ($probeRaw) {
                $vstream = ($probeRaw | ConvertFrom-Json).streams |
                    Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
                if ($vstream) {
                    $entry.codec     = $vstream.codec_name
                    $entry.frameRate = Convert-FrameRate $vstream.avg_frame_rate
                    if ($vstream.width -and $vstream.height) {
                        $entry.resolution = "$($vstream.width)x$($vstream.height)"
                    }
                }
            }

            # Grab a single decoded frame, scaled down for a thumbnail.
            if (Test-Path $frame) { Remove-Item $frame -Force -ErrorAction SilentlyContinue }
            & $ffmpeg -rtsp_transport tcp -stimeout 8000000 -y -i $url `
                -frames:v 1 -an -vf "scale=$($MaxWidth):-1" -q:v 5 $frame *>$null

            if ((Test-Path $frame) -and (Get-Item $frame).Length -gt 0) {
                $bytes = [System.IO.File]::ReadAllBytes($frame)
                $entry.image = "data:image/jpeg;base64," + [System.Convert]::ToBase64String($bytes)
                $entry.ok = $true
            } else {
                $entry.error = "No frame captured (camera not streaming on $url)."
            }
        }
        catch {
            $entry.error = $_.Exception.Message
        }
        finally {
            if (Test-Path $frame) { Remove-Item $frame -Force -ErrorAction SilentlyContinue }
        }
        $results += $entry
    }

    Out-Json ([ordered]@{ available = $true; results = @($results) })
}
catch {
    Out-Json ([ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-CameraVideo.ps1'
    })
}
