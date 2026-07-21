#Requires -Version 5.1
<#
.SYNOPSIS
    Shared CoreAudio COM interop - compiled C# helper.
.DESCRIPTION
    Dot-sourced by Get-AudioDevices.ps1 and Set-AudioVolume.ps1. ALL COM
    work (enumeration, property reads, volume/mute, peak meters, default
    endpoints) happens inside the compiled CoreAudio.Api class below;
    PowerShell only calls its static entry points.

    Why no COM calls at script level: on the VPU fleet image (Win10 LTSC
    1809, PS 5.1.17763) PowerShell's type converter cannot cast a ComImport
    class to its COM interface ("Cannot convert ... MMDeviceEnumerator to
    ... IMMDeviceEnumerator"), which silently forced the WMI fallback on
    every real VPU. The same QueryInterface done from compiled C# works
    fine on that image, so the interface cast must live in C#.

    Idempotent - the type-presence check skips Add-Type when the types are
    already loaded in this PowerShell session.

    Compile cache: every /api/audio poll is a FRESH powershell.exe, and
    Add-Type -TypeDefinition shells out to csc.exe (1-3s per process) -
    that made the live meters crawl. The C# is compiled once to a DLL in
    TEMP, keyed by a hash of the source (any edit gets a fresh file name),
    and later processes just load the DLL. Any failure on the cache path
    falls back to the slow in-memory compile, so behavior never changes.

    IMPORTANT: keep this file pure ASCII (plain '-' dashes, no box-drawing
    or smart punctuation). Windows PowerShell 5.1 reads unsigned .ps1 files
    as ANSI; non-ASCII bytes get misdecoded and can break parsing (a54f85f).
    The C# below must also stay C# 5 compatible - PS 5.1 compiles Add-Type
    with the legacy CodeDom compiler (no string interpolation, no ?. etc).
#>

if (-not ([System.Management.Automation.PSTypeName]'CoreAudio.Api').Type) {
    $coreAudioSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace CoreAudio {

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorCom {}

    internal enum EDataFlow : uint { eRender = 0, eCapture = 1, eAll = 2 }

    // Vtable order matters on every interface below - methods must be
    // declared in IDL order even when unused, so later slots resolve right.
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(EDataFlow flow, uint mask, out IMMDeviceCollection col);
        int GetDefaultAudioEndpoint(EDataFlow flow, uint role, out IMMDevice device);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
    }

    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection {
        int GetCount(out uint count);
        int Item(uint index, out IMMDevice device);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice {
        int Activate([MarshalAs(UnmanagedType.LPStruct)] Guid iid, uint clsCtx,
                     IntPtr pActivationParams,
                     [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
        int OpenPropertyStore(uint access, out IPropertyStore store);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetState(out uint state);
    }

    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore {
        int GetCount(out uint count);
        int GetAt(uint index, out PROPERTYKEY key);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PROPERTYKEY {
        public Guid fmtid; public uint pid;
        public PROPERTYKEY(Guid g, uint p) { fmtid = g; pid = p; }
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PROPVARIANT {
        public ushort vt; public ushort r1; public ushort r2; public ushort r3;
        public IntPtr data1; public IntPtr data2;
    }

    // Full vtable through GetMute (index 13) so SetMute/GetMute hit the
    // correct COM slots.
    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume {
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

    [Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioMeterInformation {
        int GetPeakValue(out float pfPeak);
    }

    internal static class Ole32 {
        [DllImport("ole32.dll")]
        public static extern int PropVariantClear(ref PROPVARIANT pvar);
    }

    // Plain data objects handed back to PowerShell - no COM types cross
    // the boundary.
    public class EndpointInfo {
        public string Id;
        public string Name;
        public string DataFlow;    // "Input" | "Output"
        public string State;       // Active | Disabled | NotPresent | Unplugged | Unknown
        public string FormFactor;
        public bool HasVolume; public float Volume; public bool Muted;
        public bool HasPeak;   public float Peak;
        public bool IsDefaultCapture;       // Windows default recording device (console role)
        public bool IsDefaultCaptureComms;  // default communications recording device
        public bool IsDefaultRender;        // Windows default playback device (console role)
    }

    public class VolumeResult {
        public bool Success; public float Applied; public string Error;
    }

    public static class Api {
        static readonly Guid IID_Volume = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        static readonly Guid IID_Meter  = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
        static readonly PROPERTYKEY PKEY_Name =
            new PROPERTYKEY(new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), 14);
        static readonly PROPERTYKEY PKEY_FormFactor =
            new PROPERTYKEY(new Guid("1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E"), 0);

        static IMMDeviceEnumerator NewEnumerator() {
            // The QueryInterface PS 5.1 can't do at script level.
            return (IMMDeviceEnumerator)(object)new MMDeviceEnumeratorCom();
        }

        public static List<EndpointInfo> Enumerate() {
            var list = new List<EndpointInfo>();
            IMMDeviceEnumerator en = NewEnumerator();
            try {
                string defCapture  = DefaultId(en, EDataFlow.eCapture, 0);
                string defCapComms = DefaultId(en, EDataFlow.eCapture, 2);
                string defRender   = DefaultId(en, EDataFlow.eRender, 0);

                EDataFlow[] flows = new EDataFlow[] { EDataFlow.eCapture, EDataFlow.eRender };
                foreach (EDataFlow flow in flows) {
                    IMMDeviceCollection col;
                    Marshal.ThrowExceptionForHR(en.EnumAudioEndpoints(flow, 0xF, out col));
                    try {
                        uint count; col.GetCount(out count);
                        for (uint i = 0; i < count; i++) {
                            IMMDevice dev;
                            if (col.Item(i, out dev) != 0 || dev == null) continue;
                            try {
                                list.Add(ReadEndpoint(dev, flow, defCapture, defCapComms, defRender));
                            } finally { Marshal.ReleaseComObject(dev); }
                        }
                    } finally { Marshal.ReleaseComObject(col); }
                }
            } finally { Marshal.ReleaseComObject(en); }
            return list;
        }

        public static VolumeResult SetVolume(string deviceId, int volumePercent) {
            var r = new VolumeResult();
            if (volumePercent < 0) volumePercent = 0;
            if (volumePercent > 100) volumePercent = 100;
            IMMDeviceEnumerator en = null; IMMDevice dev = null; object volObj = null;
            try {
                en = NewEnumerator();
                int hr = en.GetDevice(deviceId, out dev);
                if (hr != 0 || dev == null) {
                    r.Error = "Device not found: " + deviceId;
                    return r;
                }
                hr = dev.Activate(IID_Volume, 1, IntPtr.Zero, out volObj);
                if (hr != 0 || volObj == null) {
                    r.Error = "Volume control unavailable for this device (HRESULT 0x" + hr.ToString("X8") + ")";
                    return r;
                }
                IAudioEndpointVolume vol = (IAudioEndpointVolume)volObj;
                Guid ctx = Guid.Empty;
                hr = vol.SetMasterVolumeLevelScalar(volumePercent / 100f, ref ctx);
                if (hr != 0) {
                    r.Error = "Set volume failed (HRESULT 0x" + hr.ToString("X8") + ")";
                    return r;
                }
                float applied; vol.GetMasterVolumeLevelScalar(out applied);
                r.Success = true; r.Applied = applied * 100f;
                return r;
            } catch (Exception ex) {
                r.Error = ex.Message;
                return r;
            } finally {
                if (volObj != null) Marshal.ReleaseComObject(volObj);
                if (dev != null) Marshal.ReleaseComObject(dev);
                if (en != null) Marshal.ReleaseComObject(en);
            }
        }

        static EndpointInfo ReadEndpoint(IMMDevice dev, EDataFlow flow,
                                         string defCapture, string defCapComms, string defRender) {
            var info = new EndpointInfo();
            string id; dev.GetId(out id);
            info.Id = id;
            uint state; dev.GetState(out state);
            info.State = StateLabel(state);
            info.DataFlow = flow == EDataFlow.eCapture ? "Input" : "Output";

            IPropertyStore store;
            if (dev.OpenPropertyStore(0, out store) == 0 && store != null) {
                try {
                    info.Name = ReadStringProp(store, PKEY_Name);
                    info.FormFactor = FormFactorLabel(ReadUIntProp(store, PKEY_FormFactor, 10));
                } finally { Marshal.ReleaseComObject(store); }
            } else {
                info.Name = ""; info.FormFactor = "Unknown";
            }

            if (state == 1) { // volume + meter only activate on Active endpoints
                object volObj = null;
                try {
                    if (dev.Activate(IID_Volume, 1, IntPtr.Zero, out volObj) == 0 && volObj != null) {
                        IAudioEndpointVolume vol = (IAudioEndpointVolume)volObj;
                        float scalar;
                        if (vol.GetMasterVolumeLevelScalar(out scalar) == 0) {
                            info.HasVolume = true;
                            info.Volume = scalar * 100f;
                            int mute;
                            if (vol.GetMute(out mute) == 0) info.Muted = mute != 0;
                        }
                    }
                } catch {} finally { if (volObj != null) Marshal.ReleaseComObject(volObj); }

                object meterObj = null;
                try {
                    if (dev.Activate(IID_Meter, 1, IntPtr.Zero, out meterObj) == 0 && meterObj != null) {
                        IAudioMeterInformation meter = (IAudioMeterInformation)meterObj;
                        float peak;
                        if (meter.GetPeakValue(out peak) == 0) {
                            info.HasPeak = true; info.Peak = peak * 100f;
                        }
                    }
                } catch {} finally { if (meterObj != null) Marshal.ReleaseComObject(meterObj); }
            }

            info.IsDefaultCapture      = defCapture  != null && id == defCapture;
            info.IsDefaultCaptureComms = defCapComms != null && id == defCapComms;
            info.IsDefaultRender       = defRender   != null && id == defRender;
            return info;
        }

        static string DefaultId(IMMDeviceEnumerator en, EDataFlow flow, uint role) {
            IMMDevice dev = null;
            try {
                if (en.GetDefaultAudioEndpoint(flow, role, out dev) != 0 || dev == null) return null;
                string id; dev.GetId(out id);
                return id;
            } catch { return null; }
            finally { if (dev != null) Marshal.ReleaseComObject(dev); }
        }

        static string ReadStringProp(IPropertyStore store, PROPERTYKEY key) {
            PROPVARIANT pv = new PROPVARIANT();
            try {
                PROPERTYKEY k = key; // readonly statics can't be passed by ref
                if (store.GetValue(ref k, out pv) != 0) return "";
                if (pv.vt == 31 && pv.data1 != IntPtr.Zero) // VT_LPWSTR
                    return Marshal.PtrToStringUni(pv.data1);
                return "";
            } catch { return ""; }
            finally { try { Ole32.PropVariantClear(ref pv); } catch {} }
        }

        static uint ReadUIntProp(IPropertyStore store, PROPERTYKEY key, uint fallback) {
            PROPVARIANT pv = new PROPVARIANT();
            try {
                PROPERTYKEY k = key;
                if (store.GetValue(ref k, out pv) != 0) return fallback;
                if (pv.vt == 19) return (uint)pv.data1.ToInt64(); // VT_UI4
                return fallback;
            } catch { return fallback; }
            finally { try { Ole32.PropVariantClear(ref pv); } catch {} }
        }

        static string StateLabel(uint state) {
            switch (state) {
                case 1: return "Active";
                case 2: return "Disabled";
                case 4: return "NotPresent";
                case 8: return "Unplugged";
                default: return "Unknown";
            }
        }

        static string FormFactorLabel(uint ff) {
            switch (ff) {
                case 0: return "RemoteNetwork";
                case 1: return "Speakers";
                case 2: return "LineLevel";
                case 3: return "Headphones";
                case 4: return "Microphone";
                case 5: return "Headset";
                case 6: return "Handset";
                case 7: return "DigitalPassthrough";
                case 8: return "SPDIF";
                case 9: return "DigitalDisplay";
                default: return "Unknown";
            }
        }
    }
}
'@

    $coreAudioLoaded = $false
    try {
        # Key the cached DLL by a hash of the source so any code change
        # compiles to a new file name instead of loading a stale build.
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($coreAudioSource))
        $hash = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 12)
        $dllPath = Join-Path $env:TEMP ("PulseCoreAudio-" + $hash + ".dll")

        if (-not (Test-Path -LiteralPath $dllPath)) {
            # Compile to a per-process temp name, then move into place, so two
            # concurrent polls can't clobber each other's half-written DLL. If
            # the move loses the race, the winner's identical DLL is loaded.
            $tmpPath = $dllPath + "." + $PID + ".tmp"
            Add-Type -TypeDefinition $coreAudioSource -OutputAssembly $tmpPath -ErrorAction Stop
            try {
                Move-Item -LiteralPath $tmpPath -Destination $dllPath -Force -ErrorAction Stop
            } catch {
                Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path -LiteralPath $dllPath) {
            Add-Type -Path $dllPath -ErrorAction Stop
            $coreAudioLoaded = $true
        }
    } catch {
        $coreAudioLoaded = $false
    }

    if (-not $coreAudioLoaded) {
        # Cache path failed (locked TEMP, antivirus, corrupt DLL) - fall back
        # to the slow-but-sure in-memory compile.
        Add-Type -TypeDefinition $coreAudioSource -ErrorAction Stop
    }
}
