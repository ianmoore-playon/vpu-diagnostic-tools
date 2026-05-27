#Requires -Version 5.1
<#
.SYNOPSIS
    Enumerates audio devices with volume, peak, and port info.
.DESCRIPTION
    Uses CoreAudio COM interop to list all audio endpoints (input + output),
    read volume/mute state, sample peak meter, and identify physical port.
    Falls back to WMI Win32_SoundDevice if CoreAudio fails.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ── CoreAudio interop types ──────────────────────────────────
# Compiled once per session via Add-Type; skipped if already loaded.
if (-not ([System.Management.Automation.PSTypeName]'CoreAudio.MMDeviceEnumerator').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CoreAudio {

    // ── COM class ────────────────────────────────────────────
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator {}

    // ── Enums ────────────────────────────────────────────────
    public enum EDataFlow : uint { eRender = 0, eCapture = 1, eAll = 2 }
    public enum EDeviceState : uint {
        ACTIVE = 0x1, DISABLED = 0x2, NOTPRESENT = 0x4, UNPLUGGED = 0x8,
        ALL = 0xF
    }
    public enum EndpointFormFactor : uint {
        RemoteNetworkDevice = 0, Speakers = 1, LineLevel = 2, Headphones = 3,
        Microphone = 4, Headset = 5, Handset = 6, UnknownDigitalPassthrough = 7,
        SPDIF = 8, DigitalAudioDisplayDevice = 9, UnknownFormFactor = 10
    }

    // ── IMMDeviceCollection ──────────────────────────────────
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceCollection {
        int GetCount(out uint count);
        int Item(uint index, out IMMDevice device);
    }

    // ── IMMDevice ────────────────────────────────────────────
    [Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice {
        int Activate([MarshalAs(UnmanagedType.LPStruct)] Guid iid,
                     uint clsCtx, IntPtr pActivationParams,
                     [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(uint access, out IPropertyStore store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out uint state);
    }

    // ── IPropertyStore ───────────────────────────────────────
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IPropertyStore {
        int GetCount(out uint count);
        int GetAt(uint index, out PROPERTYKEY key);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPERTYKEY {
        public Guid fmtid; public uint pid;
        public PROPERTYKEY(Guid g, uint p) { fmtid = g; pid = p; }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROPVARIANT {
        public ushort vt; ushort r1; ushort r2; ushort r3;
        public IntPtr data1; public IntPtr data2;
    }

    // ── IAudioEndpointVolume ─────────────────────────────────
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioEndpointVolume {
        int RegisterControlChangeNotify(IntPtr n);
        int UnregisterControlChangeNotify(IntPtr n);
        int GetChannelCount(out uint count);
        int SetMasterVolumeLevel(float fLevelDB, ref Guid ctx);
        int SetMasterVolumeLevelScalar(float fLevel, ref Guid ctx);
        int GetMasterVolumeLevel(out float pfLevelDB);
        int GetMasterVolumeLevelScalar(out float pfLevel);
    }

    // ── IAudioMeterInformation ───────────────────────────────
    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioMeterInformation {
        int GetPeakValue(out float pfPeak);
    }

    // ── IMMDeviceEnumerator ──────────────────────────────────
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow flow, uint mask,
                               out IMMDeviceCollection col);
        int GetDefaultAudioEndpoint(EDataFlow flow, uint role,
                                    out IMMDevice device);
    }

    // ── Helper ───────────────────────────────────────────────
    public static class Guids {
        public static Guid IID_IAudioEndpointVolume =
            new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        public static Guid IID_IAudioMeterInformation =
            new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
        // Property keys
        public static PROPERTYKEY PKEY_Device_FriendlyName =
            new PROPERTYKEY(new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), 14);
        public static PROPERTYKEY PKEY_AudioEndpoint_FormFactor =
            new PROPERTYKEY(new Guid("1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E"), 0);
    }
}
'@ -ErrorAction Stop
}

try {
    $enum = New-Object CoreAudio.MMDeviceEnumerator
    $iEnum = [CoreAudio.IMMDeviceEnumerator]$enum

    $devices = @()

    foreach ($flow in @([CoreAudio.EDataFlow]::eCapture, [CoreAudio.EDataFlow]::eRender)) {
        $col = $null
        [void]$iEnum.EnumAudioEndpoints($flow, [uint32]([CoreAudio.EDeviceState]::ALL), [ref]$col)
        $count = [uint32]0
        [void]$col.GetCount([ref]$count)

        for ($i = 0; $i -lt $count; $i++) {
            $dev = $null
            [void]$col.Item($i, [ref]$dev)

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

            $nameKey = [CoreAudio.Guids]::PKEY_Device_FriendlyName
            $namePV = New-Object CoreAudio.PROPVARIANT
            $friendlyName = ''
            try {
                [void]$store.GetValue([ref]$nameKey, [ref]$namePV)
                if ($namePV.data1 -ne [IntPtr]::Zero) {
                    $friendlyName = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($namePV.data1)
                }
            } catch {}

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

            $dataFlow = if ($flow -eq [CoreAudio.EDataFlow]::eCapture) { 'Input' } else { 'Output' }

            # Volume + mute (only for active devices)
            $volume = $null
            $muted = $null
            $peakValue = $null

            if ($state -eq 1) {
                # IAudioEndpointVolume
                try {
                    $volObj = $null
                    [void]$dev.Activate(
                        [CoreAudio.Guids]::IID_IAudioEndpointVolume,
                        1, [IntPtr]::Zero, [ref]$volObj)
                    $iVol = [CoreAudio.IAudioEndpointVolume]$volObj
                    $scalar = [float]0
                    [void]$iVol.GetMasterVolumeLevelScalar([ref]$scalar)
                    $volume = [math]::Round($scalar * 100, 1)
                } catch {}

                # IAudioMeterInformation — sample peak over ~500ms
                try {
                    $meterObj = $null
                    [void]$dev.Activate(
                        [CoreAudio.Guids]::IID_IAudioMeterInformation,
                        1, [IntPtr]::Zero, [ref]$meterObj)
                    $iMeter = [CoreAudio.IAudioMeterInformation]$meterObj
                    $maxPeak = [float]0
                    for ($s = 0; $s -lt 5; $s++) {
                        $pk = [float]0
                        [void]$iMeter.GetPeakValue([ref]$pk)
                        if ($pk -gt $maxPeak) { $maxPeak = $pk }
                        Start-Sleep -Milliseconds 100
                    }
                    $peakValue = [math]::Round($maxPeak * 100, 1)
                } catch {}
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
        devices = @($devices)
        inputCount = ($devices | Where-Object { $_.dataFlow -eq 'Input' -and $_.state -eq 'Active' }).Count
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
