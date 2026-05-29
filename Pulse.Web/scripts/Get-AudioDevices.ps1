#Requires -Version 5.1
<#
.SYNOPSIS
    Enumerates audio devices with volume, mute, peak, and port info.
.DESCRIPTION
    Uses CoreAudio COM interop to list all audio endpoints (input + output),
    read volume/mute state, sample peak meter, and identify physical port.
    Falls back to WMI Win32_SoundDevice if CoreAudio fails.

    The script ALWAYS emits JSON to stdout — even on hard failures during
    type loading. Earlier versions could die silently if Add-Type failed
    inside _AudioInterop.ps1, leaving the frontend in a fetch loop. Now
    every error path bubbles into a final `$result` variable that gets
    emitted at the very end.
.NOTES
    Peak sampling uses a single GetPeakValue() call — the CoreAudio meter
    tracks the highest sample since the last query internally, so frequent
    polling from the frontend gives a real-time view without forcing this
    script to block on Start-Sleep.
#>
[CmdletBinding()]
param()

# NOTE: deliberately NOT setting $ErrorActionPreference = 'Stop' at the
# script level — Add-Type / dot-source failures need to be caught,
# not terminating. Individual blocks use -ErrorAction Stop where needed.

$result = $null
$comObjects = [System.Collections.ArrayList]::new()
$diagnostics = [ordered]@{
    interopLoaded   = $false
    coreAudioFailed = $false
    wmiFallbackUsed = $false
    interopError    = $null
    coreAudioError  = $null
    wmiError        = $null
    psVersion       = $PSVersionTable.PSVersion.ToString()
}

function _Release($obj) {
    if ($null -ne $obj) {
        try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) } catch {}
    }
}

function _ClearPropVariant([ref]$pv) {
    try {
        [CoreAudio.Ole32]::PropVariantClear([ref]$pv.Value) | Out-Null
    } catch {}
}

function _EmitJsonAndExit($obj) {
    # Single output point — every code path must funnel through here so
    # the frontend never sees an empty stdout.
    $obj | ConvertTo-Json -Depth 5 -Compress
}

# ── Phase 1: load interop types ───────────────────────────────
$interopPath = Join-Path $PSScriptRoot '_AudioInterop.ps1'
try {
    if (-not (Test-Path -LiteralPath $interopPath)) {
        throw "Interop file not found at $interopPath"
    }
    . $interopPath
    $diagnostics.interopLoaded = $true
} catch {
    $diagnostics.interopError = $_.Exception.Message
}

# ── Phase 2: try CoreAudio enumeration ────────────────────────
if ($diagnostics.interopLoaded) {
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

        $result = [ordered]@{
            devices     = @($devices)
            inputCount  = ($devices | Where-Object { $_.dataFlow -eq 'Input'  -and $_.state -eq 'Active' }).Count
            outputCount = ($devices | Where-Object { $_.dataFlow -eq 'Output' -and $_.state -eq 'Active' }).Count
        }
    } catch {
        $diagnostics.coreAudioFailed = $true
        $diagnostics.coreAudioError  = $_.Exception.Message
    }
}

# ── Phase 3: WMI fallback (used if interop OR CoreAudio failed) ──
if ($null -eq $result) {
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
        $diagnostics.wmiFallbackUsed = $true
        $reason = if (-not $diagnostics.interopLoaded) {
            "CoreAudio interop did not load ($($diagnostics.interopError))"
        } else {
            "CoreAudio enumeration failed ($($diagnostics.coreAudioError))"
        }
        $result = [ordered]@{
            devices     = @($devices)
            inputCount  = 0
            outputCount = 0
            wmiFallback = $true
            warning     = "CoreAudio unavailable — limited device info from WMI only. $reason"
        }
    } catch {
        $diagnostics.wmiError = $_.Exception.Message
    }
}

# ── Phase 4: COM cleanup (best-effort) ────────────────────────
for ($i = $comObjects.Count - 1; $i -ge 0; $i--) {
    _Release $comObjects[$i]
}
try { [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers() } catch {}

# ── Phase 5: emit (guaranteed to run) ─────────────────────────
if ($null -eq $result) {
    # Everything failed — emit a structured error payload with diagnostics
    # so the frontend has something actionable to display.
    $result = [ordered]@{
        error       = $true
        message     = "Audio enumeration failed: " + @(
            $diagnostics.interopError
            $diagnostics.coreAudioError
            $diagnostics.wmiError
        ) -join ' | '
        script      = 'Get-AudioDevices.ps1'
        diagnostics = $diagnostics
    }
} else {
    # Attach diagnostics to the success payload too — helps debug edge cases
    # without changing the success-path schema (frontend ignores unknown keys).
    $result.diagnostics = $diagnostics
}

_EmitJsonAndExit $result
