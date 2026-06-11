#Requires -Version 5.1
<#
.SYNOPSIS
    Shared CoreAudio COM interop type definitions.
.DESCRIPTION
    Dot-sourced by Get-AudioDevices.ps1 and Set-AudioVolume.ps1 to compile
    the IMMDeviceEnumerator / IAudioEndpointVolume / IAudioMeterInformation
    COM interfaces. The IAudioEndpointVolume interface includes all methods
    through GetMute (vtable index 13) so callers can read/write mute state.

    Idempotent - the type-presence check at the top skips Add-Type if the
    interop types are already loaded in the current PowerShell session.
#>

if (-not ([System.Management.Automation.PSTypeName]'CoreAudio.MMDeviceEnumerator').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace CoreAudio {

    // -- COM class --------------------------------------------
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator {}

    // -- Enums ------------------------------------------------
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

    // -- IMMDeviceCollection ----------------------------------
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceCollection {
        int GetCount(out uint count);
        int Item(uint index, out IMMDevice device);
    }

    // -- IMMDevice --------------------------------------------
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

    // -- IPropertyStore ---------------------------------------
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

    // -- IAudioEndpointVolume ---------------------------------
    // Full vtable through GetMute (index 13) - required so SetMute/GetMute
    // resolve to the correct COM slots. Methods after GetMute are omitted
    // since we don't call them, and the vtable beyond what's defined is
    // untouched.
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
        int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid ctx);
        int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid ctx);
        int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
        int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
        int SetMute(int bMute, ref Guid ctx);
        int GetMute(out int pbMute);
    }

    // -- IAudioMeterInformation -------------------------------
    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioMeterInformation {
        int GetPeakValue(out float pfPeak);
    }

    // -- IMMDeviceEnumerator ----------------------------------
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow flow, uint mask,
                               out IMMDeviceCollection col);
        int GetDefaultAudioEndpoint(EDataFlow flow, uint role,
                                    out IMMDevice device);
    }

    // -- Ole32 - PropVariantClear -----------------------------
    public static class Ole32 {
        [DllImport("ole32.dll")]
        public static extern int PropVariantClear(ref PROPVARIANT pvar);
    }

    // -- Constants --------------------------------------------
    public static class Guids {
        public static Guid IID_IAudioEndpointVolume =
            new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        public static Guid IID_IAudioMeterInformation =
            new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
        public static PROPERTYKEY PKEY_Device_FriendlyName =
            new PROPERTYKEY(new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), 14);
        public static PROPERTYKEY PKEY_AudioEndpoint_FormFactor =
            new PROPERTYKEY(new Guid("1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E"), 0);
    }
}
'@ -ErrorAction Stop
}
