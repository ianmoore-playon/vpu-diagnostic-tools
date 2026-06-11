#Requires -Version 5.1
<#
.SYNOPSIS
    Sets the master volume for a specific audio endpoint device.
.DESCRIPTION
    Uses CoreAudio COM interop (IAudioEndpointVolume) to set the
    master volume scalar on the device identified by DeviceId.
    Outputs JSON to stdout.
.PARAMETER DeviceId
    The MMDevice endpoint ID string (e.g. "{0.0.1.00000000}.{guid}").
.PARAMETER Volume
    Desired volume level 0-100.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeviceId,
    [Parameter(Mandatory)][int]$Volume
)

$ErrorActionPreference = 'Stop'

# Clamp to 0-100
$Volume = [Math]::Max(0, [Math]::Min(100, $Volume))

# Load CoreAudio interop types (idempotent - no-op if already loaded)
. (Join-Path $PSScriptRoot '_AudioInterop.ps1')

$comObjects = [System.Collections.ArrayList]::new()

function _Release($obj) {
    if ($null -ne $obj) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
    }
}

try {
    $enum = New-Object CoreAudio.MMDeviceEnumerator
    [void]$comObjects.Add($enum)
    $iEnum = [CoreAudio.IMMDeviceEnumerator]$enum

    # Search both capture and render, ALL states - a device might briefly
    # transition between Active/Unplugged but still be the right target.
    $found = $false
    $appliedVolume = $null
    foreach ($flow in @([CoreAudio.EDataFlow]::eCapture, [CoreAudio.EDataFlow]::eRender)) {
        $col = $null
        [void]$iEnum.EnumAudioEndpoints($flow, [uint32]([CoreAudio.EDeviceState]::ALL), [ref]$col)
        [void]$comObjects.Add($col)
        $count = [uint32]0
        [void]$col.GetCount([ref]$count)

        for ($i = 0; $i -lt $count; $i++) {
            $dev = $null
            [void]$col.Item($i, [ref]$dev)
            [void]$comObjects.Add($dev)

            $devId = ''
            [void]$dev.GetId([ref]$devId)

            if ($devId -eq $DeviceId) {
                $volObj = $null
                try {
                    [void]$dev.Activate(
                        [CoreAudio.Guids]::IID_IAudioEndpointVolume,
                        1, [IntPtr]::Zero, [ref]$volObj)
                    $iVol = [CoreAudio.IAudioEndpointVolume]$volObj
                    $ctx = [Guid]::Empty
                    [void]$iVol.SetMasterVolumeLevelScalar([float]($Volume / 100.0), [ref]$ctx)

                    # Verify by reading back
                    $verify = [float]0
                    [void]$iVol.GetMasterVolumeLevelScalar([ref]$verify)
                    $appliedVolume = [math]::Round($verify * 100, 1)
                    $found = $true
                } finally { _Release $volObj }
                break
            }
        }
        if ($found) { break }
    }

    if ($found) {
        [ordered]@{
            success  = $true
            deviceId = $DeviceId
            volume   = $appliedVolume
        } | ConvertTo-Json -Compress
    } else {
        [ordered]@{
            error   = $true
            message = "Device not found: $DeviceId"
        } | ConvertTo-Json -Compress
    }
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Set-AudioVolume.ps1'
    } | ConvertTo-Json -Compress
}
finally {
    for ($i = $comObjects.Count - 1; $i -ge 0; $i--) {
        _Release $comObjects[$i]
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
