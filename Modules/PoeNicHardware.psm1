# =============================================================================
#  PoeNicHardware.psm1  —  ADLINK SmartPoE DLL discovery + stub panel
#  Top-level code runs at dot-source time (DLL search, P/Invoke).
#  Build-PoEPanel is called by the launcher after the form is created.
# =============================================================================

# ---------- ADLINK SmartPoE DLL search ---------------------------------------
$PoeDllPath = $null
foreach ($c in @(
    "C:\Program Files\ADLINK\GIE Series\Library\Dll\x64\SmartPoE.dll"
    "$env:SystemRoot\System32\SmartPoE.dll"
    "C:\Program Files\ADLINK\SmartPoE\SmartPoE.dll"
    "C:\Program Files (x86)\ADLINK\SmartPoE\SmartPoE.dll"
    "C:\Program Files\ADLINK\PCIe-GIE7x\SmartPoE.dll"
    "C:\ADLINK\SmartPoE\SmartPoE.dll"
)) { if (Test-Path $c) { $PoeDllPath = $c; break } }

if (-not $PoeDllPath) {
    foreach ($reg in @("HKLM:\SOFTWARE\ADLINK\SmartPoE","HKLM:\SOFTWARE\WOW6432Node\ADLINK\SmartPoE","HKLM:\SOFTWARE\ADLINK\GigE Tool")) {
        try {
            $k = Get-ItemPropertyValue $reg "InstallDir" -ErrorAction Stop
            $c = Join-Path $k "SmartPoE.dll"; if (Test-Path $c) { $PoeDllPath = $c; break }
        } catch { }
    }
}
if (-not $PoeDllPath) {
    foreach ($root in @("C:\Program Files\ADLINK","C:\Program Files (x86)\ADLINK","C:\ADLINK")) {
        if (Test-Path $root) {
            $found = Get-ChildItem $root -Recurse -Filter "SmartPoE.dll" -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -notlike "*x86*" } | Select-Object -First 1
            if ($found) { $PoeDllPath = $found.FullName; break }
        }
    }
}

# ---------- ADLINK P/Invoke --------------------------------------------------
if ($PoeDllPath -and -not ([System.Management.Automation.PSTypeName]'AdlinkPoE').Type) {
    $env:PATH = "$([System.IO.Path]::GetDirectoryName($PoeDllPath));$env:PATH"
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class AdlinkPoE {
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Register_Card(ushort card_num);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Release_Card(ushort wCardNumber);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_Temperature(ushort wCardNumber, out double wTemperature);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_POEConsPowbudget(ushort wCardNumber, out double wPower);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_POELeftPowbudget(ushort wCardNumber, out double wPower);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_PSEPortCurrent(ushort wCardNumber, ushort PortNumber, out double wCurrent);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_PSEPortVoltage(ushort wCardNumber, ushort PortNumber, out double wVoltage);
}
"@
}

# ---------- Panel builder (call after form is created) -----------------------
function Build-PoEPanel {
    $script:pnlPoE = New-StubPanel "PoE / NIC Hardware" "Check PoE power, NIC status and hardware health."
}
