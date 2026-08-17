#Requires -Version 5.1
<#
.SYNOPSIS
    Confirm each camera is producing decodable video by grabbing a single frame.
.DESCRIPTION
    For each camera IP, grabs ONE JPEG frame from the RTSP stream with ffmpeg
    and reads codec/frame-rate/resolution with ffprobe. A successfully decoded
    frame proves the camera is streaming real video -- far stronger than a ping,
    and near-instant compared to capturing a full clip.

    Returns the frame as a base64 data URI so the UI can show a thumbnail --
    a tech can see at a glance whether the image is black, lens-capped, or
    pointed wrong, not just whether bytes flow.

    RTSP auth: Dynacolor/Pixellot cameras require credentials on the RTSP
    stream (same Admin/1234 as the CGI probe), so they're baked into the URL.

    RTSP path varies by camera OEM: Pixellot's own cameras answer on
    "stream1", but some box cameras (e.g. nessyMediaServer-based units) only
    serve "h264". We try the preferred path first and, on a 404, fall back
    through a short list of known paths, recording which one decoded.

    ffmpeg/ffprobe ship with Pixellot at C:\Pixellot\Bin\ffmpeg. If they're
    missing we report available=false. -hide_banner keeps the version banner
    out of the output; stderr is captured to a file so a real failure reason
    (401, timeout, no route) surfaces instead of noise.

    Adapted from Canopy videoTest.ps1 (60s clip -> single frame; localhost
    POST stripped).
.PARAMETER CameraIps
    Comma-separated camera IPs, e.g. "169.254.16.50,169.254.16.51".
.PARAMETER Labels
    Optional comma-separated labels parallel to CameraIps.
.PARAMETER StreamPath
    Preferred RTSP stream path, tried first. Default "stream1"
    (Pixellot/Dynacolor primary). On a 404 a short list of other known OEM
    paths (h264, stream0, live, ...) is tried before giving up.
.PARAMETER RtspUser / RtspPass
    RTSP credentials. Default Admin / 1234 (Pixellot factory default).
.PARAMETER MaxWidth
    Thumbnail width in px (height auto). Default 640.
.OUTPUTS
    { available, results: [ { ip, label, ok, codec, frameRate, resolution,
      streamPath, image, error, luma } ] }   # image = "data:image/jpeg;base64,..."
      # or null; streamPath = the RTSP path that decoded (e.g. "h264");
      # luma = { yavg, ymin, ymax, uavg, vavg } 0-255 brightness/chroma of the
      # captured frame (or null) so the server can spot a genuinely black image.
#>
[CmdletBinding()]
param(
    [string] $CameraIps  = "",
    [string] $Labels     = "",
    [string] $StreamPath  = "stream1",
    [string] $RtspUser    = "Admin",
    [string] $RtspPass    = "1234",
    [int]    $MaxWidth     = 640
)

# Native ffmpeg/ffprobe write to stderr and return non-zero on a dead camera;
# that's expected, not a script failure -- don't let it abort the run.
$ErrorActionPreference = 'Continue'

$ffmpeg  = 'C:\Pixellot\Bin\ffmpeg\ffmpeg.exe'
$ffprobe = 'C:\Pixellot\Bin\ffmpeg\ffprobe.exe'

function Out-Json($obj) { $obj | ConvertTo-Json -Depth 6 -Compress }

# Concise, single-line failure reason from an ffmpeg/ffprobe stderr file --
# the last meaningful line, never the version banner.
function Get-FailReason($errFile) {
    if (-not (Test-Path $errFile)) { return $null }
    $lines = Get-Content $errFile -ErrorAction SilentlyContinue |
        Where-Object { $_ -and $_.Trim() -ne "" -and $_ -notmatch '^ffmpeg version|^ffprobe version|^\s*built with|^\s*configuration:|^\s*lib' }
    if (-not $lines) { return $null }
    $last = ($lines | Select-Object -Last 1).Trim()
    if ($last.Length -gt 180) { $last = $last.Substring(0, 180) + "..." }
    return $last
}

# Average/min/max luminance (0-255) and mean chroma of a captured frame, via
# ffmpeg's signalstats filter. The "metadata=print" sink writes "key=value"
# lines (no file= option, so we sidestep the Windows drive-colon escaping trap
# in the filtergraph); *> captures them whether the build prints to stdout or
# the log. Returns $null if stats can't be read -- never throws, so a frame
# still surfaces even if this analysis pass fails.
function Get-FrameLuma($framePath) {
    $statsFile = "$framePath.stats"
    try {
        & $ffmpeg -hide_banner -loglevel error -i $framePath `
            -vf "signalstats,metadata=print" -an -f null NUL *> $statsFile
        if (-not (Test-Path $statsFile)) { return $null }
        $txt = Get-Content $statsFile -Raw -ErrorAction SilentlyContinue
        if (-not $txt) { return $null }
        $luma = [ordered]@{ yavg = $null; ymin = $null; ymax = $null; uavg = $null; vavg = $null }
        foreach ($k in @('YAVG', 'YMIN', 'YMAX', 'UAVG', 'VAVG')) {
            if ($txt -match "lavfi\.signalstats\.$k=([0-9.]+)") {
                $luma[$k.ToLower()] = [math]::Round([double]$matches[1], 1)
            }
        }
        if ($null -eq $luma.yavg) { return $null }
        return $luma
    } catch {
        return $null
    } finally {
        if (Test-Path $statsFile) { Remove-Item $statsFile -Force -ErrorAction SilentlyContinue }
    }
}

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

    # RTSP stream path varies by camera OEM. Try the preferred path first
    # (StreamPath, default "stream1" for Pixellot/Dynacolor), then fall back
    # through other known paths. Dedupe but keep order so the preferred path
    # always wins when it works.
    $fallbackPaths = @('stream1', 'h264', 'stream0', 'live', 'media/video1', 'video1', 'live/ch0')
    $candidatePaths = @()
    foreach ($p in (@($StreamPath) + $fallbackPaths)) {
        $p = "$p".Trim().Trim('/')
        if ($p -and ($candidatePaths -notcontains $p)) { $candidatePaths += $p }
    }

    $results = @()
    for ($i = 0; $i -lt $ips.Count; $i++) {
        $ip    = $ips[$i]
        $label = if ($i -lt $lbls.Count -and $lbls[$i]) { $lbls[$i] } else { $ip }
        $frame   = Join-Path $tmpDir ("cam_" + ($ip -replace '[^0-9A-Za-z]', '_') + ".jpg")
        $errFile = Join-Path $tmpDir ("cam_" + ($ip -replace '[^0-9A-Za-z]', '_') + ".err")
        $entry = [ordered]@{
            ip = $ip; label = $label; ok = $false
            codec = $null; frameRate = $null; resolution = $null
            streamPath = $null; image = $null; error = $null; luma = $null
        }

        try {
            # Walk candidate paths until one decodes a frame. ffmpeg is the
            # real test (a header read can pass where decode fails), so grab
            # the frame per path and probe metadata only for the winner.
            $usedPath = $null
            $reason   = $null
            foreach ($path in $candidatePaths) {
                $url = "rtsp://$($RtspUser):$($RtspPass)@$ip/$path"
                if (Test-Path $frame) { Remove-Item $frame -Force -ErrorAction SilentlyContinue }
                & $ffmpeg -hide_banner -loglevel error -rtsp_transport tcp -stimeout 8000000 `
                    -y -i $url -frames:v 1 -an -vf "scale=$($MaxWidth):-1" -q:v 4 $frame 2>$errFile 1>$null
                if ((Test-Path $frame) -and (Get-Item $frame).Length -gt 0) {
                    $usedPath = $path
                    break
                }
                # Keep trying other paths only while the server answers 404
                # (up, but no such stream). A timeout/refused/401 won't improve
                # with a different path, so stop and report that reason.
                $reason = Get-FailReason $errFile
                if ($reason -notmatch '404|not found') { break }
            }

            if ($usedPath) {
                $entry.streamPath = $usedPath
                $url = "rtsp://$($RtspUser):$($RtspPass)@$ip/$usedPath"
                # Stream metadata for the path that worked (fast header read).
                $probeRaw = & $ffprobe -hide_banner -loglevel error -rtsp_transport tcp `
                    -stimeout 6000000 `
                    -show_entries "stream=codec_type,codec_name,avg_frame_rate,width,height" `
                    -of json -i $url 2>$null
                if ($probeRaw) {
                    $probe = $probeRaw | ConvertFrom-Json
                    $vstream = $probe.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
                    if ($vstream) {
                        $entry.codec     = $vstream.codec_name
                        $entry.frameRate = Convert-FrameRate $vstream.avg_frame_rate
                        if ($vstream.width -and $vstream.height) {
                            $entry.resolution = "$($vstream.width)x$($vstream.height)"
                        }
                    }
                }
                $bytes = [System.IO.File]::ReadAllBytes($frame)
                $entry.image = "data:image/jpeg;base64," + [System.Convert]::ToBase64String($bytes)
                # Look inside the pixels: a black thumbnail otherwise renders as
                # "Active" and hides the fault. The server uses this to tell a
                # genuinely black picture from a normally-lit one.
                $entry.luma = Get-FrameLuma $frame
                $entry.ok = $true
            } else {
                $tried = $candidatePaths -join ', '
                $entry.error = if ($reason) { "$reason (tried paths: $tried)" }
                               else { "No frame captured (tried paths: $tried)." }
            }
        }
        catch {
            $entry.error = $_.Exception.Message
        }
        finally {
            if (Test-Path $frame)   { Remove-Item $frame -Force -ErrorAction SilentlyContinue }
            if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
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
