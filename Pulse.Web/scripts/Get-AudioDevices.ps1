#Requires -Version 5.1
<#
.SYNOPSIS
    Enumerates audio devices with volume, mute, peak, port, and default info.
.DESCRIPTION
    Calls the compiled CoreAudio.Api helper (see _AudioInterop.ps1) to list
    all audio endpoints (input + output), read volume/mute state, sample the
    peak meter, identify the physical port, and flag the Windows default
    recording/playback devices. Falls back to WMI Win32_SoundDevice if the
    CoreAudio path fails.

    All COM work lives in the compiled helper - this script must not touch
    COM objects directly. PS 5.1 on the VPU image (Win10 LTSC 1809) cannot
    cast ComImport classes to COM interfaces at script level; doing so here
    silently forced the WMI fallback on every real VPU.

    The script ALWAYS emits JSON to stdout - even on hard failures during
    type loading. Earlier versions could die silently if Add-Type failed
    inside _AudioInterop.ps1, leaving the frontend in a fetch loop. Every
    error path bubbles into a final `$result` variable emitted at the end.
.NOTES
    Peak sampling uses a single GetPeakValue() call - the CoreAudio meter
    tracks the highest sample since the last query internally, so frequent
    polling from the frontend gives a real-time view without forcing this
    script to block on Start-Sleep.

    Keep this file pure ASCII (see the note in _AudioInterop.ps1).
#>
[CmdletBinding()]
param()

# NOTE: deliberately NOT setting $ErrorActionPreference = 'Stop' at the
# script level - Add-Type / dot-source failures need to be caught,
# not terminating.

$result = $null
$diagnostics = [ordered]@{
    interopLoaded   = $false
    coreAudioFailed = $false
    wmiFallbackUsed = $false
    interopError    = $null
    coreAudioError  = $null
    wmiError        = $null
    psVersion       = $PSVersionTable.PSVersion.ToString()
}

function _EmitJsonAndExit($obj) {
    # Single output point - every code path must funnel through here so
    # the frontend never sees an empty stdout.
    $obj | ConvertTo-Json -Depth 5 -Compress
}

# -- Phase 1: load + compile the interop helper ----------------
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

# -- Phase 2: CoreAudio enumeration via the compiled helper ----
if ($diagnostics.interopLoaded) {
    try {
        $devices = @()
        foreach ($ep in [CoreAudio.Api]::Enumerate()) {
            $devices += [ordered]@{
                id                    = $ep.Id
                name                  = $ep.Name
                dataFlow              = $ep.DataFlow
                state                 = $ep.State
                formFactor            = $ep.FormFactor
                volume                = if ($ep.HasVolume) { [math]::Round($ep.Volume, 1) } else { $null }
                muted                 = if ($ep.HasVolume) { $ep.Muted } else { $null }
                peak                  = if ($ep.HasPeak) { [math]::Round($ep.Peak, 1) } else { $null }
                isDefaultCapture      = $ep.IsDefaultCapture
                isDefaultCaptureComms = $ep.IsDefaultCaptureComms
                isDefaultRender       = $ep.IsDefaultRender
            }
        }

        $result = [ordered]@{
            devices     = @($devices)
            inputCount  = @($devices | Where-Object { $_.dataFlow -eq 'Input'  -and $_.state -eq 'Active' }).Count
            outputCount = @($devices | Where-Object { $_.dataFlow -eq 'Output' -and $_.state -eq 'Active' }).Count
        }
    } catch {
        $diagnostics.coreAudioFailed = $true
        $diagnostics.coreAudioError  = $_.Exception.Message
    }
}

# -- Phase 3: WMI fallback (used if interop OR CoreAudio failed) --
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
            warning     = "CoreAudio unavailable - limited device info from WMI only. $reason"
        }
    } catch {
        $diagnostics.wmiError = $_.Exception.Message
    }
}

# -- Phase 4: emit (guaranteed to run) -------------------------
if ($null -eq $result) {
    # Everything failed - emit a structured error payload with diagnostics
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
    # Attach diagnostics to the success payload too - helps debug edge cases
    # without changing the success-path schema (frontend ignores unknown keys).
    $result.diagnostics = $diagnostics
}

_EmitJsonAndExit $result
