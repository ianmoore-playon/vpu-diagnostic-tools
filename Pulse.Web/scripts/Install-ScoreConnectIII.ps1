#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and runs the ScoreConnect III installer from the Canopy CDN.
.DESCRIPTION
    SC III is the preferred ScoreConnect version. This script downloads the
    official install script from the Canopy public packages CDN and launches
    it with elevated privileges (triggers UAC prompt on the VPU desktop).

    Source: https://canopy-public-packages.nfhsnetwork.com/SC3/Current/installScript3_current.ps1
    Based on Logan's Install-SC3-1.0.bat (PlayOn internal).

    The install script handles: downloading the SC III MSI, stopping any
    existing SC II/III services, running the installer, and starting SC III.
.PARAMETER ScriptUrl
    Override the install script URL (for testing).
#>
[CmdletBinding()]
param(
    [string]$ScriptUrl = 'https://canopy-public-packages.nfhsnetwork.com/SC3/Current/installScript3_current.ps1'
)

$ErrorActionPreference = 'Stop'

$tempDir    = 'C:\scoreconnecttemp'
$scriptFile = Join-Path $tempDir 'installScript3_current.ps1'

$steps = New-Object System.Collections.ArrayList

function _Step([string]$label, [string]$status, [string]$detail = '', [int]$ms = 0) {
    [void]$steps.Add([ordered]@{
        label  = $label
        status = $status
        detail = $detail
        ms     = $ms
    })
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()

try {
    # ── 1. Create temp directory ────────────────────────────────────────
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    _Step 'Create temp directory' 'ok' $tempDir $sw.ElapsedMilliseconds

    # ── 2. Download the install script ──────────────────────────────────
    $dlStart = $sw.ElapsedMilliseconds
    try {
        # Try curl.exe first — temporarily relax ErrorActionPreference so
        # curl's stderr output doesn't trigger a terminating error.
        $curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
        if ($curlPath) {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $curlPath -sSL --fail -o $scriptFile $ScriptUrl --connect-timeout 15 --max-time 60 2>$null
            $curlExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($curlExit -ne 0) { throw "curl failed (exit code $curlExit)" }
        } else {
            Invoke-WebRequest -Uri $ScriptUrl -OutFile $scriptFile -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
        }
    }
    catch {
        _Step 'Download install script' 'fail' "Failed: $($_.Exception.Message)" $sw.ElapsedMilliseconds
        throw "Download failed. Verify *.nfhsnetwork.com is reachable from this VPU. Error: $($_.Exception.Message)"
    }

    if (-not (Test-Path $scriptFile)) {
        _Step 'Download install script' 'fail' 'File not found after download' $sw.ElapsedMilliseconds
        throw "Install script not found at $scriptFile after download"
    }

    $fileSize = (Get-Item $scriptFile).Length
    _Step 'Download install script' 'ok' "$([math]::Round($fileSize/1KB, 1)) KB in $($sw.ElapsedMilliseconds - $dlStart) ms" $sw.ElapsedMilliseconds

    # ── 3. Launch the installer with elevation ──────────────────────────
    # Start-Process -Verb RunAs triggers the UAC prompt on the VPU desktop.
    # We launch it and return immediately — the user accepts UAC and the
    # installer runs in its own window.  We don't wait for completion
    # because the install can take several minutes and we don't want to
    # block the Pulse API.
    $launchStart = $sw.ElapsedMilliseconds
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptFile`"" `
            -Verb RunAs `
            -ErrorAction Stop
        _Step 'Launch installer (UAC)' 'ok' 'Installer launched — accept the UAC prompt on the VPU desktop' $sw.ElapsedMilliseconds
    }
    catch {
        # Common: user declined UAC, or elevation not available
        _Step 'Launch installer (UAC)' 'fail' $_.Exception.Message $sw.ElapsedMilliseconds
        throw "Could not launch installer with elevation: $($_.Exception.Message)"
    }

    # ── Result ──────────────────────────────────────────────────────────
    @{
        ok       = $true
        message  = 'SC III installer launched. Accept the UAC prompt on the VPU desktop to continue installation.'
        steps    = $steps
        totalMs  = [int]$sw.ElapsedMilliseconds
    } | ConvertTo-Json -Depth 5
}
catch {
    @{
        ok      = $false
        error   = $_.Exception.Message
        steps   = $steps
        totalMs = [int]$sw.ElapsedMilliseconds
    } | ConvertTo-Json -Depth 5
}
