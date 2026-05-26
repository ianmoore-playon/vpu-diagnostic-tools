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

# Reuse the CoreAudio types compiled by Get-AudioDevices.ps1.
# If not already loaded, compile them now.
if (-not ([System.Management.Automation.PSTypeName]'CoreAudio.MMDeviceEnumerator').Type) {
    # Run Get-AudioDevices first to compile the interop types
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    & "$scriptDir\Get-AudioDevices.ps1" | Out-Null
}

try {
    $enum = New-Object CoreAudio.MMDeviceEnumerator
    $iEnum = [CoreAudio.IMMDeviceEnumerator]$enum

    # Search both capture and render for the device
    $found = $false
    foreach ($flow in @([CoreAudio.EDataFlow]::eCapture, [CoreAudio.EDataFlow]::eRender)) {
        $col = $null
        [void]$iEnum.EnumAudioEndpoints($flow, [uint32]([CoreAudio.EDeviceState]::ACTIVE), [ref]$col)
        $count = [uint32]0
        [void]$col.GetCount([ref]$count)

        for ($i = 0; $i -lt $count; $i++) {
            $dev = $null
            [void]$col.Item($i, [ref]$dev)
            $devId = ''
            [void]$dev.GetId([ref]$devId)

            if ($devId -eq $DeviceId) {
                $volObj = $null
                [void]$dev.Activate(
                    [CoreAudio.Guids]::IID_IAudioEndpointVolume,
                    1, [IntPtr]::Zero, [ref]$volObj)
                $iVol = [CoreAudio.IAudioEndpointVolume]$volObj
                $ctx = [Guid]::Empty
                [void]$iVol.SetMasterVolumeLevelScalar([float]($Volume / 100.0), [ref]$ctx)
                $found = $true
                break
            }
        }
        if ($found) { break }
    }

    if ($found) {
        [ordered]@{
            success  = $true
            deviceId = $DeviceId
            volume   = $Volume
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
