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

    [ordered]@{
        registryConfig  = $registryConfig
        cameras         = @($cameras)
        cameraCfgExists = (Test-Path $cameraCfgPath)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-PixellotConfig.ps1'
    } | ConvertTo-Json -Compress
}
