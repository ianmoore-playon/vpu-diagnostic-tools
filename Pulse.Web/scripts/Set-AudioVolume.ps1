#Requires -Version 5.1
<#
.SYNOPSIS
    Sets the master volume for a specific audio endpoint device.
.DESCRIPTION
    Calls the compiled CoreAudio.Api helper (see _AudioInterop.ps1) to set
    the master volume scalar on the device identified by DeviceId, looked
    up directly via IMMDeviceEnumerator::GetDevice. Outputs JSON to stdout.

    All COM work lives in the compiled helper - this script must not touch
    COM objects directly (see the cast note in _AudioInterop.ps1).

    Keep this file pure ASCII (see the note in _AudioInterop.ps1).
.PARAMETER DeviceId
    The MMDevice endpoint ID string (e.g. "{0.0.1.00000000}.{guid}").
.PARAMETER Volume
    Desired volume level 0-100 (clamped by the helper).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeviceId,
    [Parameter(Mandatory)][int]$Volume
)

$ErrorActionPreference = 'Stop'

try {
    # Load CoreAudio interop helper (idempotent - no-op if already loaded)
    . (Join-Path $PSScriptRoot '_AudioInterop.ps1')

    $r = [CoreAudio.Api]::SetVolume($DeviceId, $Volume)
    if ($r.Success) {
        [ordered]@{
            success  = $true
            deviceId = $DeviceId
            volume   = [math]::Round($r.Applied, 1)
        } | ConvertTo-Json -Compress
    } else {
        [ordered]@{
            error   = $true
            message = $r.Error
            script  = 'Set-AudioVolume.ps1'
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
