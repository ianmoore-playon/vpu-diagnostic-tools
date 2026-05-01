# =============================================================================
#  Download.ps1  —  Downloads and installs Pulse — Pixellot Unified Live System Evaluator
#  Called by Pulse.bat for both first-install and update scenarios.
#  Reads install path from $env:VPU_INST and deploy token from $env:VPU_DEPLOY_TOKEN.
# =============================================================================

$inst        = $env:VPU_INST
$deployToken = $env:VPU_DEPLOY_TOKEN
$authHeader  = "Bearer $deployToken"

# Use the API zipball endpoint — works with auth and follows redirects to the archive
$url   = 'https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/zipball/main'
$zip   = [IO.Path]::Combine($env:TEMP, 'vpu-diag.zip')
$stage = [IO.Path]::Combine($env:TEMP, 'vpu-diag-stage')

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

# Prefer curl.exe (built into Win 10 1803+): faster, CDN-aware, native progress bar
$curlCmd = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
if ($curlCmd) {
    Write-Host '   Downloading...'
    # -L follows the redirect; auth header is stripped automatically on cross-host redirect to CDN
    & 'curl.exe' -L --progress-bar -H "Authorization: $authHeader" -o $zip $url
    if ($LASTEXITCODE -ne 0) {
        Write-Host '   ERROR: curl download failed.' -ForegroundColor Red
        exit 1
    }
} else {
    # Fallback for older Windows: WebClient async with manual progress polling
    $ProgressPreference = 'SilentlyContinue'
    $total = 0
    try {
        $req = [Net.HttpWebRequest]::Create($url)
        $req.Method = 'HEAD'
        $req.Headers.Add('Authorization', $authHeader)
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $resp.Close()
    } catch {}

    $wc = New-Object Net.WebClient
    $wc.Headers.Add('Authorization', $authHeader)
    $wc.DownloadFileAsync([uri]$url, $zip)
    $t0 = Get-Date

    while ($wc.IsBusy) {
        Start-Sleep -Milliseconds 400
        $got = if (Test-Path $zip) { (Get-Item $zip).Length } else { 0 }
        $el  = ((Get-Date) - $t0).TotalSeconds
        $sp  = if ($el -gt 0.5) { $got / $el } else { 0 }
        if ($total -gt 0) {
            $pct  = [int](($got / $total) * 100)
            $eta  = if ($sp -gt 0) { ('{0}s' -f [int](($total - $got) / $sp)) } else { '...' }
            $mbG  = [math]::Round($got   / 1MB, 1)
            $mbT  = [math]::Round($total / 1MB, 1)
            $line = '   Downloading...  {0,3}%  ({1} MB / {2} MB)  ETA: {3}' -f $pct, $mbG, $mbT, $eta
        } else {
            $mbG  = [math]::Round($got / 1MB, 1)
            $line = '   Downloading...  {0} MB received' -f $mbG
        }
        Write-Host ("`r" + $line.PadRight(65)) -NoNewline
    }
    Write-Host ''
}

if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
    Write-Host '   ERROR: Download incomplete or file missing.' -ForegroundColor Red
    exit 1
}

Expand-Archive $zip $stage -Force

# zipball extracts to a hash-named subfolder — find it dynamically
$src = Get-ChildItem $stage -Directory | Select-Object -First 1
if (-not $src) {
    Write-Host '   ERROR: Could not find extracted folder.' -ForegroundColor Red
    exit 1
}
if (Test-Path $inst) { Remove-Item $inst -Recurse -Force }
Move-Item $src.FullName $inst
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -ErrorAction SilentlyContinue
