#Requires -Version 5.1
<#
.SYNOPSIS
    Enumerates audio devices with volume, mute, peak, and port info.
.DESCRIPTION
    Uses CoreAudio COM interop to list all audio endpoints (input + output),
    read volume/mute state, sample peak meter, and identify physical port.
    Falls back to WMI Win32_SoundDevice if CoreAudio fails.
    Outputs JSON to stdout.
.NOTES
    Peak sampling uses a single GetPeakValue() call — the CoreAudio meter
    tracks the highest sample since the last query internally, so frequent
    polling from the frontend gives a real-time view without forcing this
    script to block on Start-Sleep.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ── CoreAudio interop types (idempotent — only compiled once per session) ──
. (Join-Path $PSScriptRoot '_AudioInterop.ps1')

# Track COM objects for cleanup
$comObjects = [System.Collections.ArrayList]::new()

function _Release($obj) {
    if ($null -ne $obj) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
    }
}

function _ClearPropVariant([ref]$pv) {
    try {
        # PropVariantClear from ole32.dll frees any allocated strings/blobs
        [CoreAudio.Ole32]::PropVariantClear([ref]$pv.Value) | Out-Null
    } catch {}
}

try {
    $enum = New-Object CoreAudio.MMDeviceEnumerator
    [void]$comObjects.Add($enum)
    $iEnum = [CoreAudio.IMMDeviceEnumerator]$enum

    $devices = @()

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

            # State
            $state = [uint32]0
            [void]$dev.GetState([ref]$state)
            $stateLabel = switch ($state) {
                1 { 'Active' } 2 { 'Disabled' } 4 { 'NotPresent' } 8 { 'Unplugged' }
                default { 'Unknown' }
            }

            # Device ID
            $devId = ''
            [void]$dev.GetId([ref]$devId)

            # Property store — friendly name + form factor
            $store = $null
            [void]$dev.OpenPropertyStore(0, [ref]$store)
            [void]$comObjects.Add($store)

            $nameKey = [CoreAudio.Guids]::PKEY_Device_FriendlyName
            $namePV = New-Object CoreAudio.PROPVARIANT
            $friendlyName = ''
            try {
                [void]$store.GetValue([ref]$nameKey, [ref]$namePV)
                if ($namePV.data1 -ne [IntPtr]::Zero) {
                    $friendlyName = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($namePV.data1)
                }
            } catch {}
            finally { _ClearPropVariant ([ref]$namePV) }

            $ffKey = [CoreAudio.Guids]::PKEY_AudioEndpoint_FormFactor
            $ffPV = New-Object CoreAudio.PROPVARIANT
            $formFactor = 'Unknown'
            try {
                [void]$store.GetValue([ref]$ffKey, [ref]$ffPV)
                $ffVal = [int]$ffPV.data1
                $formFactor = switch ($ffVal) {
                    0 { 'RemoteNetwork' } 1 { 'Speakers' } 2 { 'LineLevel' }
                    3 { 'Headphones' } 4 { 'Microphone' } 5 { 'Headset' }
                    6 { 'Handset' } 7 { 'DigitalPassthrough' } 8 { 'SPDIF' }
                    9 { 'DigitalDisplay' } default { 'Unknown' }
                }
            } catch {}
            finally { _ClearPropVariant ([ref]$ffPV) }

            $dataFlow = if ($flow -eq [CoreAudio.EDataFlow]::eCapture) { 'Input' } else { 'Output' }

            # Volume + mute + peak (only for active devices)
            $volume = $null
            $muted = $null
            $peakValue = $null

            if ($state -eq 1) {
                # IAudioEndpointVolume — volume + mute
                $volObj = $null
                try {
                    [void]$dev.Activate(
                        [CoreAudio.Guids]::IID_IAudioEndpointVolume,
                        1, [IntPtr]::Zero, [ref]$volObj)
                    $iVol = [CoreAudio.IAudioEndpointVolume]$volObj

                    $scalar = [float]0
                    [void]$iVol.GetMasterVolumeLevelScalar([ref]$scalar)
                    $volume = [math]::Round($scalar * 100, 1)

                    $muteState = 0
                    [void]$iVol.GetMute([ref]$muteState)
                    $muted = ($muteState -ne 0)
                } catch {}
                finally { _Release $volObj }

                # IAudioMeterInformation — single peak read
                $meterObj = $null
                try {
                    [void]$dev.Activate(
                        [CoreAudio.Guids]::IID_IAudioMeterInformation,
                        1, [IntPtr]::Zero, [ref]$meterObj)
                    $iMeter = [CoreAudio.IAudioMeterInformation]$meterObj
                    $pk = [float]0
                    [void]$iMeter.GetPeakValue([ref]$pk)
                    $peakValue = [math]::Round($pk * 100, 1)
                } catch {}
                finally { _Release $meterObj }
            }

            $devices += [ordered]@{
                id         = $devId
                name       = $friendlyName
                dataFlow   = $dataFlow
                state      = $stateLabel
                formFactor = $formFactor
                volume     = $volume
                muted      = $muted
                peak       = $peakValue
            }
        }
    }

    [ordered]@{
        devices     = @($devices)
        inputCount  = ($devices | Where-Object { $_.dataFlow -eq 'Input' -and $_.state -eq 'Active' }).Count
        outputCount = ($devices | Where-Object { $_.dataFlow -eq 'Output' -and $_.state -eq 'Active' }).Count
    } | ConvertTo-Json -Depth 4 -Compress
}
catch {
    # ── Fallback: WMI only ────────────────────────────────────
    try {
        $wmiDevs = Get-CimInstance Win32_SoundDevice -ErrorAction Stop
        $devices = foreach ($d in $wmiDevs) {
            [ordered]@{
                id         = $d.DeviceID
                name       = $d.Name
                dataFlow   = 'Unknown'
                state      = if ($d.StatusInfo -eq 3) { 'Active' } else { 'Disabled' }
                formFactor = 'Unknown'
                volume     = $null
                muted      = $null
                peak       = $null
            }
        }
        [ordered]@{
            devices     = @($devices)
            inputCount  = 0
            outputCount = 0
            wmiFallback = $true
            warning     = "CoreAudio unavailable — limited device info from WMI only"
        } | ConvertTo-Json -Depth 4 -Compress
    }
    catch {
        [ordered]@{
            error   = $true
            message = $_.Exception.Message
            script  = 'Get-AudioDevices.ps1'
        } | ConvertTo-Json -Compress
    }
}
finally {
    # Release COM objects in reverse order
    for ($i = $comObjects.Count - 1; $i -ge 0; $i--) {
        _Release $comObjects[$i]
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}
