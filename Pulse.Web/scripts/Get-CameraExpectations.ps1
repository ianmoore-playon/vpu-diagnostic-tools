#Requires -Version 5.1
<#
.SYNOPSIS
    Report the expected main-camera count + inferred system type.
.DESCRIPTION
    Reads /CAMERAS/NUMBER_OF_CAMERAS from the latest Coordinator log -- the
    authoritative count of main cameras the VPU is configured for. This is
    far more reliable than cameras.cfg (which the field has found stale).

    Camera-system mapping (per field):
      4 cameras -> S1   (JAI 4-cam head; discovered via Get-S1Cameras.ps1)
      2 cameras -> S2   (Dynacolor 2-cam head)
      1 camera  -> S2S  (single 1 Gbps Dynacolor -- Diamond sports; new)

    Uses findstr (native, encoding-safe) -- Coordinator logs can be UTF-16,
    which Select-String silently misses. Mirrors Get-SystemIdentity.ps1.
    Adapted from Canopy getConnectedS1Cameras.ps1 / getFirmwareAndTvMode.ps1
    (which both read this same log key).
.OUTPUTS
    { expectedMainCameras: int|null, systemType: "S1"|"S2"|"S2S"|null }
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$logDir = 'C:\Pixellot\Data\Log'

try {
    $count = $null
    if (Test-Path $logDir) {
        $coordLog = Get-ChildItem -Path $logDir -Filter 'coordinator*.log' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $coordLog) {
            $coordLog = Get-ChildItem -Path $logDir -Filter '*Coordinator*.log' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }
        if ($coordLog) {
            $lines = & findstr /C:"/CAMERAS/NUMBER_OF_CAMERAS result:" $coordLog.FullName 2>$null
            if ($lines) {
                $last = if ($lines -is [array]) { $lines[-1] } else { $lines }
                if ($last -match 'NUMBER_OF_CAMERAS result:\s*(\d+)') {
                    $count = [int]$Matches[1]
                }
            }
        }
    }

    $systemType = $null
    switch ($count) {
        4       { $systemType = 'S1' }
        2       { $systemType = 'S2' }
        1       { $systemType = 'S2S' }
        default { $systemType = $null }
    }

    # Is the Pixellot capture engine (vpu.exe) running? If so, it's actively
    # pulling the camera RTSP streams -- Pulse should not grab frames and
    # compete for the camera's limited RTSP sessions during a live event.
    $vpuRunning = $false
    try {
        $vpuRunning = [bool](Get-Process -Name 'vpu' -ErrorAction SilentlyContinue)
    } catch { }

    [ordered]@{
        expectedMainCameras = $count
        systemType          = $systemType
        vpuRunning          = $vpuRunning
    } | ConvertTo-Json -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-CameraExpectations.ps1'
    } | ConvertTo-Json -Compress
}
