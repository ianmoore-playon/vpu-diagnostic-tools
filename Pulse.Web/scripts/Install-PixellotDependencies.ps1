#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads and runs Pixellot-Installer-Dependencies-5.0.0.exe.
.DESCRIPTION
    Per Pixellot Troubleshooting Tips PDF #2, CUDNN_STATUS_EXECUTION_FAILED
    and TensorFlow errors in the VPU logs mean the underlying CUDA / cuDNN /
    TensorFlow dependencies are broken. The documented remedy is to
    re-download and run the Pixellot dependency installer.

    Source URL:  https://software.pixellot.tv/apps/Pixellot-Installer-Dependencies-5.0.0.exe
    Target dir:  C:\pixellot\downloadedversion\

    Falls back from curl.exe → BITS → Invoke-WebRequest since some VPUs
    lack curl (per CLAUDE.md).

    Runs the installer with /S /silent /qn flags (NSIS + MSI variants).
.PARAMETER InstallerUrl
    Override the source URL (mostly for testing).
.PARAMETER SkipDownload
    Skip the download phase — use this if the installer is already present.
.PARAMETER SkipInstall
    Download only — useful for testing without committing to the install.
#>
[CmdletBinding()]
param(
    [string]$InstallerUrl = 'https://software.pixellot.tv/apps/Pixellot-Installer-Dependencies-5.0.0.exe',
    [switch]$SkipDownload,
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

$targetDir  = 'C:\pixellot\downloadedversion'
$targetFile = Join-Path $targetDir 'Pixellot-Installer-Dependencies-5.0.0.exe'

$steps = New-Object System.Collections.ArrayList

function _Step([string]$label, [string]$status, [string]$detail = '', [int]$ms = 0) {
    [void]$steps.Add([ordered]@{
        label    = $label
        status   = $status
        detail   = $detail
        durationMs = $ms
        ts       = (Get-Date).ToString('o')
    })
}

try {
    # Ensure target dir exists
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    # ── Download phase ───────────────────────────────────────
    if (-not $SkipDownload) {
        $t0 = Get-Date
        $downloaded = $false
        $downloadVia = $null

        # Try curl first
        $curlPath = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
        if ($curlPath) {
            try {
                & $curlPath -L -f -s -o $targetFile $InstallerUrl 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $targetFile)) {
                    $downloaded = $true
                    $downloadVia = 'curl.exe'
                }
            } catch {}
        }

        # Fall back to BITS
        if (-not $downloaded) {
            try {
                Start-BitsTransfer -Source $InstallerUrl -Destination $targetFile -ErrorAction Stop
                if (Test-Path -LiteralPath $targetFile) {
                    $downloaded = $true
                    $downloadVia = 'BITS'
                }
            } catch {}
        }

        # Last resort: Invoke-WebRequest
        if (-not $downloaded) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $InstallerUrl -OutFile $targetFile -UseBasicParsing -ErrorAction Stop
                if (Test-Path -LiteralPath $targetFile) {
                    $downloaded = $true
                    $downloadVia = 'Invoke-WebRequest'
                }
            } catch {
                throw "All download methods failed. Last error: $($_.Exception.Message)"
            }
        }

        $sizeMb = if (Test-Path -LiteralPath $targetFile) { [math]::Round((Get-Item -LiteralPath $targetFile).Length / 1MB, 1) } else { 0 }
        $elapsed = [int]((Get-Date) - $t0).TotalMilliseconds
        _Step -label 'Download installer' -status 'ok' `
              -detail "Downloaded $sizeMb MB via $downloadVia to $targetFile" -ms $elapsed
    }
    else {
        _Step -label 'Download installer' -status 'skipped' -detail 'SkipDownload set'
    }

    # ── Install phase ────────────────────────────────────────
    if (-not $SkipInstall) {
        if (-not (Test-Path -LiteralPath $targetFile)) {
            throw "Installer not found at $targetFile after download phase"
        }

        $t0 = Get-Date
        # Try multiple silent-install flag combinations. NSIS uses /S,
        # InstallShield uses /quiet, MSI uses /qn. We pass them all and
        # the installer ignores the ones it doesn't understand.
        $proc = Start-Process -FilePath $targetFile `
            -ArgumentList '/S', '/silent', '/quiet', '/qn' `
            -PassThru -Wait -NoNewWindow

        $elapsed = [int]((Get-Date) - $t0).TotalMilliseconds
        $okExit = ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010)  # 3010 = success, reboot required

        $stepStatus = if ($okExit) { 'ok' } else { 'fail' }
        _Step -label 'Run installer' -status $stepStatus `
              -detail "Exit code $($proc.ExitCode) after $([math]::Round($elapsed/1000,0))s" `
              -ms $elapsed
    }
    else {
        _Step -label 'Run installer' -status 'skipped' -detail 'SkipInstall set'
    }

    [ordered]@{
        success     = $true
        targetDir   = $targetDir
        targetFile  = $targetFile
        installerUrl = $InstallerUrl
        steps       = @($steps)
        message     = 'Pixellot dependencies installer completed. Reboot recommended.'
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    _Step -label 'Error' -status 'fail' -detail $_.Exception.Message
    [ordered]@{
        success     = $false
        targetDir   = $targetDir
        targetFile  = $targetFile
        installerUrl = $InstallerUrl
        steps       = @($steps)
        message     = $_.Exception.Message
        script      = 'Install-PixellotDependencies.ps1'
    } | ConvertTo-Json -Compress
}
