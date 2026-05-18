# =============================================================================
#  Download.ps1  —  Downloads and installs Pulse — Pixellot Unified Live System Evaluator
#  Called by Pulse.bat for both first-install and update scenarios.
#  Reads install path from $env:VPU_INST. The repo is public — no auth needed.
# =============================================================================

$inst        = $env:VPU_INST

# Use the archive endpoint — public, anonymous, follows redirects to the CDN.
$url   = 'https://github.com/ianmoore-playon/vpu-diagnostic-tools/archive/refs/heads/main.zip'
$zip   = [IO.Path]::Combine($env:TEMP, 'vpu-diag.zip')
$stage = [IO.Path]::Combine($env:TEMP, 'vpu-diag-stage')

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }

# Prefer curl.exe (built into Win 10 1803+): faster, CDN-aware, native progress bar
$curlCmd = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
if ($curlCmd) {
    Write-Host '   Downloading...'
    # -L follows the redirect to the GitHub archive CDN.
    & 'curl.exe' -L --progress-bar -o $zip $url
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
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $resp.Close()
    } catch {}

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

# R18 fix: atomic install swap. Previously the install dir was wiped *before*
# the new content moved in, so any failure mid-move bricked the install.
# New flow:
#   1. Validate the staged folder contains the entry points we expect.
#   2. Rename the existing install to <inst>.bak.<pid>.
#   3. Move the staged folder into place.
#   4. On success, delete the .bak. On failure, restore it.
$requiredEntryPoints = @('Pulse.ps1','Build.ps1','Modules')
$missing = @()
foreach ($e in $requiredEntryPoints) {
    if (-not (Test-Path (Join-Path $src.FullName $e))) { $missing += $e }
}
if ($missing.Count -gt 0) {
    Write-Host ('   ERROR: Staged folder is missing expected entries: {0}. Aborting before any change to {1}.' -f ($missing -join ', '), $inst) -ForegroundColor Red
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -ErrorAction SilentlyContinue
    exit 1
}

$backup = "$inst.bak.$PID"
if (Test-Path $inst) {
    try {
        Rename-Item -Path $inst -NewName (Split-Path $backup -Leaf) -ErrorAction Stop
    } catch {
        Write-Host "   ERROR: Could not rename current install to backup: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   This usually means Pulse is still running. Close it and re-run." -ForegroundColor Yellow
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zip -ErrorAction SilentlyContinue
        exit 1
    }
}
try {
    Move-Item $src.FullName $inst -ErrorAction Stop
} catch {
    # Move failed - restore the backup so the box isn't left without an install.
    Write-Host "   ERROR: Move into $inst failed: $($_.Exception.Message)" -ForegroundColor Red
    if (Test-Path $backup) {
        try {
            Rename-Item -Path $backup -NewName (Split-Path $inst -Leaf) -ErrorAction Stop
            Write-Host "   Previous install restored from backup." -ForegroundColor Yellow
        } catch {
            Write-Host "   ERROR: Backup restore failed - manual recovery may be required at $backup" -ForegroundColor Red
        }
    }
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zip -ErrorAction SilentlyContinue
    exit 1
}
# Success — clean up backup + staging.
if (Test-Path $backup) { Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue }
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zip -ErrorAction SilentlyContinue
