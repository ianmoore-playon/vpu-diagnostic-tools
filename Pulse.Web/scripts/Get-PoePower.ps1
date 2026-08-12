#Requires -Version 5.1
<#
.SYNOPSIS
    ADLINK SmartPoE card budget + per-port PoE power draw (LOCAL collector).

.DESCRIPTION
    Ported from the gen-1 PowerShell tool (Modules/CameraConnectivity.psm1 ->
    "PoE Status", plus the AdlinkPoE P/Invoke shim in Modules/UIHelpers.psm1
    and the Get-AdlinkCardInfo NIC gate in Run.ps1, all at 3ca61dc). The
    Pulse.WPF port of the same feature dropped the NIC gate and regressed the
    low-budget threshold to a flat 55 W; both are restored here.

    Three gates, cheapest first, so an unsupported box never loads the driver:

      1. NIC model. Only the Intel I210 / I211 (ADLINK GIE74P) expose PoE
         telemetry. The 82574L (GIE64) and I350 / I354 (GIE74P-AN) do not --
         Register_Card either fails or hangs on those, so we never call it.
      2. SmartPoE.dll presence. It ships with the ADLINK driver bundle, NOT
         with Windows. A supported NIC with no bundle installed reports
         available=false with an actionable reason.
      3. Crash sentinel (see below).

    Crash sentinel: unlike gen-1 (one probe per diagnostic run) this collector
    is polled every ~2s to drive a live card. The native DLL is known to throw
    AccessViolation on some platforms, and an AV is a corrupted-state
    exception that .NET Framework will NOT let us catch -- it takes
    powershell.exe down with it. Left unguarded that becomes a crash loop
    spawning a dying process every 2s. So we increment a TEMP sentinel before
    the first native call and clear it after the reads land; three unfinished
    attempts latch the probe off until Pulse restarts (the launcher clears
    stale sentinels) or the tech clears TEMP.

    PS 5.1 portability (see CLAUDE.md):
      - Pure ASCII only. No em-dashes or smart quotes in this file.
      - The DllImport declarations live in compiled C# (C# 5 / CodeDom safe),
        never as script-level casts.
      - Every unwanted native return value is cast to [void] so it cannot
        land on stdout ahead of the JSON payload.

.OUTPUTS
    Single JSON object on stdout. See $result construction at the bottom.
#>

$ErrorActionPreference = "Stop"

# Port count on the GIE74P PSE controller. Card index is always 0 -- the VPU
# chassis has one PoE NIC.
$PortCount = 4
$CardNum   = 0

# IEEE 802.3at PoE+ per-port ceiling. Used to scale the low-budget threshold.
$PoePlusWattsPerPort = 25.5

$SentinelPath  = Join-Path $env:TEMP "PulsePoE-probe.sentinel"
$SentinelLimit = 3

function New-PoeResult {
    param(
        [bool]$Supported,
        [bool]$Available,
        [string]$NicModel   = "",
        [string]$CardLabel  = "",
        [string]$Reason     = "",
        [string]$DllPath    = ""
    )
    [ordered]@{
        supported = $Supported
        available = $Available
        nicModel  = $NicModel
        cardLabel = $CardLabel
        reason    = $Reason
        dllPath   = $DllPath
        budget    = $null
        ports     = @()
    }
}

function Write-PoeJson {
    param($Result)
    $Result | ConvertTo-Json -Depth 5 -Compress
}

# ---------------------------------------------------------------------------
# Gate 1 -- NIC model. Mirrors Get-AdlinkCardInfo from gen-1 Run.ps1 exactly,
# including which families are deliberately unsupported.
# ---------------------------------------------------------------------------
function Get-AdlinkCardInfo {
    $nics = @()
    try {
        $nics = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object {
            $_.InterfaceDescription -match 'I210|I211|I350|I354|82574L'
        })
    } catch {
        # Get-NetAdapter unavailable (rare, non-fleet host) -- fall back to WMI.
        try {
            $nics = @(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
                Where-Object { $_.Name -match 'I210|I211|I350|I354|82574L' } |
                ForEach-Object { [pscustomobject]@{ InterfaceDescription = $_.Name } })
        } catch { $nics = @() }
    }

    $desc  = if ($nics.Count -gt 0) { [string]$nics[0].InterfaceDescription } else { "" }
    $count = $nics.Count

    if ($desc -like "*82574L*") {
        [pscustomobject]@{ Model = "82574L"; Label = "ADLINK GIE64 (Intel 82574L x$count)";    Supported = $false }
    } elseif ($desc -like "*I210*") {
        [pscustomobject]@{ Model = "I210";   Label = "ADLINK GIE74P (Intel I210 x$count)";     Supported = $true  }
    } elseif ($desc -like "*I211*") {
        [pscustomobject]@{ Model = "I211";   Label = "ADLINK GIE74P (Intel I211 x$count)";     Supported = $true  }
    } elseif ($desc -like "*I350*") {
        [pscustomobject]@{ Model = "I350";   Label = "ADLINK GIE74P-AN (Intel I350 x$count)";  Supported = $false }
    } elseif ($desc -like "*I354*") {
        [pscustomobject]@{ Model = "I354";   Label = "ADLINK GIE74P-AN (Intel I354 x$count)";  Supported = $false }
    } elseif ($count -gt 0) {
        [pscustomobject]@{ Model = "Unknown"; Label = "Unknown NIC ($desc)";                   Supported = $false }
    } else {
        [pscustomobject]@{ Model = "None";    Label = "No camera NIC detected";                Supported = $false }
    }
}

$card = Get-AdlinkCardInfo

if (-not $card.Supported) {
    $reason = switch ($card.Model) {
        "82574L" { "PoE power telemetry is not available on the ADLINK GIE64 (Intel 82574L) camera NIC. This card family does not expose a PSE management interface -- the ports still deliver power, it just cannot be measured." }
        "I350"   { "PoE power telemetry is not available on the ADLINK GIE74P-AN (Intel I350) camera NIC. This card family does not expose a PSE management interface." }
        "I354"   { "PoE power telemetry is not available on the ADLINK GIE74P-AN (Intel I354) camera NIC. This card family does not expose a PSE management interface." }
        "None"   { "No Intel camera NIC (I210 / I211 / I350 / 82574L) was detected on this system, so there is no PoE card to measure." }
        default  { "PoE power telemetry requires an ADLINK GIE74P card (Intel I210 or I211). This system reports: $($card.Label)" }
    }
    Write-PoeJson (New-PoeResult -Supported $false -Available $false `
        -NicModel $card.Model -CardLabel $card.Label -Reason $reason)
    exit 0
}

# ---------------------------------------------------------------------------
# Gate 2 -- locate SmartPoE.dll. Same search order as gen-1 Run.ps1: known
# install paths, then the ADLINK registry keys, then a bounded recursive walk
# of the ADLINK trees only (never all of Program Files -- that walk took
# seconds on a spinning disk and this collector is polled).
# ---------------------------------------------------------------------------
function Find-SmartPoeDll {
    $candidates = @(
        "C:\Program Files\ADLINK\GIE Series\Library\Dll\x64\SmartPoE.dll"
        (Join-Path $env:SystemRoot "System32\SmartPoE.dll")
        "C:\Program Files\ADLINK\SmartPoE\SmartPoE.dll"
        "C:\Program Files (x86)\ADLINK\SmartPoE\SmartPoE.dll"
        "C:\Program Files\ADLINK\PCIe-GIE7x\SmartPoE.dll"
        "C:\ADLINK\SmartPoE\SmartPoE.dll"
    )
    foreach ($c in $candidates) {
        try { if (Test-Path -LiteralPath $c) { return $c } } catch { }
    }

    foreach ($reg in @(
        "HKLM:\SOFTWARE\ADLINK\SmartPoE"
        "HKLM:\SOFTWARE\WOW6432Node\ADLINK\SmartPoE"
        "HKLM:\SOFTWARE\ADLINK\GigE Tool"
    )) {
        try {
            $install = Get-ItemPropertyValue -Path $reg -Name "InstallDir" -ErrorAction Stop
            if ($install) {
                $c = Join-Path $install "SmartPoE.dll"
                if (Test-Path -LiteralPath $c) { return $c }
            }
        } catch { }
    }

    foreach ($root in @("C:\Program Files\ADLINK", "C:\Program Files (x86)\ADLINK", "C:\ADLINK")) {
        try {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            $found = Get-ChildItem -LiteralPath $root -Recurse -Filter "SmartPoE.dll" `
                        -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -notlike "*x86*" } |
                     Select-Object -First 1
            if ($found) { return $found.FullName }
        } catch { }
    }
    return $null
}

$dllPath = Find-SmartPoeDll

if (-not $dllPath) {
    Write-PoeJson (New-PoeResult -Supported $true -Available $false `
        -NicModel $card.Model -CardLabel $card.Label `
        -Reason "This VPU has a PoE-capable $($card.Model) camera NIC, but the ADLINK SmartPoE driver bundle (SmartPoE.dll) is not installed. Install the ADLINK GIE Series driver package to read per-port power draw.")
    exit 0
}

# ---------------------------------------------------------------------------
# Gate 3 -- crash sentinel. See the header note on AccessViolation.
# ---------------------------------------------------------------------------
$crashCount = 0
try {
    if (Test-Path -LiteralPath $SentinelPath) {
        $raw = Get-Content -LiteralPath $SentinelPath -Raw -ErrorAction Stop
        [void][int]::TryParse($raw.Trim(), [ref]$crashCount)
    }
} catch { $crashCount = 0 }

if ($crashCount -ge $SentinelLimit) {
    Write-PoeJson (New-PoeResult -Supported $true -Available $false `
        -NicModel $card.Model -CardLabel $card.Label -DllPath $dllPath `
        -Reason "The SmartPoE driver crashed the power probe $crashCount times in a row, so live monitoring has been disabled to stop it retrying. Restart Pulse to try again; if it keeps failing, the ADLINK driver bundle likely needs reinstalling.")
    exit 0
}

try {
    Set-Content -LiteralPath $SentinelPath -Value ([string]($crashCount + 1)) -Encoding ASCII -ErrorAction Stop
} catch { }

# ---------------------------------------------------------------------------
# Native shim. Compiled once to a hash-keyed DLL in TEMP -- every poll is a
# fresh powershell.exe and Add-Type -TypeDefinition shells out to csc.exe
# (1-3s), which would make a 2s live poll crawl. Same approach as
# _AudioInterop.ps1; any failure on the cache path falls back to the slow
# in-memory compile so behaviour never changes.
# ---------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'Pulse.AdlinkPoE').Type) {
    $poeSource = @'
using System.Runtime.InteropServices;

namespace Pulse {
    public static class AdlinkPoE {
        // Register_Card takes the card index (0 for the first card) and
        // returns 0 on success, negative on error.
        [DllImport("SmartPoE.dll")]
        public static extern short SmartPoE_Register_Card(ushort wCardNumber);
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
}
'@

    # The late-bound DllImport resolves "SmartPoE.dll" off PATH, so prepend
    # the directory we actually found it in.
    try {
        $dllDir = [System.IO.Path]::GetDirectoryName($dllPath)
        if ($dllDir -and ($env:PATH -notlike "*$dllDir*")) {
            $env:PATH = "$dllDir;$env:PATH"
        }
    } catch { }

    $poeLoaded = $false
    try {
        $md5       = [System.Security.Cryptography.MD5]::Create()
        $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($poeSource))
        $hash      = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 12)
        $cacheDll  = Join-Path $env:TEMP ("PulseAdlinkPoE-" + $hash + ".dll")

        if (-not (Test-Path -LiteralPath $cacheDll)) {
            # Compile to a per-process name then move into place, so two
            # concurrent polls cannot load a half-written DLL.
            $tmpPath = $cacheDll + "." + $PID + ".tmp"
            Add-Type -TypeDefinition $poeSource -OutputAssembly $tmpPath -ErrorAction Stop
            try {
                Move-Item -LiteralPath $tmpPath -Destination $cacheDll -Force -ErrorAction Stop
            } catch {
                Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path -LiteralPath $cacheDll) {
            Add-Type -Path $cacheDll -ErrorAction Stop
            $poeLoaded = $true
        }
    } catch { $poeLoaded = $false }

    if (-not $poeLoaded) {
        Add-Type -TypeDefinition $poeSource -ErrorAction Stop
    }
}

# ---------------------------------------------------------------------------
# Read the card. Everything below is best-effort: a driver that loads but
# fails a read reports available=false with the exception type rather than
# throwing out of the collector.
# ---------------------------------------------------------------------------
$registered = $false
try {
    $regRet = [Pulse.AdlinkPoE]::SmartPoE_Register_Card([uint16]$CardNum)
    if ($regRet -ne 0) {
        try { Remove-Item -LiteralPath $SentinelPath -Force -ErrorAction SilentlyContinue } catch { }
        Write-PoeJson (New-PoeResult -Supported $true -Available $false `
            -NicModel $card.Model -CardLabel $card.Label -DllPath $dllPath `
            -Reason "The SmartPoE driver is installed but reported no PoE card (Register_Card returned $regRet). The card may be seated badly, or the driver may not match this card revision.")
        exit 0
    }
    $registered = $true

    $consumed = 0.0
    $remaining = 0.0
    $tempC = 0.0
    [void][Pulse.AdlinkPoE]::SmartPoE_Get_POEConsPowbudget([uint16]$CardNum, [ref]$consumed)
    [void][Pulse.AdlinkPoE]::SmartPoE_Get_POELeftPowbudget([uint16]$CardNum, [ref]$remaining)
    [void][Pulse.AdlinkPoE]::SmartPoE_Get_Temperature([uint16]$CardNum, [ref]$tempC)
    $total = $consumed + $remaining

    # Port index 0..3 on the PSE controller maps to chassis Port 1..4, matching
    # gen-1's "P{index+1}" labelling. Unverified against a live GIE74P since
    # VPU2 was unreachable -- confirm the mapping on a real card before
    # trusting a single-port reading to identify a specific camera.
    $ports     = @()
    $poeOnCount = 0
    for ($i = 0; $i -lt $PortCount; $i++) {
        $voltage = 0.0
        $current = 0.0
        [void][Pulse.AdlinkPoE]::SmartPoE_Get_PSEPortVoltage([uint16]$CardNum, [uint16]$i, [ref]$voltage)
        [void][Pulse.AdlinkPoE]::SmartPoE_Get_PSEPortCurrent([uint16]$CardNum, [uint16]$i, [ref]$current)
        $watts = $voltage * $current
        # >1 V means the PSE has actually powered the pair up; an unpowered
        # port floats near zero rather than at exactly zero.
        $isOn = ($voltage -gt 1.0)
        if ($isOn) { $poeOnCount++ }
        # Hoisted out of the hashtable literal on purpose: an inline if-else as
        # a hashtable value is a 5.1 parsing hazard even though pwsh 7 accepts
        # it. Same reason the rest of this file keeps values simple.
        $stateStr = "Off"
        if ($isOn) { $stateStr = "Powered" }
        $ports += [ordered]@{
            port    = $i + 1
            voltage = [math]::Round($voltage, 2)
            current = [math]::Round($current, 3)
            watts   = [math]::Round($watts, 1)
            poeOn   = $isOn
            state   = $stateStr
        }
    }

    # Low-budget verdict. This is gen-1's D8 fix, NOT the flat 55 W the WPF
    # port shipped: 4 PoE+ ports need 4 * 25.5 = 102 W, so 55 W silently
    # passes a genuinely starved card. Scale the expectation to how many ports
    # are actually drawing, and only judge at 3+ active ports -- with 1-2
    # cameras a smaller budget is normal and would false-positive.
    $expected = [math]::Round($poeOnCount * $PoePlusWattsPerPort, 1)
    $low      = ($total -gt 0) -and ($poeOnCount -ge 3) -and ($total -lt $expected)

    $result = New-PoeResult -Supported $true -Available $true `
        -NicModel $card.Model -CardLabel $card.Label -DllPath $dllPath
    $result.budget = [ordered]@{
        totalW     = [math]::Round($total, 1)
        consumedW  = [math]::Round($consumed, 1)
        remainingW = [math]::Round($remaining, 1)
        tempC      = [math]::Round($tempC, 1)
        poeOnCount = $poeOnCount
        expectedW  = $expected
        low        = $low
    }
    $result.ports = $ports

    # Reads landed -- the driver did not take the process down.
    try { Remove-Item -LiteralPath $SentinelPath -Force -ErrorAction SilentlyContinue } catch { }

    Write-PoeJson $result
} catch {
    $errType = $_.Exception.GetType().Name
    $errMsg  = ($_.Exception.Message -replace "[\r\n]+", " ")
    try { Remove-Item -LiteralPath $SentinelPath -Force -ErrorAction SilentlyContinue } catch { }
    Write-PoeJson (New-PoeResult -Supported $true -Available $false `
        -NicModel $card.Model -CardLabel $card.Label -DllPath $dllPath `
        -Reason "Reading PoE power failed ($errType): $errMsg")
} finally {
    if ($registered) {
        try { [void][Pulse.AdlinkPoE]::SmartPoE_Release_Card([uint16]$CardNum) } catch { }
    }
}
