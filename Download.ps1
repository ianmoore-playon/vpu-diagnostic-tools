# =============================================================================
#  Download.ps1  —  Downloads and installs the VPU Diagnostic Tool Suite
#  Called by the launcher BAT for both first-install and update scenarios.
#  Reads install path from $env:VPU_INST.
# =============================================================================

$inst  = $env:VPU_INST
$ProgressPreference = 'SilentlyContinue'
$url   = 'https://github.com/ianmoore-playon/vpu-diagnostic-tools/archive/refs/heads/main.zip'
$zip   = [IO.Path]::Combine($env:TEMP, 'vpu-diag.zip')
$stage = [IO.Path]::Combine($env:TEMP, 'vpu-diag-stage')

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

# HEAD request to get total size for progress calculation
$total = 0
try {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Method = 'HEAD'
    $resp = $req.GetResponse()
    $total = $resp.ContentLength
    $resp.Close()
} catch {}

# Async download so we can poll and show progress
$wc = New-Object Net.WebClient
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

if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 100000) {
    Write-Host '   ERROR: Download incomplete or file missing.' -ForegroundColor Red
    exit 1
}

Expand-Archive $zip $stage -Force
$src = Join-Path $stage 'vpu-diagnostic-tools-main'
if (Test-Path $inst) { Remove-Item $inst -Recurse -Force }
Move-Item $src $inst
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -ErrorAction SilentlyContinue
