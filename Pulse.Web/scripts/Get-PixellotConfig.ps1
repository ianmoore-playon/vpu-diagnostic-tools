#Requires -Version 5.1
<#
.SYNOPSIS
    Reads Pixellot configuration from registry and config files.
.DESCRIPTION
    Gathers all Pixellot registry values and parses the cameras.cfg
    file for camera IP and MAC mappings. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Registry values
    $registryConfig = [ordered]@{}
    $regPath = 'HKLM:\SOFTWARE\Pixellot'

    try {
        if (Test-Path $regPath) {
            $regItem = Get-Item -Path $regPath -ErrorAction Stop
            foreach ($valueName in $regItem.GetValueNames()) {
                if ($valueName -ne '') {
                    $registryConfig[$valueName] = $regItem.GetValue($valueName)
                }
            }
        }
    }
    catch { }

    # Parse cameras.cfg (INI-style)
    $cameras = @()
    $cameraCfgPath = 'D:\Pixellot\PixellotAgent\cameras.cfg'

    if (Test-Path $cameraCfgPath) {
        try {
            $content = Get-Content -Path $cameraCfgPath -ErrorAction Stop
            $currentCamera = $null

            foreach ($line in $content) {
                $trimmed = $line.Trim()

                # Skip empty lines and comments
                if (-not $trimmed -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) {
                    continue
                }

                # Section header (e.g., [camera1])
                if ($trimmed -match '^\[(.+)\]$') {
                    if ($currentCamera) {
                        $cameras += $currentCamera
                    }
                    $currentCamera = [ordered]@{
                        section = $Matches[1]
                        ip      = $null
                        mac     = $null
                        role    = $null
                    }
                    continue
                }

                # Key=Value pairs
                if ($trimmed -match '^(\w+)\s*=\s*(.*)$') {
                    $key   = $Matches[1].ToLower()
                    $value = $Matches[2].Trim()

                    if ($currentCamera) {
                        switch ($key) {
                            'ip'      { $currentCamera.ip = $value }
                            'ipaddress' { $currentCamera.ip = $value }
                            'address' { $currentCamera.ip = $value }
                            'mac'     { $currentCamera.mac = $value }
                            'macaddress' { $currentCamera.mac = $value }
                            'role'    { $currentCamera.role = $value }
                            'type'    { if (-not $currentCamera.role) { $currentCamera.role = $value } }
                        }
                    }
                }
            }

            # Add last camera
            if ($currentCamera) {
                $cameras += $currentCamera
            }
        }
        catch { }
    }

    # Calibration status — recorded by FILE/FOLDER PRESENCE, not a registry
    # flag (confirmed on a VPU 2026-06-15):
    #   * Main camera multisport view:
    #       C:\Pixellot\Data\Configuration\multisportcalibration\<sport>\
    #       one subfolder per sport == calibrated for that sport; folder
    #       mtime ≈ when. primary.txt names the default sport.
    #   * OCR / scoreboard:
    #       C:\Pixellot\Data\Configuration\Graphics\pipdesign\
    #       calibrated when enhanced_pip.txt AND innerobjects.txt both exist.
    $calibration = [ordered]@{
        multisport = [ordered]@{ calibrated = $false; sports = @(); primary = $null }
        ocr        = [ordered]@{ calibrated = $false; lastCalibrated = $null; hasEnhancedPip = $false; hasInnerObjects = $false }
    }

    $mscPath = 'C:\Pixellot\Data\Configuration\multisportcalibration'
    if (Test-Path $mscPath) {
        try {
            $sports = @()
            foreach ($f in (Get-ChildItem -LiteralPath $mscPath -Directory -ErrorAction SilentlyContinue)) {
                $sports += [ordered]@{
                    name           = $f.Name
                    lastCalibrated = $f.LastWriteTime.ToString('o')
                }
            }
            $calibration.multisport.sports     = @($sports)
            $calibration.multisport.calibrated = ($sports.Count -gt 0)

            $primaryPath = Join-Path $mscPath 'primary.txt'
            if (Test-Path $primaryPath) {
                $primaryRaw = Get-Content -LiteralPath $primaryPath -Raw -ErrorAction SilentlyContinue
                if ($primaryRaw) { $calibration.multisport.primary = $primaryRaw.Trim() }
            }
        }
        catch { }
    }

    $pipPath = 'C:\Pixellot\Data\Configuration\Graphics\pipdesign'
    if (Test-Path $pipPath) {
        try {
            $enhanced    = Join-Path $pipPath 'enhanced_pip.txt'
            $inner       = Join-Path $pipPath 'innerobjects.txt'
            $hasEnhanced = Test-Path $enhanced
            $hasInner    = Test-Path $inner
            $calibration.ocr.hasEnhancedPip  = $hasEnhanced
            $calibration.ocr.hasInnerObjects = $hasInner
            $calibration.ocr.calibrated      = ($hasEnhanced -and $hasInner)

            $times = @()
            if ($hasInner)    { $times += (Get-Item -LiteralPath $inner).LastWriteTime }
            if ($hasEnhanced) { $times += (Get-Item -LiteralPath $enhanced).LastWriteTime }
            if ($times.Count -gt 0) {
                $calibration.ocr.lastCalibrated = ($times | Sort-Object -Descending | Select-Object -First 1).ToString('o')
            }
        }
        catch { }
    }

    [ordered]@{
        registryConfig  = $registryConfig
        cameras         = @($cameras)
        cameraCfgExists = (Test-Path $cameraCfgPath)
        calibration     = $calibration
    } | ConvertTo-Json -Depth 6 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-PixellotConfig.ps1'
    } | ConvertTo-Json -Compress
}
