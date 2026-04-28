# =============================================================================
#  VPU Cable & NIC Troubleshooter  v1.6.6
#  GUI diagnostic tool for Pixellot VPU camera NIC and cable issues.
#
#  HOW TO RUN (one-liner):
#    irm 'https://raw.githubusercontent.com/ianmoore-playon/pixellot-vpu-tools/refs/heads/main/TestCameraConnectivity.ps1' | iex
# =============================================================================

$ScriptUrl = "https://raw.githubusercontent.com/ianmoore-playon/pixellot-vpu-tools/refs/heads/main/TestCameraConnectivity.ps1"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden"
    if ($PSCommandPath) {
        Start-Process PowerShell -Verb RunAs -ArgumentList "$elevArgs -File `"$PSCommandPath`""
    } else {
        Start-Process PowerShell -Verb RunAs -ArgumentList "$elevArgs -Command `"irm '$ScriptUrl' | iex`""
    }
    exit
}

# ---------- Configuration ----------------------------------------------------
$ScriptVersion      = "1.6.6"
$OutputBaseDir      = if ($PSScriptRoot) { $PSScriptRoot } else { [Environment]::GetFolderPath('Desktop') }
$OutputDir          = Join-Path $OutputBaseDir "CameraLink_Results"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$NicDriverPatterns  = @("Intel(R) 82574L*", "Intel(R) I210*")
$RenegotiateWaitSec = 30
$EventLogHours      = 48
$PixellotLogPaths   = @(
    "C:\Pixellot\Data\Log"
    "C:\Pixellot\logs"
    "C:\Pixellot\Logs"
    "C:\Program Files\Pixellot\logs"
    "C:\ProgramData\Pixellot\logs"
)
$CameraIPs = @(
    [PSCustomObject]@{ IP = "169.254.16.50"; Label = "Camera 1 (main)";       Optional = $false }
    [PSCustomObject]@{ IP = "169.254.16.51"; Label = "Camera 2 / DoublePlay"; Optional = $false }
    [PSCustomObject]@{ IP = "169.254.16.52"; Label = "OCR camera (optional)"; Optional = $true  }
)
$RtspPort    = 554
$OcrMacOui   = "00-D0-89"

# ---------- WinForms ---------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

Add-Type -TypeDefinition @"
using System.Drawing;
using System.Drawing.Drawing2D;
public static class GfxHelper {
    public static GraphicsPath RoundedRect(Rectangle r, int radius) {
        int d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}
"@ -ReferencedAssemblies System.Drawing

$ColSidebar  = [System.Drawing.Color]::FromArgb(24,  33,  47)
$ColNavHover = [System.Drawing.Color]::FromArgb(51,  65,  85)
$ColNavActive= [System.Drawing.Color]::FromArgb(59, 130, 246)
$ColAccent   = [System.Drawing.Color]::FromArgb(59, 130, 246)
$ColBg       = [System.Drawing.Color]::FromArgb(243,244,246)
$ColCard     = [System.Drawing.Color]::White
$ColBorder   = [System.Drawing.Color]::FromArgb(226,232,240)
$ColText     = [System.Drawing.Color]::FromArgb(17,  24,  39)
$ColMuted    = [System.Drawing.Color]::FromArgb(107,114, 128)
$ColGreen    = [System.Drawing.Color]::FromArgb(22, 163,  74)
$ColRed      = [System.Drawing.Color]::FromArgb(220,  38,  38)
$ColYellow   = [System.Drawing.Color]::FromArgb(202, 138,   4)
$ColLogBg    = [System.Drawing.Color]::FromArgb(15,  23,  42)

# ---------- Shared state (runspace <-> UI timer) ----------------------------
$sync = [hashtable]::Synchronized(@{
    SummaryQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    Running    = $false
    Complete   = $false
    Cancelled  = $false
    AllClear   = $false
    VpuModel   = ""
    OutputFile = ""
    RunId      = ""
    TotalDowngrades = 0
    LastRunLine     = ""
    CurrentStep     = "Ready"
    StepsDone   = [hashtable]::Synchronized(@{})
    Cards = @{
        SmartSpeed = @{ Value = "--"; Status = "neutral" }
        PingCHU    = @{ Value = "--"; Status = "neutral" }
        ArpEntry   = @{ Value = "--"; Status = "neutral" }
        ChuDetect  = @{ Value = "--"; Status = "neutral" }
    }
    PortResults     = [System.Collections.ArrayList]::new()
    CamResults      = [System.Collections.ArrayList]::new()
    AppIssues       = [System.Collections.ArrayList]::new()
    NextSteps       = [System.Collections.ArrayList]::new()
    UpdateAvailable = ""
    AppLogTime      = $null
})

# ---------- Diagnostic engine (runs in background runspace) -----------------
$DiagScript = {
    param($sync, $NicDriverPatterns, $RenegotiateWaitSec, $EventLogHours,
          $PixellotLogPaths, $CameraIPs, $RtspPort, $OutputFile, $RunId, $ScriptVersion,
          [string]$OcrMacOui = "00-D0-89",
          [string]$FilterNic = "")

    function Add-Log {
        param([string]$Message, [string]$Level = "Info")
        Add-Content -Path $OutputFile -Value $Message -ErrorAction SilentlyContinue
    }

    function Add-Summary {
        param([string]$Label, [string]$Result, [string]$Level = "Info")
        $sync.SummaryQueue.Enqueue(@{ Label = $Label; Result = $Result; L = $Level })
        Add-Content -Path $OutputFile -Value ("  {0,-24}{1}" -f $Label, $Result) -ErrorAction SilentlyContinue
    }

    function Add-Section {
        param([string]$Title)
        $sync.SummaryQueue.Enqueue(@{ Label = ""; Result = $Title; L = "Section" })
    }

    function Set-Card {
        param([string]$Key, [string]$Value, [string]$Status = "neutral")
        $sync.Cards[$Key] = @{ Value = $Value; Status = $Status }
    }

    function Get-AdapterSpeedMbps {
        param([string]$AdapterName)
        try {
            $a = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
            if ($a.Status -ne "Up") { return 0 }
            $ls = $a.LinkSpeed.ToString()
            if ($ls -match '(\d+(?:\.\d+)?)\s*Gbps') { return [int]([double]$Matches[1] * 1000) }
            if ($ls -match '(\d+(?:\.\d+)?)\s*Mbps') { return [int]$Matches[1] }
            if ($ls -match '^\d+$') { return [math]::Round([double]$ls / 1e6) }
            return -1
        } catch { return -1 }
    }

    function Get-AdapterPeakSpeedMbps {
        param([string]$AdapterName, [int]$SampleSeconds = 12, [int]$IntervalMs = 750)
        $peak = 0; $deadline = (Get-Date).AddSeconds($SampleSeconds)
        while ((Get-Date) -lt $deadline) {
            $s = Get-AdapterSpeedMbps -AdapterName $AdapterName
            if ($s -gt $peak) { $peak = $s }
            if ($peak -ge 1000) { break }
            Start-Sleep -Milliseconds $IntervalMs
        }
        return $peak
    }

    function Set-AdapterSpeedDuplex {
        param([string]$AdapterName, [string]$Val)
        foreach ($kw in @('*SpeedDuplex','SpeedDuplex')) {
            try {
                Get-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -ErrorAction Stop | Out-Null
                Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -RegistryValue $Val -ErrorAction Stop
                return $true
            } catch { continue }
        }
        return $false
    }

    function Get-EventAdapterName {
        param($Evt, [string[]]$KnownDescs)
        $n = try { $m = $Evt.Message; if ($m -and $m -notlike "*description string*") { ($m -split "`n")[0].Trim() } else { "" } } catch { "" }
        if ($KnownDescs -contains $n) { return $n }
        $n = try { $found = ""; foreach ($d in @(([xml]$Evt.ToXml()).Event.EventData.Data)) { if ($KnownDescs -contains $d.InnerText.Trim()) { $found = $d.InnerText.Trim(); break } }; $found } catch { "" }
        if ($KnownDescs -contains $n) { return $n }
        $n = try { $found = ""; foreach ($p in $Evt.Properties) { $v = $p.Value.ToString().Trim(); if ($KnownDescs -contains $v) { $found = $v; break } }; $found } catch { "" }
        return $n
    }

    function Test-TcpPort {
        param([string]$IP, [int]$Port, [int]$TimeoutMs = 2000)
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $c   = $tcp.BeginConnect($IP, $Port, $null, $null)
            $ok  = $c.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok) { $tcp.EndConnect($c) }
            $tcp.Close(); return $ok
        } catch { return $false }
    }

    # ── Init ──────────────────────────────────────────────────────────────────
    $sync.Running = $true; $sync.Complete = $false; $sync.AllClear = $false
    $sync.PortResults.Clear(); $sync.CamResults.Clear()
    $sync.AppIssues.Clear();   $sync.NextSteps.Clear()
    $sync.TotalDowngrades = 0; $sync.LastRunLine = ""; $sync.AppLogTime = $null
    $item = $null
    while ($sync.SummaryQueue.TryDequeue([ref]$item)) { }
    $sync.StepsDone.Clear()

    "" | Set-Content -Path $OutputFile -ErrorAction SilentlyContinue
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # ── VPU model detection ───────────────────────────────────────────────────
    $sync.CurrentStep = "Detecting VPU model..."
    $VpuModel = $null; $VpuUnitId = $null; $VpuType = $null

    # Search all known log paths; also try one level of subdirectory for non-standard layouts
    $searchPaths = @()
    foreach ($lp in $PixellotLogPaths) {
        $searchPaths += $lp
        try {
            $subs = Get-ChildItem -Path $lp -Directory -ErrorAction SilentlyContinue
            if ($subs) { $searchPaths += $subs.FullName }
        } catch { }
    }

    foreach ($lp in $searchPaths) {
        if (-not (Test-Path $lp)) { continue }
        $ag = Get-ChildItem -Path $lp -Filter "agent_*.log" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $ag) { continue }
        $agLines = Get-Content -Path $ag.FullName -ErrorAction SilentlyContinue
        if (-not $agLines) { continue }
        foreach ($line in $agLines) {
            if (-not $VpuModel -and $line -match '"paramName"\s*:\s*"vpuName"[^}]*"paramValue"\s*:\s*"([^"]+)"') {
                $raw = $Matches[1]
                if ($raw -match '^(PXL\w+?)_(\d+)') { $VpuModel = $Matches[1]; $VpuUnitId = $Matches[2] }
            }
            if (-not $VpuType -and $line -match '"paramName"\s*:\s*"presentedProductType"[^}]*"paramValue"\s*:\s*"([^"]+)"') {
                $VpuType = $Matches[1]
            }
            if ($VpuModel -and $VpuType) { break }
        }
        if ($VpuModel) { break }
    }

    # Fallback: scrape VPU Manager SPA title (requires browser open)
    if (-not $VpuModel) {
        try {
            $pg = Invoke-WebRequest -Uri "http://localhost:32323/" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($pg.Content -match '<title>[^<]*(PXL\w+?)_(\d+)') { $VpuModel = $Matches[1]; $VpuUnitId = $Matches[2] }
        } catch { }
    }

    $typeStr = if ($VpuType) { " / $VpuType" } else { "" }
    $sync.VpuModel = if ($VpuModel) { "$VpuModel  (Unit ID: $VpuUnitId)$typeStr" } else { "Not detected" }

    $hdr = "================================================================`n Pixellot VPU - Camera Diagnostic  v$ScriptVersion`n================================================================`n Computer : $($env:COMPUTERNAME)`n User     : $($env:USERNAME)`n Date/Time: $ts`n Run ID   : $RunId`n VPU Model: $($sync.VpuModel)`n================================================================"
    Add-Log $hdr "Cyan"
    Add-Log ""
    Add-Section "System"
    Add-Summary "VPU Model" $sync.VpuModel $(if ($VpuModel) { "Info" } else { "Warn" })

    # ── Find NIC ports ────────────────────────────────────────────────────────
    $sync.CurrentStep = "Detecting NIC ports..."
    Add-Log "-- Detecting Camera NIC Ports --" "Cyan"
    Add-Log ""
    Add-Section "Ports"
    $nicPorts = Get-NetAdapter | Where-Object {
        $d = $_.InterfaceDescription
        ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
    } | Sort-Object {
        try { (Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction Stop).Function } catch { 999 }
    }, Name

    if ($FilterNic) {
        $nicPorts = @($nicPorts | Where-Object { $_.Name -eq $FilterNic })
    }

    if ($nicPorts.Count -eq 0) {
        Add-Log "  [FAIL] No camera NIC adapters found." "Fail"
        Add-Summary "NIC Detection" "No camera NICs found" "Fail"
        $sync.NextSteps.Add(@{
            H = "Wrong machine - no VPU hardware detected"
            B = "No compatible Intel camera NICs found. Run this tool directly on the Pixellot VPU."
        }) | Out-Null
        $sync.AllClear = $false
        $sync.Running = $false; $sync.Complete = $true
        return
    }
    Add-Log ("  Found {0} camera NIC port(s):" -f $nicPorts.Count) "Info"
    foreach ($n in $nicPorts) { Add-Log ("    - {0}  ({1})" -f $n.Name, $n.InterfaceDescription) "Info" }
    Add-Log ""
    $sync.StepsDone["NicDetect"] = "pass"
    Add-Summary "NIC Detection" "$($nicPorts.Count) port(s) found" "Pass"

    # ── SmartSpeed pre-scan ───────────────────────────────────────────────────
    $sync.CurrentStep = "Scanning event log..."
    $cutoff    = (Get-Date).AddHours(-$EventLogHours)
    $startTime = Get-Date
    $providers = @('e1iexpress','e1dexpress','e1rexpress')
    $ssIds     = @(27, 33, 40)
    $knownDescs= @($nicPorts | ForEach-Object { $_.InterfaceDescription })
    $events    = @()
    $ssHistory = @{}
    $ocrAdapters = @{}

    foreach ($prov in $providers) {
        $evts = Get-WinEvent -FilterHashtable @{
            LogName='System'; StartTime=$cutoff; EndTime=$startTime
            ProviderName=$prov; Id=$ssIds
        } -ErrorAction SilentlyContinue
        if ($evts) {
            $events += $evts
            foreach ($e in ($evts | Where-Object { $_.Id -eq 40 })) {
                $a = Get-EventAdapterName -Evt $e -KnownDescs $knownDescs
                if ($a) { $ssHistory[$a] = ($ssHistory[$a] -as [int]) + 1 }
            }
        }
    }

    # ── Link speed check ──────────────────────────────────────────────────────
    $sync.CurrentStep = "Checking link speeds..."
    Add-Log "-- Link Speed Check --" "Cyan"
    Add-Log ""
    $portResults = @()
    $bestSpeed   = 0
    $anyFail     = $false

    foreach ($nic in $nicPorts) {
        if ($sync.Cancelled) { break }
        $nm  = $nic.Name
        $spd = Get-AdapterSpeedMbps -AdapterName $nm
        $blinking = $false

        Add-Log ("  Adapter : {0}  ({1})" -f $nm, $nic.InterfaceDescription) "Info"
        Add-Log ("  Status  : {0}   MAC: {1}" -f $nic.Status, $nic.MacAddress) "Info"

        if ($spd -eq 0) {
            Add-Log "  [INFO]  No link - sampling 12s for intermittent connection..." "Warn"
            $sync.CurrentStep = "Sampling $nm for 12s..."
            $peak = Get-AdapterPeakSpeedMbps -AdapterName $nm -SampleSeconds 12
            if ($peak -gt 0) {
                $blinking = $true; $spd = $peak
                Add-Log ("  [INFO]  Intermittent link at {0} Mbps (SmartSpeed retry cycle)" -f $spd) "Warn"
            }
        }

        if ($spd -gt $bestSpeed) { $bestSpeed = $spd }

        if ($spd -eq 1000) {
            Add-Log "  Speed   : 1 Gbps  [OK]" "Pass"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=1000; Result="PASS"; Blinking=$false; Desc=$nic.InterfaceDescription }
            Set-Card $nm "1 Gbps" "ok"
            Add-Summary $nm "1 Gbps  OK" "Pass"
        } elseif ($spd -eq 100) {
            Add-Log "  Speed   : 100 Mbps  [DEGRADED]" "Fail"
            if (-not $ssHistory.ContainsKey($nic.InterfaceDescription)) {
                # Any events (ID 27/33) but no ID 40 → connected at 100M without ever attempting gigabit → confirmed OCR.
                # Zero events → could be OCR or a brand-new cable fault with no prior history yet.
                $hasAnyHistory = ($events | Where-Object {
                    (Get-EventAdapterName -Evt $_ -KnownDescs $knownDescs) -eq $nic.InterfaceDescription
                }).Count -gt 0
                $hasOcrMac = $false
                try {
                    $portIdx = (Get-NetAdapter -Name $nm -ErrorAction Stop).ifIndex
                    $hasOcrMac = ($null -ne (Get-NetNeighbor -InterfaceIndex $portIdx -ErrorAction SilentlyContinue |
                        Where-Object { $_.State -ne "Unreachable" -and $_.LinkLayerAddress -like "$OcrMacOui-*" } |
                        Select-Object -First 1))
                } catch { }
                $ocrAdapters[$nic.InterfaceDescription] = $true
                if ($hasOcrMac) {
                    $histNote = if ($hasAnyHistory) { "link-at-100M events + MAC $OcrMacOui confirmed" } else { "MAC $OcrMacOui confirmed, no prior event history" }
                    Add-Log "  [PASS]  Pixellot OCR camera identified ($histNote) — 100 Mbps expected. Skipping remediation." "Pass"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    Set-Card $nm "100 Mbps (OCR)" "ok"
                    Add-Summary $nm "100 Mbps  OCR camera" "Pass"
                } elseif ($hasAnyHistory) {
                    Add-Log "  [PASS]  Link-at-100M events present, no ID 40 — confirmed 100 Mbps-only device (OCR camera). Skipping remediation." "Pass"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    Set-Card $nm "100 Mbps (OCR)" "ok"
                    Add-Summary $nm "100 Mbps  OCR camera" "Pass"
                } else {
                    Add-Log "  [WARN]  No SmartSpeed history and MAC not yet in ARP cache — likely OCR camera, but cannot rule out new cable fault." "Warn"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR?)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    Set-Card $nm "100 Mbps (OCR)" "warn"
                    Add-Summary $nm "100 Mbps  OCR? (unconfirmed)" "Warn"
                }
            } else {
                Add-Log "  [ACTION] SmartSpeed history confirmed - attempting to force 1 Gbps..." "Warn"
                $sync.CurrentStep = "Forcing 1 Gbps on $nm..."
                Set-Card $nm "Forcing..." "warn"
                $forceOk = Set-AdapterSpeedDuplex -AdapterName $nm -Val "6"
                if ($forceOk) {
                    Restart-NetAdapter -Name $nm -Confirm:$false -ErrorAction SilentlyContinue
                    Add-Log ("  [INFO]  Waiting {0}s for re-negotiation..." -f $RenegotiateWaitSec) "Warn"
                    $sync.CurrentStep = "Waiting ${RenegotiateWaitSec}s for re-negotiation on $nm..."
                    Start-Sleep -Seconds $RenegotiateWaitSec
                    $newSpd = Get-AdapterSpeedMbps -AdapterName $nm
                    if ($newSpd -eq 1000) {
                        Add-Log "  [PASS]  Forced to 1 Gbps successfully." "Pass"
                        $portResults += [PSCustomObject]@{ Name=$nm; Speed=1000; Result="PASS (forced)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                        Set-Card $nm "1 Gbps" "ok"
                        Add-Summary $nm "1 Gbps  (forced OK)" "Pass"
                    } else {
                        $nsLabel = if ($newSpd -eq 0) { "Disconnected" } else { "$newSpd Mbps" }
                        Add-Log ("  [FAIL]  Still not 1 Gbps after forcing (current: {0}). Physical layer issue." -f $nsLabel) "Fail"
                        Add-Log "          Resetting to Auto Negotiation..." "Warn"
                        Set-AdapterSpeedDuplex -AdapterName $nm -Val "0" | Out-Null
                        Restart-NetAdapter -Name $nm -Confirm:$false -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 5
                        $autoSpd = Get-AdapterSpeedMbps -AdapterName $nm
                        if ($autoSpd -gt 0) { Add-Log ("  [INFO]  Link restored at {0} Mbps" -f $autoSpd) "Warn" }
                        $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="FAIL"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                        $anyFail = $true
                        Set-Card $nm "100 Mbps" "fail"
                        Add-Summary $nm "DEGRADED  cable fault" "Fail"
                    }
                } else {
                    Add-Log "  [FAIL]  Could not apply SpeedDuplex setting." "Fail"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="FAIL"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    $anyFail = $true
                    Set-Card $nm "100 Mbps" "fail"
                    Add-Summary $nm "DEGRADED  (SpeedDuplex failed)" "Fail"
                }
            }
        } elseif ($spd -eq 0) {
            Add-Log "  Speed   : No link - no cable or device powered off." "Gray"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=0; Result="NO LINK"; Blinking=$false; Desc=$nic.InterfaceDescription }
            Set-Card $nm "No link" "neutral"
            Add-Summary $nm "No link" "Gray"
        } else {
            Add-Log ("  Speed   : {0} Mbps - unexpected" -f $spd) "Warn"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="UNKNOWN"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
            Set-Card $nm "$spd Mbps" "warn"
            Add-Summary $nm "$spd Mbps  unexpected" "Warn"
        }
        Add-Log ""
    }

    $sync.StepsDone["LinkSpeed"] = if ($anyFail) { "fail" } else { "pass" }
    foreach ($r in $portResults) { $sync.PortResults.Add($r) | Out-Null }

    # ── SmartSpeed event display ──────────────────────────────────────────────
    $sync.CurrentStep = "Processing SmartSpeed events..."
    Add-Section "Signal Quality"
    $chuEvents = $events | Where-Object {
        $a = Get-EventAdapterName -Evt $_ -KnownDescs $knownDescs
        -not $ocrAdapters.ContainsKey($a)
    }
    $sync.TotalDowngrades = ($chuEvents | Where-Object { $_.Id -eq 40 }).Count

    Add-Log "-- Intel SmartSpeed Event Log (last $EventLogHours hours) --" "Cyan"
    Add-Log ""
    if ($chuEvents.Count -gt 0) {
        $dCnt = ($chuEvents | Where-Object { $_.Id -eq 40 }).Count
        $wCnt = ($chuEvents | Where-Object { $_.Id -eq 27 }).Count
        $ssLevel = if ($dCnt -gt 0) { "Fail" } else { "Warn" }
        Add-Log ("  [WARN] {0} downgrade(s) and {1} link warning(s) on CHU ports in the last {2}h." -f $dCnt, $wCnt, $EventLogHours) $ssLevel
        Add-Log ""
        foreach ($evt in ($chuEvents | Sort-Object @{Expression='TimeCreated';Descending=$true} | Select-Object -First 10)) {
            $an = Get-EventAdapterName -Evt $evt -KnownDescs $knownDescs
            $shortName = if ($an -match '#(\d+)') { "CHU NIC #$($Matches[1])" } else { $an }
            $label = switch ($evt.Id) { 40 {"SmartSpeed Downgrade"} 33 {"Link at 100 Mbps"} 27 {"Link Warning"} default {"Event $($evt.Id)"} }
            Add-Log ("  {0}  {1}  ID {2} - {3}" -f $evt.TimeCreated.ToString("HH:mm:ss"), $shortName, $evt.Id, $label) "Warn"
        }
        Add-Log ""
        if ($dCnt -gt 0) {
            Add-Log "  -> Physical layer limitation confirmed. Likely cause: faulty cable or bad termination." "Info"
        }
        $sync.StepsDone["SmartSpeed"] = if ($dCnt -gt 0) { "fail" } else { "pass" }
        $ssSummary = if ($dCnt -gt 0) { "$dCnt downgrade(s) in ${EventLogHours}h" } else { "$wCnt warning(s), 0 downgrades" }
        Add-Summary "SmartSpeed Events" $ssSummary $ssLevel
        $ssCardVal    = if ($dCnt -gt 0) { "$dCnt events" } elseif ($wCnt -gt 0) { "$wCnt warnings" } else { "None" }
        $ssCardStatus = if ($dCnt -gt 0) { "fail" } elseif ($wCnt -gt 0) { "warn" } else { "ok" }
        Set-Card "SmartSpeed" $ssCardVal $ssCardStatus
    } else {
        Add-Log "  [PASS] No SmartSpeed downgrade events on CHU ports." "Pass"
        $sync.StepsDone["SmartSpeed"] = "pass"
        Add-Summary "SmartSpeed Events" "None in ${EventLogHours}h" "Pass"
        Set-Card "SmartSpeed" "None" "ok"
    }
    Add-Log ""

    # ── ARP check ─────────────────────────────────────────────────────────────
    Add-Section "Network"
    $sync.CurrentStep = "Checking ARP table..."
    $arpEntries = @()
    foreach ($nic in $nicPorts) {
        $idx = (Get-NetAdapter -Name $nic.Name).ifIndex
        $nb  = Get-NetNeighbor -InterfaceIndex $idx -ErrorAction SilentlyContinue |
               Where-Object { $_.State -ne "Unreachable" -and ([Convert]::ToInt32(($_.LinkLayerAddress -split '-')[0], 16) -band 1) -eq 0 }
        if ($nb) { $arpEntries += $nb }
    }
    if ($arpEntries.Count -gt 0) {
        Set-Card "ArpEntry" "Found" "ok"
        Add-Log ("  [PASS] {0} ARP entry/entries found in camera subnet." -f $arpEntries.Count) "Pass"
        Add-Summary "ARP Table" "$($arpEntries.Count) entry/entries found" "Pass"
    } else {
        Set-Card "ArpEntry" "Not Found" "neutral"
        Add-Log "  [INFO] No ARP entries found in camera subnet." "Gray"
        Add-Summary "ARP Table" "No entries" "Gray"
    }
    $sync.StepsDone["ArpGateway"] = "pass"
    Add-Log ""

    # ── Camera connectivity ───────────────────────────────────────────────────
    $sync.CurrentStep = "Testing camera connectivity..."
    Add-Section "Cameras"
    Add-Log "-- Camera Connectivity (Ping + RTSP Port 554) --" "Cyan"
    Add-Log ""
    $camResults = @()
    $mainPingCount = 0; $mainTotal = 0

    foreach ($cam in $CameraIPs) {
        if ($sync.Cancelled) { break }
        $sync.CurrentStep = "Pinging $($cam.IP)..."
        Add-Log ("  {0,-18} {1}" -f $cam.IP, $cam.Label) "Info"
        $pingOk = Test-Connection -ComputerName $cam.IP -Count 2 -Quiet -ErrorAction SilentlyContinue
        $rtspOk = $false

        if ($pingOk) {
            Add-Log "  Ping    : Responding" "Pass"
            $sync.CurrentStep = "Testing RTSP on $($cam.IP)..."
            $rtspOk = Test-TcpPort -IP $cam.IP -Port $RtspPort
            if ($rtspOk) { Add-Log "  RTSP 554: Port open  (camera stream reachable)" "Pass" }
            else          { Add-Log "  RTSP 554: Port closed or no response" "Fail" }
            if (-not $cam.Optional) { $mainPingCount++ }
            $rtspStr = if ($rtspOk) { "Ping OK / RTSP OK" } else { "Ping OK / RTSP FAIL" }
            $rtspLvl = if ($rtspOk) { "Pass" } else { "Fail" }
            Add-Summary $cam.IP $rtspStr $rtspLvl
        } else {
            $note = if ($cam.Optional) { " (expected - optional camera not installed)" } else { "" }
            Add-Log ("  Ping    : No response$note") "Gray"
            Add-Log "  RTSP 554: Skipped" "Gray"
            $noteStr = if ($cam.Optional) { "Not installed (optional)" } else { "No response" }
            $noteLvl = if ($cam.Optional) { "Gray" } else { "Fail" }
            Add-Summary $cam.IP $noteStr $noteLvl
        }
        if (-not $cam.Optional) { $mainTotal++ }
        $camResults += [PSCustomObject]@{ IP=$cam.IP; Label=$cam.Label; Ping=$pingOk; Rtsp=$rtspOk; Optional=$cam.Optional }
        Add-Log ""
    }

    foreach ($r in $camResults) { $sync.CamResults.Add($r) | Out-Null }
    $sync.StepsDone["CamPing"] = if ($mainPingCount -gt 0) { "pass" } else { "fail" }

    if ($mainPingCount -eq $mainTotal -and $mainTotal -gt 0) {
        Set-Card "PingCHU"   "Success" "ok";   Set-Card "ChuDetect" "Online"  "ok"
    } elseif ($mainPingCount -gt 0) {
        Set-Card "PingCHU"   "Partial" "warn"; Set-Card "ChuDetect" "Partial" "warn"
    } else {
        Set-Card "PingCHU"   "No Response" "fail"; Set-Card "ChuDetect" "Offline" "fail"
    }

    # ── Application log analysis ──────────────────────────────────────────────
    $sync.CurrentStep = "Analyzing Pixellot application logs..."
    Add-Section "App Log"
    Add-Log "-- Pixellot Application Log Analysis --" "Cyan"
    Add-Log ""
    $latestLog = $null
    foreach ($lp in $PixellotLogPaths) {
        if (Test-Path $lp) {
            $f = Get-ChildItem -Path $lp -Filter "CamerasTester_*.log" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($f) { $latestLog = $f; break }
        }
    }

    if ($latestLog) {
        $sync.AppLogTime = $latestLog.LastWriteTime
        Add-Log ("  Log file : {0}  ({1} KB  Modified: {2})" -f $latestLog.Name, [math]::Round($latestLog.Length/1KB,1), $latestLog.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")) "Info"
        $logContent = Get-Content -Path $latestLog.FullName -ErrorAction SilentlyContinue
        if ($logContent) {
            $failCounts = @{}; $successIPs = @{}; $models = @{}; $exitCodes = @{}
            $sessions = 0; $lastIp = $null
            foreach ($line in $logContent) {
                if ($line -match 'START NEW LOG SESSION') { $sessions++ }
                if ($line -match '\[rtsp://([\d.]+)/') { $lastIp = $Matches[1] }
                if ($line -match "Couldn't get response from camera\s+rtsp://([\d.]+)") {
                    $ip = $Matches[1]; $failCounts[$ip] = ($failCounts[$ip] -as [int]) + 1; $lastIp = $ip
                }
                if ($line -match 'Done Setting camera parameters' -and $lastIp) { $successIPs[$lastIp] = $true }
                if ($line -match 'Found modelName:\s*(\S+)' -and $lastIp) { $models[$lastIp] = $Matches[1].Trim() }
                if ($line -match 'Process exiting with result:\s*(\d+)' -and $lastIp) {
                    $c = [int]$Matches[1]
                    if ($c -ne 0 -or -not $exitCodes.ContainsKey($lastIp)) { $exitCodes[$lastIp] = $c }
                }
            }
            Add-Log ("  Sessions : {0}" -f $sessions) "Info"
            Add-Log ""
            $allIPs = (@($failCounts.Keys)+@($successIPs.Keys)+@($models.Keys)) | Sort-Object -Unique
            foreach ($ip in $allIPs) {
                $fails = $failCounts[$ip] -as [int]
                $model = if ($models[$ip]) { $models[$ip] } else { "Unknown" }
                $camDef  = $CameraIPs  | Where-Object { $_.IP -eq $ip } | Select-Object -First 1
                $connRes = $camResults | Where-Object { $_.IP -eq $ip } | Select-Object -First 1
                $optAbsent = $camDef -and $camDef.Optional -and $connRes -and (-not $connRes.Ping)
                Add-Log ("  Camera IP : {0}  Model: {1}" -f $ip, $model) "Info"
                if ($fails -gt 0 -and -not $optAbsent) {
                    $exitCode = $exitCodes[$ip]
                    $exitMsg  = if ($null -ne $exitCode) { switch ($exitCode) { 11 {"Camera not found / no response before timeout"} 12 {"Camera first connection problem"} default {"Exit code $exitCode"} } } else { "" }
                    Add-Log ("  Errors    : {0} 'Couldn't get response' failure(s) across {1} session(s)" -f $fails, $sessions) "Fail"
                    if ($exitMsg) { Add-Log ("  Exit Code : {0}  ({1})" -f $exitCode, $exitMsg) "Fail" }

                    $portMatch = $null
                    $arp = Get-NetNeighbor -IPAddress $ip -ErrorAction SilentlyContinue | Where-Object { $_.State -ne "Unreachable" } | Select-Object -First 1
                    if ($arp) { $portMatch = Get-NetAdapter -InterfaceIndex $arp.InterfaceIndex -ErrorAction SilentlyContinue }
                    if (-not $portMatch) {
                        $sub = ($ip -split '\.')[0..2] -join '.'
                        foreach ($n in $nicPorts) {
                            $idx  = (Get-NetAdapter -Name $n.Name).ifIndex
                            $addrs = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue
                            if ($addrs | Where-Object { $_.IPAddress -and (($_.IPAddress -split '\.')[0..2] -join '.') -eq $sub }) { $portMatch = Get-NetAdapter -Name $n.Name; break }
                        }
                    }
                    $portResult = if ($portMatch) { $portResults | Where-Object { $_.Name -eq $portMatch.Name } | Select-Object -First 1 } else { $null }
                    $unknownModel = ($model -eq "Unknown")
                    if ($portResult -and $portResult.Result -eq "FAIL") {
                        Add-Log "  [CONFIRM] NIC port DEGRADED - app failures corroborate physical fault." "Fail"
                        $sync.AppIssues.Add("$ip ($model): app failures + NIC degraded = CONFIRMED physical fault") | Out-Null
                        Add-Summary "App Log  $ip" "$fails failure(s)  NIC fault confirmed" "Fail"
                    } elseif ($portResult -and $portResult.Result -like "PASS*") {
                        Add-Log "  [NOTE]    Cable and NIC port are OK (1 Gbps confirmed) - physical layer is ruled out." "Warn"
                        if ($unknownModel) {
                            Add-Log "  [NOTE]    Camera model could not be read - the VPU is not completing the camera handshake." "Warn"
                        }
                        Add-Log "  [NOTE]    Possible causes: insufficient PoE power, camera firmware/config issue, or camera hardware fault." "Warn"
                        Add-Log "            Start with a PoE reset before assuming hardware failure." "Warn"
                        $sync.AppIssues.Add("$ip ($model): app failures but NIC OK - cable ruled out, investigate camera") | Out-Null
                        Add-Summary "App Log  $ip" "$fails failure(s)  cable ruled out" "Warn"
                    } else {
                        $sync.AppIssues.Add("$ip ($model): $fails app failure(s)") | Out-Null
                        Add-Summary "App Log  $ip" "$fails failure(s)" "Warn"
                    }
                } elseif ($optAbsent) {
                    Add-Log "  Status    : Expected - optional camera (OCR) not installed on this unit." "Gray"
                } else {
                    Add-Log "  Status    : Connected successfully - no application-level failures." "Pass"
                    Add-Summary "App Log  $ip" "No failures" "Pass"
                }
                Add-Log ""
            }
        }
    } else {
        Add-Log "  No CamerasTester log found in Pixellot log paths." "Gray"
        Add-Log ""
        Add-Summary "App Log" "No log file found" "Gray"
    }
    $sync.StepsDone["AppLog"] = "pass"

    # ── Build Next Steps ──────────────────────────────────────────────────────
    $failPorts    = @($portResults | Where-Object { $_.Result -eq "FAIL" })
    $forcedPorts  = @($portResults | Where-Object { $_.Result -eq "PASS (forced)" })
    $uncertainOcr = @($portResults | Where-Object { $_.Result -eq "PASS (OCR?)" })
    $rtspFaults   = @($camResults  | Where-Object { $_.Ping -and -not $_.Rtsp })
    $noPingMain   = @($camResults  | Where-Object { -not $_.Optional -and -not $_.Ping })
    # allClear only when every active fault category is empty; historical SmartSpeed events on
    # currently-passing ports are informational only and do not block all-clear
    $allClear = ($failPorts.Count -eq 0) -and ($forcedPorts.Count -eq 0) -and
                ($uncertainOcr.Count -eq 0) -and ($rtspFaults.Count -eq 0) -and
                ($sync.AppIssues.Count -eq 0) -and ($noPingMain.Count -eq 0)
    $sync.AllClear = $allClear

    if ($allClear) {
        $sync.NextSteps.Add(@{ H="All tests passed."; B="No action required. All NIC ports and cameras are healthy." }) | Out-Null
    } else {
        $s = 1
        foreach ($r in $failPorts) {
            $bNote = if ($r.Blinking) { " (intermittent link)" } else { "" }
            $sync.NextSteps.Add(@{
                H = "$s. Isolate Fault — $($r.Name)$bNote"
                B = "Use the Isolate tab to determine whether the fault is the cable, NIC port, or camera before replacing anything."
            }) | Out-Null
            $s++
        }
        foreach ($r in $forcedPorts) {
            $sync.NextSteps.Add(@{
                H = "$s. Replace cable on $($r.Name) — preventive"
                B = "This port was forced to 1 Gbps and is currently holding, but SmartSpeed history confirms the cable or termination is marginal. Replace the cable before the link degrades again."
            }) | Out-Null
            $s++
        }
        foreach ($r in $uncertainOcr) {
            $sync.NextSteps.Add(@{
                H = "$s. Verify $($r.Name) — OCR camera or new cable fault?"
                B = "This port is at 100 Mbps with no SmartSpeed history. On an established VPU this is an OCR (scoreboard) camera — no action needed. On a new or first-time installation a bad cable also produces no history. If this is a CHU port, use the Isolate tab to test the cable."
            }) | Out-Null
            $s++
        }
        foreach ($c in $rtspFaults) {
            $sync.NextSteps.Add(@{
                H = "$s. PoE reset $($c.IP)"
                B = "RTSP is stalled — reset PoE power in VPU Manager (Settings > Cameras), wait 2 min, then re-run."
            }) | Out-Null
            $s++
        }
        foreach ($c in $noPingMain) {
            $sync.NextSteps.Add(@{
                H = "$s. PoE reset $($c.IP)"
                B = "Reset PoE power in VPU Manager (Settings > Cameras), wait 2 min, then re-run. If still offline after 2 resets, check cable seating and power."
            }) | Out-Null
            $s++
        }
        foreach ($issue in $sync.AppIssues) {
            if ($issue -like "*cable ruled out*") {
                $ip = if ($issue -match '(\d+\.\d+\.\d+\.\d+)') { $Matches[1] } else { "camera" }
                $camLabel = ($CameraIPs | Where-Object { $_.IP -eq $ip } | Select-Object -First 1).Label
                $tag = if ($camLabel) { "$ip ($camLabel)" } else { $ip }
                $logNote = if ($sync.AppLogTime) {
                    " Log is from $($sync.AppLogTime.ToString('MM/dd HH:mm')) — if a cable was recently replaced, these failures may be stale; re-run after the VPU reconnects to confirm."
                } else { "" }
                $sync.NextSteps.Add(@{
                    H = "$s. Camera issue on $tag"
                    B = "Cable and NIC are healthy (1 Gbps).$logNote Reset PoE power in VPU Manager, wait 2 min, and re-run. If failures persist after 2 resets, the camera likely needs replacement."
                }) | Out-Null
                $s++
            }
        }
        $activePortIssues = $failPorts.Count + $forcedPorts.Count + $uncertainOcr.Count
        if ($activePortIssues -gt 0 -and ($rtspFaults.Count -gt 0 -or $noPingMain.Count -gt 0 -or $sync.AppIssues.Count -gt 0)) {
            $sync.NextSteps.Add(@{
                H = "$s. Re-run after each fix"
                B = "Fix one issue at a time and re-run the full diagnostic to confirm each fix before moving on."
            }) | Out-Null
        }
    }
    $sync.StepsDone["NextSteps"] = "pass"
    Add-Summary "─────────────────" "Complete" "Cyan"

    $sync.LastRunLine = if ($allClear) { "All tests passed - No issues detected" } else { "$($failPorts.Count) port fault(s) detected" }
    Add-Content -Path $OutputFile -Value "`nSTATUS: $(if ($allClear) { 'ALL_CLEAR' } else { 'ISSUES_FOUND' })" -ErrorAction SilentlyContinue
    Add-Content -Path $OutputFile -Value "Full results saved: $OutputFile" -ErrorAction SilentlyContinue
    $sync.CurrentStep = if ($allClear) { "All tests passed. No issues detected." } else { "Diagnostic complete. Review next steps in right panel." }
    $sync.Running = $false
    $sync.Complete = $true
}

# ---------- GUI Helper Functions --------------------------------------------
function New-SidebarButton {
    param([string]$Text, [int]$Y, [bool]$Active = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text; $btn.Size = New-Object System.Drawing.Size(205, 44)
    $btn.Location = New-Object System.Drawing.Point(7, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $ColNavHover
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btn.Padding = New-Object System.Windows.Forms.Padding(16,0,0,0)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Active) { $btn.BackColor = $ColNavActive; $btn.ForeColor = [System.Drawing.Color]::White }
    else         { $btn.BackColor = $ColSidebar;   $btn.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184) }
    return $btn
}

function New-StatusCard {
    param([string]$Title, [int]$X, [int]$Y, [string]$Icon = "", [string]$Sub = "", [int]$CardW=178, [int]$CardH=78)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($CardW, $CardH); $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.BackColor = $ColCard; $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $panel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $CardW, $CardH)), 8))
    $panel.Add_Paint(({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $e.Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
        if ($Icon) {
            $iFont  = New-Object System.Drawing.Font("Segoe MDL2 Assets", 26)
            $iBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 210, 222))
            $iStr   = [string]$Icon
            $iSz    = $e.Graphics.MeasureString($iStr, $iFont)
            $ix     = $CardW - [int]$iSz.Width  - 10
            $iy     = $CardH - [int]$iSz.Height - 6
            $e.Graphics.DrawString($iStr, $iFont, $iBrush, $ix, $iy)
            $iFont.Dispose(); $iBrush.Dispose()
        }
        $rr = New-Object System.Drawing.Rectangle(0, 0, $CardW - 1, $CardH - 1)
        $bp = [GfxHelper]::RoundedRect($rr, 8)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 218, 228), 1)
        $e.Graphics.DrawPath($pen, $bp)
        $pen.Dispose(); $bp.Dispose()
    }).GetNewClosure())

    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = $Title
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lbl.ForeColor = $ColMuted
    $lbl.Location = New-Object System.Drawing.Point(10, 10); $lbl.AutoSize = $true
    $panel.Controls.Add($lbl)

    $val = New-Object System.Windows.Forms.Label; $val.Text = "--"
    $val.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
    $val.ForeColor = $ColText; $val.Location = New-Object System.Drawing.Point(10, 26)
    $val.Size = New-Object System.Drawing.Size($CardW - 20, 28); $val.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($val)

    $subLbl = New-Object System.Windows.Forms.Label; $subLbl.Text = $Sub
    $subLbl.Font = New-Object System.Drawing.Font("Segoe UI", 7); $subLbl.ForeColor = $ColMuted
    $subLbl.Location = New-Object System.Drawing.Point(10, 57); $subLbl.Size = New-Object System.Drawing.Size($CardW - 20, 14)
    $subLbl.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($subLbl)

    $dot = New-Object System.Windows.Forms.Panel; $dot.Size = New-Object System.Drawing.Size(10, 10)
    $dot.Location = New-Object System.Drawing.Point($CardW - 18, 10); $dot.BackColor = $ColMuted
    $dot.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 10, 10)), 5))
    $panel.Controls.Add($dot)

    return @{ Panel=$panel; ValueLabel=$val; DotPanel=$dot; SubLabel=$subLbl }
}

function Update-CardStatus {
    param($Card, [string]$Value, [string]$Status)
    $Card.ValueLabel.Text = $Value
    $Card.ValueLabel.Font = if ($Value.Length -gt 9) {
        New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    } else {
        New-Object System.Drawing.Font("Segoe UI Semibold", 13)
    }
    $dotC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColMuted} }
    $valC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColText}  }
    $Card.DotPanel.BackColor   = $dotC
    $Card.ValueLabel.ForeColor = $valC
}

# ---------- Form ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "VPU Cable & NIC Troubleshooter  v$ScriptVersion"
$form.ClientSize = New-Object System.Drawing.Size(1280, 760)
$form.MinimumSize = $form.Size
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $ColBg
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Anchor shorthands — used to make panels resize correctly when maximized
$AnchorTLRB = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTLR  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorTLB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTRB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorBLR  = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorBL   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$AnchorTR   = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right

# ---- Header Bar ------------------------------------------------------------
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Size = New-Object System.Drawing.Size(1280, 68)
$pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
$pnlHeader.BackColor = $ColSidebar
$pnlHeader.Anchor = $AnchorTLR
$form.Controls.Add($pnlHeader)

$lblHdrIcon = New-Object System.Windows.Forms.Label
$lblHdrIcon.Text = [char]0xF785
$lblHdrIcon.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 26)
$lblHdrIcon.ForeColor = $ColAccent
$lblHdrIcon.Location = New-Object System.Drawing.Point(14, 8); $lblHdrIcon.Size = New-Object System.Drawing.Size(52, 52)
$pnlHeader.Controls.Add($lblHdrIcon)

$lblHdrTitle = New-Object System.Windows.Forms.Label
$lblHdrTitle.Text = "VPU Cable & NIC Troubleshooter"
$lblHdrTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
$lblHdrTitle.ForeColor = [System.Drawing.Color]::White
$lblHdrTitle.Location = New-Object System.Drawing.Point(68, 10); $lblHdrTitle.Size = New-Object System.Drawing.Size(700, 28)
$pnlHeader.Controls.Add($lblHdrTitle)

$lblHdrSub = New-Object System.Windows.Forms.Label
$lblHdrSub.Text = "Diagnose cable, NIC, CHU, and camera port issues"
$lblHdrSub.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblHdrSub.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblHdrSub.Location = New-Object System.Drawing.Point(70, 40); $lblHdrSub.Size = New-Object System.Drawing.Size(520, 18)
$pnlHeader.Controls.Add($lblHdrSub)

# Status badge — lives in the header bar
$pnlBadge = New-Object System.Windows.Forms.Panel
$pnlBadge.Size = New-Object System.Drawing.Size(110, 30); $pnlBadge.Location = New-Object System.Drawing.Point(1150, 19)
$pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
$pnlBadge.Anchor = $AnchorTR
$pnlHeader.Controls.Add($pnlBadge)
$pnlBadge.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 30)), 15))

$pnlBadgeDot = New-Object System.Windows.Forms.Panel
$pnlBadgeDot.Size = New-Object System.Drawing.Size(8, 8); $pnlBadgeDot.Location = New-Object System.Drawing.Point(12, 11)
$pnlBadgeDot.BackColor = $ColGreen
$pnlBadgeDot.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
$pnlBadge.Controls.Add($pnlBadgeDot)

$lblBadge = New-Object System.Windows.Forms.Label; $lblBadge.Text = "Ready"
$lblBadge.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9); $lblBadge.ForeColor = $ColGreen
$lblBadge.Location = New-Object System.Drawing.Point(24, 0); $lblBadge.Size = New-Object System.Drawing.Size(80, 30)
$lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlBadge.Controls.Add($lblBadge)

$sepHdr = New-Object System.Windows.Forms.Panel; $sepHdr.Size = New-Object System.Drawing.Size(1280, 1)
$sepHdr.Location = New-Object System.Drawing.Point(0, 67); $sepHdr.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sepHdr.Anchor = $AnchorTLR
$pnlHeader.Controls.Add($sepHdr)

# ---- Left Sidebar ----------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Size = New-Object System.Drawing.Size(220, 692); $sidebar.Location = New-Object System.Drawing.Point(0, 68)
$sidebar.BackColor = $ColSidebar; $sidebar.Anchor = $AnchorTLB; $form.Controls.Add($sidebar)

$sep1 = New-Object System.Windows.Forms.Panel; $sep1.Size = New-Object System.Drawing.Size(196, 1)
$sep1.Location = New-Object System.Drawing.Point(12, 2); $sep1.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sidebar.Controls.Add($sep1)

$navOverview = New-SidebarButton ([char]0x2302 + "  Overview") 8   $true
$navTests    = New-SidebarButton ([char]0x2630 + "  Isolate")  54
$navHistory  = New-SidebarButton ([char]0x25F7 + "  History")  100
$navHelp     = New-SidebarButton ([char]0x003F + "  Help")     146
$sidebar.Controls.AddRange(@($navOverview, $navTests, $navHistory, $navHelp))

$sep2 = New-Object System.Windows.Forms.Panel; $sep2.Size = New-Object System.Drawing.Size(196, 1)
$sep2.Location = New-Object System.Drawing.Point(12, 198); $sep2.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sidebar.Controls.Add($sep2)

$lblNicHdr = New-Object System.Windows.Forms.Label; $lblNicHdr.Text = "Test Scope"
$lblNicHdr.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lblNicHdr.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblNicHdr.Location = New-Object System.Drawing.Point(12, 208); $lblNicHdr.AutoSize = $true
$sidebar.Controls.Add($lblNicHdr)

$cboNic = New-Object System.Windows.Forms.ComboBox
$cboNic.Size = New-Object System.Drawing.Size(196, 22); $cboNic.Location = New-Object System.Drawing.Point(12, 224)
$cboNic.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboNic.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85); $cboNic.ForeColor = [System.Drawing.Color]::White
$cboNic.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$sidebar.Controls.Add($cboNic)

$pnlConnDot = New-Object System.Windows.Forms.Panel
$pnlConnDot.Size = New-Object System.Drawing.Size(8, 8); $pnlConnDot.Location = New-Object System.Drawing.Point(12, 252)
$pnlConnDot.BackColor = $ColGreen
$pnlConnDot.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
$sidebar.Controls.Add($pnlConnDot)

$lblConnStatus = New-Object System.Windows.Forms.Label; $lblConnStatus.Text = "Connected"
$lblConnStatus.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lblConnStatus.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblConnStatus.Location = New-Object System.Drawing.Point(24, 249); $lblConnStatus.AutoSize = $true
$sidebar.Controls.Add($lblConnStatus)

$sep3 = New-Object System.Windows.Forms.Panel; $sep3.Size = New-Object System.Drawing.Size(196, 1)
$sep3.Location = New-Object System.Drawing.Point(12, 268); $sep3.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sidebar.Controls.Add($sep3)

$lblQiHdr = New-Object System.Windows.Forms.Label; $lblQiHdr.Text = "Quick Info"
$lblQiHdr.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lblQiHdr.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblQiHdr.Location = New-Object System.Drawing.Point(12, 278); $lblQiHdr.AutoSize = $true
$sidebar.Controls.Add($lblQiHdr)

$lblQiOs   = New-Object System.Windows.Forms.Label; $lblQiOs.Text   = "OS: Windows"
$lblQiVpu  = New-Object System.Windows.Forms.Label; $lblQiVpu.Text  = "VPU: $($env:COMPUTERNAME)"
$lblQiUser = New-Object System.Windows.Forms.Label; $lblQiUser.Text = "User: $($env:USERNAME)"
foreach ($pair in @(($lblQiOs, 294), ($lblQiVpu, 312), ($lblQiUser, 330))) {
    $pair[0].Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $pair[0].ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
    $pair[0].Location = New-Object System.Drawing.Point(12, $pair[1]); $pair[0].Size = New-Object System.Drawing.Size(196, 18)
    $sidebar.Controls.Add($pair[0])
}

$sep4 = New-Object System.Windows.Forms.Panel; $sep4.Size = New-Object System.Drawing.Size(196, 1)
$sep4.Location = New-Object System.Drawing.Point(12, 356); $sep4.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sidebar.Controls.Add($sep4)

$lblVpuHdr = New-Object System.Windows.Forms.Label; $lblVpuHdr.Text = "VPU Model"
$lblVpuHdr.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lblVpuHdr.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblVpuHdr.Location = New-Object System.Drawing.Point(12, 366); $lblVpuHdr.AutoSize = $true
$sidebar.Controls.Add($lblVpuHdr)

$lblVpuVal = New-Object System.Windows.Forms.Label; $lblVpuVal.Text = "Detecting..."
$lblVpuVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblVpuVal.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblVpuVal.Location = New-Object System.Drawing.Point(12, 382); $lblVpuVal.Size = New-Object System.Drawing.Size(196, 46)
$sidebar.Controls.Add($lblVpuVal)

$lblUpdate = New-Object System.Windows.Forms.Label; $lblUpdate.Text = ""
$lblUpdate.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lblUpdate.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
$lblUpdate.Location = New-Object System.Drawing.Point(12, 436); $lblUpdate.Size = New-Object System.Drawing.Size(196, 52)
$lblUpdate.Visible = $false
$sidebar.Controls.Add($lblUpdate)

# ---- Center Panel ----------------------------------------------------------
$center = New-Object System.Windows.Forms.Panel
$center.Size = New-Object System.Drawing.Size(800, 692); $center.Location = New-Object System.Drawing.Point(220, 68)
$center.BackColor = $ColBg; $center.Anchor = $AnchorTLRB; $form.Controls.Add($center)

$btnRun = New-Object System.Windows.Forms.Button; $btnRun.Text = [char]0x25B6 + "  Run Full Diagnostic"
$btnRun.Size = New-Object System.Drawing.Size(290, 44); $btnRun.Location = New-Object System.Drawing.Point(10, 12)
$btnRun.BackColor = $ColAccent; $btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRun.FlatAppearance.BorderSize = 0
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$btnRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$center.Controls.Add($btnRun)
$btnRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 290, 44)), 7))

$btnRetest = New-Object System.Windows.Forms.Button; $btnRetest.Text = "Retest Last Step"
$btnRetest.Size = New-Object System.Drawing.Size(174, 44); $btnRetest.Location = New-Object System.Drawing.Point(308, 12)
$btnRetest.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240); $btnRetest.ForeColor = $ColText
$btnRetest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRetest.FlatAppearance.BorderSize = 0
$btnRetest.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnRetest.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnRetest.Enabled = $false
$center.Controls.Add($btnRetest)
$btnRetest.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 174, 44)), 7))

$btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "Cancel"
$btnCancel.Size = New-Object System.Drawing.Size(128, 44); $btnCancel.Location = New-Object System.Drawing.Point(490, 12)
$btnCancel.BackColor = $ColRed; $btnCancel.ForeColor = [System.Drawing.Color]::White
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnCancel.FlatAppearance.BorderSize = 0
$btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnCancel.Visible = $false
$center.Controls.Add($btnCancel)
$btnCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 128, 44)), 7))

$lblRunSteps = New-Object System.Windows.Forms.Label
$lblRunSteps.Text = "Runs: Port Speed  •  Ping  •  ARP  •  CHU Detection"
$lblRunSteps.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRunSteps.ForeColor = $ColMuted
$lblRunSteps.Location = New-Object System.Drawing.Point(10, 62); $lblRunSteps.Size = New-Object System.Drawing.Size(760, 18)
$center.Controls.Add($lblRunSteps)

$lblCurStat = New-Object System.Windows.Forms.Label; $lblCurStat.Text = "Current Results"
$lblCurStat.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblCurStat.ForeColor = $ColText
$lblCurStat.Location = New-Object System.Drawing.Point(10, 88); $lblCurStat.AutoSize = $true
$center.Controls.Add($lblCurStat)

$lnkClear = New-Object System.Windows.Forms.LinkLabel; $lnkClear.Text = "Clear"
$lnkClear.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lnkClear.LinkColor = $ColMuted
$lnkClear.Location = New-Object System.Drawing.Point(762, 90); $lnkClear.AutoSize = $true
$center.Controls.Add($lnkClear)

# Fixed bottom-row cards: SmartSpeed, Ping, ARP, CHU  (187px each, 10px gaps)
$cardDefs = @(
    @{Key="SmartSpeed"; Title="SmartSpeed";    Sub="Intel events (48h)"; X=10;  Y=204; Icon=[char]0xE7BA; W=187}
    @{Key="PingCHU";    Title="Ping (CHU)";    Sub="Camera head unit";   X=207; Y=204; Icon=[char]0xE701; W=187}
    @{Key="ArpEntry";   Title="ARP Entry";     Sub="L2 neighbor table";  X=404; Y=204; Icon=[char]0xE9D5; W=187}
    @{Key="ChuDetect";  Title="CHU Detection"; Sub="Camera response";    X=601; Y=204; Icon=[char]0xE722; W=187}
)
$cards = @{}
foreach ($cd in $cardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y $cd.Y -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $cards[$cd.Key] = $c
    $center.Controls.Add($c.Panel)
}

# Dynamic top-row cards: one per camera NIC, ordered by physical PCI port position
$script:detectedNics = @(Get-NetAdapter | Where-Object {
    $d = $_.InterfaceDescription
    ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
} | Sort-Object {
    try { (Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction Stop).Function } catch { 999 }
}, Name)

if ($script:detectedNics.Count -gt 0) {
    $numPorts  = $script:detectedNics.Count
    $portCardW = [int]((780 - ($numPorts - 1) * 10) / $numPorts)
    $portCardX = 10; $portNum = 1
    foreach ($n in $script:detectedNics) {
        $c = New-StatusCard -Title "P$portNum" -Sub $n.Name -X $portCardX -Y 106 -CardW $portCardW -CardH 90
        $cards[$n.Name] = $c
        $sync.Cards[$n.Name] = @{ Value = "--"; Status = "neutral" }
        $center.Controls.Add($c.Panel)
        # Click a degraded port card → jump to Guide with that port pre-selected
        $capturedName = $n.Name
        $portClickHandler = {
            $pr = $sync.PortResults | Where-Object { $_.Name -eq $capturedName -and $_.Result -eq "FAIL" } | Select-Object -First 1
            if ($pr) { $navTests.PerformClick(); Reset-Guide; $idx = $cboGuidePortA.Items.IndexOf($capturedName); if ($idx -ge 0) { $cboGuidePortA.SelectedIndex = $idx } }
        }.GetNewClosure()
        $c.Panel.Add_Click($portClickHandler)
        $c.ValueLabel.Add_Click($portClickHandler)
        $c.Panel.Cursor = [System.Windows.Forms.Cursors]::Hand
        $portCardX += $portCardW + 10; $portNum++
    }
}

$pnlSummaryCard = New-Object System.Windows.Forms.Panel
$pnlSummaryCard.Size = New-Object System.Drawing.Size(780, 56); $pnlSummaryCard.Location = New-Object System.Drawing.Point(10, 304)
$pnlSummaryCard.BackColor = [System.Drawing.Color]::White
$pnlSummaryCard.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 780, 56)), 8))
$pnlSummaryCard.Add_Paint({
    param($s, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rr  = New-Object System.Drawing.Rectangle(0, 0, 779, 55)
    $bp  = [GfxHelper]::RoundedRect($rr, 8)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 218, 228), 1)
    $e.Graphics.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
})
$center.Controls.Add($pnlSummaryCard)

$lblLastRun = New-Object System.Windows.Forms.Label; $lblLastRun.Text = "Last Run Summary"
$lblLastRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $lblLastRun.ForeColor = $ColText
$lblLastRun.BackColor = [System.Drawing.Color]::White
$lblLastRun.Location = New-Object System.Drawing.Point(14, 7); $lblLastRun.AutoSize = $true
$pnlSummaryCard.Controls.Add($lblLastRun)

$lblLastRunVal = New-Object System.Windows.Forms.Label; $lblLastRunVal.Text = "No runs yet"
$lblLastRunVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblLastRunVal.ForeColor = $ColMuted
$lblLastRunVal.BackColor = [System.Drawing.Color]::White
$lblLastRunVal.Location = New-Object System.Drawing.Point(14, 28); $lblLastRunVal.Size = New-Object System.Drawing.Size(750, 18)
$pnlSummaryCard.Controls.Add($lblLastRunVal)

$lblLogHdr = New-Object System.Windows.Forms.Label; $lblLogHdr.Text = "Live Log"
$lblLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblLogHdr.ForeColor = $ColText
$lblLogHdr.Location = New-Object System.Drawing.Point(10, 370); $lblLogHdr.AutoSize = $true
$center.Controls.Add($lblLogHdr)

$lblStatus = New-Object System.Windows.Forms.Label; $lblStatus.Text = ""
$lblStatus.Font = New-Object System.Drawing.Font("Consolas", 8); $lblStatus.ForeColor = $ColMuted
$lblStatus.Location = New-Object System.Drawing.Point(10, 392); $lblStatus.Size = New-Object System.Drawing.Size(780, 18)
$center.Controls.Add($lblStatus)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Size = New-Object System.Drawing.Size(780, 288); $rtbLog.Location = New-Object System.Drawing.Point(10, 412)
$rtbLog.BackColor = $ColLogBg; $rtbLog.ForeColor = [System.Drawing.Color]::FromArgb(203, 213, 225)
$rtbLog.Font = New-Object System.Drawing.Font("Consolas", 8); $rtbLog.ReadOnly = $true
$rtbLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbLog.Anchor = $AnchorTLRB
$center.Controls.Add($rtbLog)

# ---- Right Panel -----------------------------------------------------------
$rightBorder = New-Object System.Windows.Forms.Panel; $rightBorder.Size = New-Object System.Drawing.Size(1, 692)
$rightBorder.Location = New-Object System.Drawing.Point(1020, 68); $rightBorder.BackColor = $ColBorder
$rightBorder.Anchor = $AnchorTRB
$form.Controls.Add($rightBorder)

$right = New-Object System.Windows.Forms.Panel
$right.Size = New-Object System.Drawing.Size(259, 692); $right.Location = New-Object System.Drawing.Point(1021, 68)
$right.BackColor = [System.Drawing.Color]::White; $right.Anchor = $AnchorTRB; $form.Controls.Add($right)

# Blue "Next Steps / Guidance" header bar
$pnlNextHdr = New-Object System.Windows.Forms.Panel
$pnlNextHdr.Size = New-Object System.Drawing.Size(259, 36); $pnlNextHdr.Location = New-Object System.Drawing.Point(0, 0)
$pnlNextHdr.BackColor = $ColAccent
$right.Controls.Add($pnlNextHdr)
$lblNextHdr = New-Object System.Windows.Forms.Label; $lblNextHdr.Text = "Next Steps / Guidance"
$lblNextHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $lblNextHdr.ForeColor = [System.Drawing.Color]::White
$lblNextHdr.Location = New-Object System.Drawing.Point(12, 8); $lblNextHdr.AutoSize = $true
$pnlNextHdr.Controls.Add($lblNextHdr)

$rtbSteps = New-Object System.Windows.Forms.RichTextBox
$rtbSteps.Size = New-Object System.Drawing.Size(239, 408); $rtbSteps.Location = New-Object System.Drawing.Point(10, 44); $rtbSteps.Anchor = $AnchorTLRB
$rtbSteps.BackColor = [System.Drawing.Color]::White; $rtbSteps.ForeColor = $ColText
$rtbSteps.Font = New-Object System.Drawing.Font("Segoe UI", 9); $rtbSteps.ReadOnly = $true
$rtbSteps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbSteps.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbSteps.Text = "Run the diagnostic to`nsee guidance here."
$right.Controls.Add($rtbSteps)

$btnGoGuide = New-Object System.Windows.Forms.Button
$btnGoGuide.Text = "Open Fault Isolator  →"
$btnGoGuide.Size = New-Object System.Drawing.Size(239, 34); $btnGoGuide.Location = New-Object System.Drawing.Point(10, 460)
$btnGoGuide.BackColor = $ColAccent; $btnGoGuide.ForeColor = [System.Drawing.Color]::White
$btnGoGuide.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGoGuide.FlatAppearance.BorderSize = 0
$btnGoGuide.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnGoGuide.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnGoGuide.Visible = $false
$right.Controls.Add($btnGoGuide)
$btnGoGuide.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 239, 34)), 6))

$sepAct = New-Object System.Windows.Forms.Panel; $sepAct.Size = New-Object System.Drawing.Size(239, 1)
$sepAct.Location = New-Object System.Drawing.Point(10, 502); $sepAct.BackColor = $ColBorder
$sepAct.Anchor = $AnchorBLR
$right.Controls.Add($sepAct)

$lblActHdr = New-Object System.Windows.Forms.Label; $lblActHdr.Text = "Actions"
$lblActHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblActHdr.ForeColor = $ColText
$lblActHdr.Location = New-Object System.Drawing.Point(10, 510); $lblActHdr.AutoSize = $true
$lblActHdr.Anchor = $AnchorBL
$right.Controls.Add($lblActHdr)

foreach ($pair in @(("btnExport","Export Report",532),("btnCopySummary","Copy Summary",564),("btnCopy","Copy Log",596),("btnSave","Save Log",628))) {
    $b = New-Object System.Windows.Forms.Button; $b.Text = $pair[1]
    $b.Size = New-Object System.Drawing.Size(239, 28); $b.Location = New-Object System.Drawing.Point(10, $pair[2])
    $b.Anchor = $AnchorBLR
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $ColBorder; $b.FlatAppearance.BorderSize = 1
    $b.BackColor = [System.Drawing.Color]::White; $b.ForeColor = $ColText
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $right.Controls.Add($b)
    $b.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 239, 28)), 5))
    Set-Variable -Name $pair[0] -Value $b
}

# ---------- Timer (polls $sync every 300ms, updates UI) ---------------------
$script:runspace = $null
$script:spinIdx  = 0

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    $item = $null
    while ($sync.SummaryQueue.TryDequeue([ref]$item)) {
        if ($item.L -eq "Section") {
            $rtbLog.SelectionStart = $rtbLog.TextLength; $rtbLog.SelectionLength = 0
            $rtbLog.SelectionFont  = New-Object System.Drawing.Font("Consolas", 7.5, [System.Drawing.FontStyle]::Bold)
            $rtbLog.SelectionColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
            $rtbLog.AppendText("`n  $($item.Result.ToUpper())`n")
            $rtbLog.ScrollToCaret()
            continue
        }
        $rtbLog.SelectionStart = $rtbLog.TextLength; $rtbLog.SelectionLength = 0
        $rtbLog.SelectionColor = [System.Drawing.Color]::FromArgb(100,116,139)
        $rtbLog.SelectionFont  = New-Object System.Drawing.Font("Consolas",8)
        $rtbLog.AppendText(("{0,-24}" -f $item.Label))
        $rtbLog.SelectionStart = $rtbLog.TextLength; $rtbLog.SelectionLength = 0
        $col = switch ($item.L) {
            "Pass" { [System.Drawing.Color]::FromArgb(74,222,128) }
            "Fail" { [System.Drawing.Color]::FromArgb(252,165,165) }
            "Warn" { [System.Drawing.Color]::FromArgb(253,224,71)  }
            "Cyan" { [System.Drawing.Color]::FromArgb(103,232,249) }
            "Gray" { [System.Drawing.Color]::FromArgb(100,116,139) }
            default{ [System.Drawing.Color]::FromArgb(203,213,225) }
        }
        $rtbLog.SelectionColor = $col
        $rtbLog.SelectionFont  = New-Object System.Drawing.Font("Consolas",8)
        $rtbLog.AppendText("$($item.Result)`n")
        $rtbLog.ScrollToCaret()
    }

    foreach ($key in $cards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $cards[$key].ValueLabel.Text -ne $sc.Value) {
            Update-CardStatus -Card $cards[$key] -Value $sc.Value -Status $sc.Status
        }
    }

    $spinChars = @('|','/','-','\')
    if ($sync.Running) {
        $script:spinIdx = ($script:spinIdx + 1) % 4
        $sc = $spinChars[$script:spinIdx]
        $lblStatus.ForeColor = $ColAccent
        $lblStatus.Text = " $sc  $($sync.CurrentStep)"
    } elseif ($sync.Complete -and $lblStatus.ForeColor -ne $ColMuted) {
        $lblStatus.ForeColor = $ColMuted
        $lblStatus.Text = "  $($sync.CurrentStep)"
    }
    if ($sync.VpuModel   -and $lblVpuVal.Text -ne $sync.VpuModel)   { $lblVpuVal.Text = $sync.VpuModel }

    if ($sync.Running) {
        $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(219,234,254)
        $lblBadge.ForeColor = $ColAccent; $lblBadge.Text = "Running"
        $pnlBadgeDot.BackColor = $ColAccent
        if (-not $btnCancel.Visible) { $btnCancel.Visible = $true }
    }

    if ($sync.UpdateAvailable -and -not $lblUpdate.Visible) {
        $lblUpdate.Text = "Update available: v$($sync.UpdateAvailable)`nRe-run the one-liner to update."
        $lblUpdate.Visible = $true
    }

    if ($sync.Complete -and -not $sync.Running) {
        $timer.Stop()
        $btnCancel.Visible = $false
        $btnRun.Enabled = $true
        $btnRun.Text = if ($cboNic.SelectedIndex -le 0) {
            [char]0x25B6 + "  Run Full Diagnostic"
        } else {
            $n = ($cboNic.SelectedItem -as [string]) -replace '\s+\(.*', ''
            [char]0x25B6 + "  Test $n Only"
        }
        $btnRetest.Enabled = $true

        if ($sync.AllClear) {
            $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(220,252,231)
            $lblBadge.ForeColor = $ColGreen; $lblBadge.Text = "All Clear"
            $pnlBadgeDot.BackColor = $ColGreen
        } else {
            $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(254,226,226)
            $lblBadge.ForeColor = $ColRed; $lblBadge.Text = "Issues Found"
            $pnlBadgeDot.BackColor = $ColRed
        }

        Show-OverviewSteps

        $dt = Get-Date -Format "yyyy-MM-dd HH:mm"
        $trend = Get-PortTrendSummary
        $trendSuffix = if ($trend) { "   ·   $trend" } else { "" }
        $lblLastRunVal.Text = "$($sync.LastRunLine)   $dt$trendSuffix"
        $btnGoGuide.Visible = ((@($sync.PortResults) | Where-Object { $_.Result -eq "FAIL" }).Count -gt 0)
    }
})

# ---------- Button Handlers -------------------------------------------------
$btnRun.Add_Click({
    if ($sync.Running) { return }

    # Prune log folder — keep the 49 most recent files (new run will be the 50th)
    try {
        $pruneFiles = @(Get-ChildItem -Path $OutputDir -Filter "CameraLink_Results_*.txt" -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -Skip 49)
        $pruneFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }

    $newRunId  = Get-Date -Format "yyyyMMdd_HHmmss"
    $newOutput = Join-Path $OutputDir "CameraLink_Results_$newRunId.txt"
    $sync.Running = $false; $sync.Complete = $false; $sync.AllClear = $false
    $sync.PortResults.Clear(); $sync.CamResults.Clear()
    $sync.AppIssues.Clear();   $sync.NextSteps.Clear()
    $sync.TotalDowngrades = 0; $sync.LastRunLine = ""; $sync.VpuModel = ""
    $sync.Cancelled = $false; $sync.CurrentStep = "Starting..."
    $sync.OutputFile = $newOutput; $sync.RunId = $newRunId
    foreach ($k in $cards.Keys) { $sync.Cards[$k] = @{ Value="--"; Status="neutral" } }
    $sync.StepsDone.Clear()
    $item2 = $null; while ($sync.SummaryQueue.TryDequeue([ref]$item2)) { }

    $rtbLog.Clear(); $rtbSteps.Text = "Diagnostic running..."; $btnGoGuide.Visible = $false
    $btnRun.Enabled = $false; $btnRun.Text = "  Running..."
    $btnRetest.Enabled = $false
    $script:spinIdx = 0; $lblStatus.ForeColor = $ColAccent; $lblStatus.Text = " |  Starting..."

    if ($script:runspace) { try { $script:runspace.Close() } catch { } }
    $script:runspace = [runspacefactory]::CreateRunspace()
    $script:runspace.ApartmentState = "STA"
    $script:runspace.ThreadOptions  = "ReuseThread"
    $script:runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $script:runspace
    $ps.AddScript($DiagScript) | Out-Null
    $filterNicVal = if ($cboNic.SelectedIndex -gt 0) { ($cboNic.SelectedItem -as [string]) -replace '\s+\(.*', '' } else { "" }
    $ps.AddParameters(@{
        sync               = $sync
        NicDriverPatterns  = $NicDriverPatterns
        RenegotiateWaitSec = $RenegotiateWaitSec
        EventLogHours      = $EventLogHours
        PixellotLogPaths   = $PixellotLogPaths
        CameraIPs          = $CameraIPs
        RtspPort           = $RtspPort
        OutputFile         = $newOutput
        RunId              = $newRunId
        ScriptVersion      = $ScriptVersion
        OcrMacOui          = $OcrMacOui
        FilterNic          = $filterNicVal
    }) | Out-Null
    $ps.BeginInvoke() | Out-Null
    $timer.Start()
})

$btnRetest.Add_Click({ $btnRun.PerformClick() })

$btnCancel.Add_Click({
    $sync.Cancelled = $true
    $btnCancel.Visible = $false
})

$cboNic.Add_SelectedIndexChanged({
    if (-not $sync.Running) {
        if ($cboNic.SelectedIndex -le 0) {
            $btnRun.Text = [char]0x25B6 + "  Run Full Diagnostic"
            $lblRunSteps.Text = "Runs: Port Speed  •  Ping  •  ARP  •  CHU Detection"
        } else {
            $nicName = ($cboNic.SelectedItem -as [string]) -replace '\s+\(.*', ''
            $btnRun.Text = [char]0x25B6 + "  Test $nicName Only"
            $lblRunSteps.Text = "Scope: $nicName only  •  Port Speed  •  Ping  •  ARP  •  CHU Detection"
        }
    }
})

$btnExport.Add_Click({
    if ($sync.OutputFile -and (Test-Path $sync.OutputFile)) {
        Start-Process notepad.exe $sync.OutputFile
    } else {
        [System.Windows.Forms.MessageBox]::Show("Run the diagnostic first.", "Export Report", "OK", "Information") | Out-Null
    }
})

$btnCopySummary.Add_Click({
    if (-not $sync.Complete) {
        [System.Windows.Forms.MessageBox]::Show("Run the diagnostic first.", "Copy Summary", "OK", "Information") | Out-Null
        return
    }
    $lines = @()
    $lines += "═" * 48
    $lines += "VPU DIAGNOSTIC SUMMARY"
    $lines += "Date:       $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $lines += "Computer:   $($env:COMPUTERNAME)"
    $lines += "VPU Model:  $($sync.VpuModel)"
    $lines += "Run ID:     $($sync.RunId)"
    $lines += ""
    $lines += "RESULT: $(if ($sync.AllClear) { 'ALL CLEAR' } else { 'ISSUES FOUND' })"
    $lines += "═" * 48
    $lines += ""
    $lines += "PORT STATUS"
    foreach ($r in @($sync.PortResults)) {
        $status = switch ($r.Result) {
            "PASS"          { "1 Gbps — OK" }
            "PASS (forced)" { "1 Gbps — OK (forced)" }
            "PASS (OCR)"    { "100 Mbps — OCR camera (expected)" }
            "FAIL"          { "DEGRADED — physical layer fault" }
            "NO LINK"       { "No link" }
            default         { $r.Result }
        }
        $lines += "  $($r.Name.PadRight(16)) $status"
    }
    $lines += ""
    $lines += "SIGNAL QUALITY"
    $ssLine = if ($sync.TotalDowngrades -gt 0) { "$($sync.TotalDowngrades) SmartSpeed downgrade event(s) in 48h — physical layer fault confirmed" } else { "No SmartSpeed downgrade events" }
    $lines += "  $ssLine"
    $lines += ""
    $lines += "CAMERA CONNECTIVITY"
    foreach ($c in @($sync.CamResults)) {
        $cs = if ($c.Ping -and $c.Rtsp) { "Ping OK / RTSP OK" } elseif ($c.Ping) { "Ping OK / RTSP FAIL" } elseif ($c.Optional) { "Not installed (optional)" } else { "No response" }
        $lines += "  $($c.IP.PadRight(18)) $($c.Label) — $cs"
    }
    if ($sync.AppIssues.Count -gt 0) {
        $lines += ""
        $lines += "APPLICATION LOG FINDINGS"
        foreach ($issue in @($sync.AppIssues)) { $lines += "  $issue" }
    }
    $lines += ""
    $lines += "NEXT STEPS"
    foreach ($step in @($sync.NextSteps)) { $lines += "  - $($step.H)" }
    $lines += ""
    if ($sync.OutputFile) { $lines += "Full report: $(Split-Path $sync.OutputFile -Leaf)" }
    $lines += "═" * 48
    [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
    [System.Windows.Forms.MessageBox]::Show("Summary copied to clipboard. Paste into your ticket or support chat.", "Copy Summary", "OK", "Information") | Out-Null
})

$btnCopy.Add_Click({
    if ($rtbLog.TextLength -gt 0) {
        [System.Windows.Forms.Clipboard]::SetText($rtbLog.Text)
        [System.Windows.Forms.MessageBox]::Show("Log copied to clipboard.", "Copy Log", "OK", "Information") | Out-Null
    }
})

$btnSave.Add_Click({
    if ($sync.OutputFile -and (Test-Path $sync.OutputFile)) {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
        $dlg.FileName = [System.IO.Path]::GetFileName($sync.OutputFile)
        if ($dlg.ShowDialog() -eq "OK") {
            Copy-Item $sync.OutputFile $dlg.FileName -Force
            [System.Windows.Forms.MessageBox]::Show("Saved to $($dlg.FileName)", "Save Log", "OK", "Information") | Out-Null
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Run the diagnostic first.", "Save Log", "OK", "Information") | Out-Null
    }
})

$lnkClear.Add_LinkClicked({
    $rtbLog.Clear()
    foreach ($k in $cards.Keys) { Update-CardStatus -Card $cards[$k] -Value "--" -Status "neutral" }
    $lblLastRunVal.Text = "No runs yet"
})

# ---------- Helper functions ------------------------------------------------
function Get-PortTrendSummary {
    $files = @(Get-ChildItem -Path $OutputDir -Filter "CameraLink_Results_*.txt" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 15)
    if ($files.Count -lt 3) { return $null }
    $portCounts = @{}
    foreach ($f in $files) {
        try {
            $lines = Get-Content -Path $f.FullName -ErrorAction Stop
            @($lines | Where-Object { $_ -match 'DEGRADED' }) | ForEach-Object {
                if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $p = $Matches[1].Trim(); $portCounts[$p] = ($portCounts[$p] -as [int]) + 1 }
            }
        } catch { }
    }
    if ($portCounts.Count -eq 0) { return $null }
    $top = $portCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
    return "$($top.Key) has had issues in $($top.Value) of the last $($files.Count) runs"
}

function Show-OverviewSteps {
    $rtbSteps.Clear()
    if ($sync.NextSteps.Count -eq 0) { $rtbSteps.Text = "Run the diagnostic to`nsee guidance here."; return }
    $first = $true
    foreach ($step in @($sync.NextSteps)) {
        if (-not $first) {
            $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
            $rtbSteps.SelectionFont = New-Object System.Drawing.Font("Segoe UI",4)
            $rtbSteps.SelectionColor = [System.Drawing.Color]::White; $rtbSteps.AppendText("`n")
        }
        $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
        $rtbSteps.SelectionFont = New-Object System.Drawing.Font("Segoe UI Semibold",9)
        $rtbSteps.SelectionColor = $ColAccent; $rtbSteps.AppendText("$($step.H)`n")
        $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
        $rtbSteps.SelectionFont = New-Object System.Drawing.Font("Segoe UI",8.5)
        $rtbSteps.SelectionColor = $ColMuted; $rtbSteps.AppendText("$($step.B)`n")
        $first = $false
    }
}

function Show-GuideSteps {
    $rtbSteps.Clear()
    $sections = @(
        @{ H="Phase 1 — Baseline";   B="Confirm the link is degraded on the suspect port. Establishes a reference speed before any changes." }
        @{ H="Phase 2 — NIC Port";   B="Move the SAME cable and camera to a different NIC port. If 1 Gbps: NIC port is faulty. If still degraded: continue." }
        @{ H="Phase 3 — Cable";      B="Stay on the same test port and camera. Swap only the cable for a known-good one. If 1 Gbps: cable is faulty. If still degraded: continue." }
        @{ H="Phase 4 — Camera";     B="Stay on test port and new cable. Swap only the camera for a known-good unit. If 1 Gbps: camera is faulty. If still degraded: NIC/motherboard fault." }
    )
    $first = $true
    foreach ($s in $sections) {
        if (-not $first) {
            $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
            $rtbSteps.SelectionFont = New-Object System.Drawing.Font("Segoe UI",4)
            $rtbSteps.SelectionColor = [System.Drawing.Color]::White; $rtbSteps.AppendText("`n")
        }
        $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
        $rtbSteps.SelectionFont = New-Object System.Drawing.Font("Segoe UI Semibold",9)
        $rtbSteps.SelectionColor = $ColAccent; $rtbSteps.AppendText("$($s.H)`n")
        $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
        $rtbSteps.SelectionFont = New-Object System.Drawing.Font("Segoe UI",8.5)
        $rtbSteps.SelectionColor = $ColMuted; $rtbSteps.AppendText("$($s.B)`n")
        $first = $false
    }
}

function Reset-Guide {
    $script:guide.Phase = 0; $script:guide.SuspectPort = ""; $script:guide.TestPort = ""; $script:guide.BaseSpeed = 0
    $rtbGuide.Text = "Phase results will appear here as you work through each step."
    $pnlGuideResult.Visible = $false
    $lblGuidePhase.Text = "SELECT A PORT TO BEGIN"
    $lblGuideInstr.Text = "Select the NIC port that is showing degraded speed (100 Mbps) and click Start."
    $btnGuideAction.Text = "  Start Baseline"; $btnGuideAction.Enabled = $true
    $lblGuidePortA.Visible = $true; $cboGuidePortA.Visible = $true
    $lblGuidePortB.Visible = $false; $cboGuidePortB.Visible = $false
    Update-GuideStepDots -ActivePhase 1
}

function Update-HistoryList {
    $lvHistory.Items.Clear()
    $files = @(Get-ChildItem -Path $OutputDir -Filter "CameraLink_Results_*.txt" -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)
    if ($files.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.ListViewItem("No history yet")
        $empty.ForeColor = $ColMuted
        $empty.SubItems.Add("") | Out-Null
        $empty.SubItems.Add("Run a diagnostic from the Overview tab to generate history.") | Out-Null
        $empty.SubItems.Add("") | Out-Null
        $lvHistory.Items.Add($empty) | Out-Null
        return
    }
    foreach ($f in $files) {
        $dt = $f.LastWriteTime
        if ($f.Name -match '_(\d{8})_(\d{6})\.txt$') {
            try { $dt = [datetime]::ParseExact("$($Matches[1])$($Matches[2])", "yyyyMMddHHmmss", $null) } catch { }
        }
        $resultText = "Unknown"; $resultColor = $ColMuted; $summary = ""
        try {
            $lines = Get-Content -Path $f.FullName -ErrorAction Stop
            $statusLine = $lines | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
            if ($statusLine -match 'ALL_CLEAR') {
                $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
            } elseif ($statusLine -match 'ISSUES_FOUND') {
                $resultText = "Issues Found"; $resultColor = $ColRed
                $failLines = @($lines | Where-Object { $_ -match 'DEGRADED' })
                $ports = $failLines | ForEach-Object {
                    if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                } | Where-Object { $_ }
                $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " — " + ($ports -join ", ") } else { "" })
            } else {
                # Fallback for files written before v1.5.0
                $failLines = @($lines | Where-Object { $_ -match 'DEGRADED' })
                if ($failLines.Count -gt 0) {
                    $resultText = "Issues Found"; $resultColor = $ColRed
                    $ports = $failLines | ForEach-Object {
                        if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                    } | Where-Object { $_ }
                    $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " — " + ($ports -join ", ") } else { "" })
                } elseif (@($lines | Where-Object { $_ -match 'Complete' }).Count -gt 0) {
                    $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
                }
            }
        } catch { }
        $sizeKb = [math]::Round($f.Length / 1KB, 1)
        $item = New-Object System.Windows.Forms.ListViewItem($dt.ToString("yyyy-MM-dd  HH:mm"))
        $item.SubItems.Add($resultText) | Out-Null
        $item.SubItems.Add($summary)    | Out-Null
        $item.SubItems.Add("$sizeKb KB") | Out-Null
        $item.ForeColor = $resultColor
        $item.BackColor = [System.Drawing.Color]::White
        $item.Tag       = $f.FullName
        $lvHistory.Items.Add($item) | Out-Null
    }
}

# ---- Guide Panel (Fault Isolation Wizard) ----------------------------------
$pnlGuide = New-Object System.Windows.Forms.Panel
$pnlGuide.Size = $center.Size; $pnlGuide.Location = $center.Location
$pnlGuide.BackColor = $ColBg; $pnlGuide.Visible = $false
$pnlGuide.Anchor = $AnchorTLRB
$form.Controls.Add($pnlGuide)

# Title
$lblGuideTitle = New-Object System.Windows.Forms.Label
$lblGuideTitle.Text = "Fault Isolation"
$lblGuideTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblGuideTitle.ForeColor = $ColText
$lblGuideTitle.Location = New-Object System.Drawing.Point(10, 16); $lblGuideTitle.AutoSize = $true
$pnlGuide.Controls.Add($lblGuideTitle)

$lblGuideSub = New-Object System.Windows.Forms.Label
$lblGuideSub.Text = "One change at a time — force the fault to reveal what it follows."
$lblGuideSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblGuideSub.ForeColor = $ColMuted
$lblGuideSub.Location = New-Object System.Drawing.Point(10, 42); $lblGuideSub.Size = New-Object System.Drawing.Size(562, 18)
$pnlGuide.Controls.Add($lblGuideSub)

# Phase step dots: 4 numbered circles
$guideStepDots = @()
$guideStepLabels = @("1  Baseline","2  NIC Port","3  Cable","4  Camera")
$dotX = 10
foreach ($i in 0..3) {
    $dp = New-Object System.Windows.Forms.Panel; $dp.Size = New-Object System.Drawing.Size(110, 28)
    $dp.Location = New-Object System.Drawing.Point($dotX, 64); $dp.BackColor = $ColBg
    $dl = New-Object System.Windows.Forms.Label; $dl.Text = $guideStepLabels[$i]
    $dl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
    $dl.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 200)
    $dl.Location = New-Object System.Drawing.Point(0, 4); $dl.Size = New-Object System.Drawing.Size(110, 20)
    $dl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $dp.Controls.Add($dl)
    $pnlGuide.Controls.Add($dp)
    $guideStepDots += @{ Panel=$dp; Label=$dl }
    $dotX += 114
}

# Blue instruction card
$pnlGuideInstr = New-Object System.Windows.Forms.Panel
$pnlGuideInstr.Size = New-Object System.Drawing.Size(780, 108)
$pnlGuideInstr.Location = New-Object System.Drawing.Point(10, 100)
$pnlGuideInstr.BackColor = $ColAccent
$pnlGuide.Controls.Add($pnlGuideInstr)
$pnlGuideInstr.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,780,108)), 8))

$lblGuidePhase = New-Object System.Windows.Forms.Label
$lblGuidePhase.Text = "SELECT A PORT TO BEGIN"
$lblGuidePhase.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$lblGuidePhase.ForeColor = [System.Drawing.Color]::FromArgb(187, 222, 251)
$lblGuidePhase.Location = New-Object System.Drawing.Point(14, 10); $lblGuidePhase.Size = New-Object System.Drawing.Size(544, 18)
$pnlGuideInstr.Controls.Add($lblGuidePhase)

$lblGuideInstr = New-Object System.Windows.Forms.Label
$lblGuideInstr.Text = "Select the NIC port that is showing degraded speed (100 Mbps) and click Start."
$lblGuideInstr.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblGuideInstr.ForeColor = [System.Drawing.Color]::White
$lblGuideInstr.Location = New-Object System.Drawing.Point(14, 32); $lblGuideInstr.Size = New-Object System.Drawing.Size(544, 66)
$pnlGuideInstr.Controls.Add($lblGuideInstr)

# Port selector row (primary: suspect port / test port as applicable)
$lblGuidePortA = New-Object System.Windows.Forms.Label; $lblGuidePortA.Text = "Suspect port:"
$lblGuidePortA.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblGuidePortA.ForeColor = $ColMuted
$lblGuidePortA.Location = New-Object System.Drawing.Point(10, 220); $lblGuidePortA.Size = New-Object System.Drawing.Size(90, 24)
$pnlGuide.Controls.Add($lblGuidePortA)

$cboGuidePortA = New-Object System.Windows.Forms.ComboBox
$cboGuidePortA.Size = New-Object System.Drawing.Size(200, 24); $cboGuidePortA.Location = New-Object System.Drawing.Point(104, 218)
$cboGuidePortA.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboGuidePortA.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$pnlGuide.Controls.Add($cboGuidePortA)

$lblGuidePortB = New-Object System.Windows.Forms.Label; $lblGuidePortB.Text = "Test port:"
$lblGuidePortB.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblGuidePortB.ForeColor = $ColMuted
$lblGuidePortB.Location = New-Object System.Drawing.Point(318, 220); $lblGuidePortB.Size = New-Object System.Drawing.Size(70, 24)
$lblGuidePortB.Visible = $false
$pnlGuide.Controls.Add($lblGuidePortB)

$cboGuidePortB = New-Object System.Windows.Forms.ComboBox
$cboGuidePortB.Size = New-Object System.Drawing.Size(168, 24); $cboGuidePortB.Location = New-Object System.Drawing.Point(392, 218)
$cboGuidePortB.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboGuidePortB.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$cboGuidePortB.Visible = $false
$pnlGuide.Controls.Add($cboGuidePortB)

# Action button
$btnGuideAction = New-Object System.Windows.Forms.Button; $btnGuideAction.Text = "  Start Baseline"
$btnGuideAction.Size = New-Object System.Drawing.Size(780, 40); $btnGuideAction.Location = New-Object System.Drawing.Point(10, 250)
$btnGuideAction.BackColor = $ColAccent; $btnGuideAction.ForeColor = [System.Drawing.Color]::White
$btnGuideAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGuideAction.FlatAppearance.BorderSize = 0
$btnGuideAction.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnGuideAction.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGuideAction.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,780,40)), 6))
$pnlGuide.Controls.Add($btnGuideAction)

# Result card (hidden until a check completes)
$pnlGuideResult = New-Object System.Windows.Forms.Panel
$pnlGuideResult.Size = New-Object System.Drawing.Size(780, 84)
$pnlGuideResult.Location = New-Object System.Drawing.Point(10, 302)
$pnlGuideResult.BackColor = [System.Drawing.Color]::White
$pnlGuideResult.Visible = $false
$pnlGuideResult.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,780,84)), 8))
$pnlGuideResult.Add_Paint(({
    param($s,$e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rr = New-Object System.Drawing.Rectangle(0,0,571,83)
    $bp = [GfxHelper]::RoundedRect($rr,8)
    $pen = New-Object System.Drawing.Pen($ColBorder,1)
    $e.Graphics.DrawPath($pen,$bp); $pen.Dispose(); $bp.Dispose()
}).GetNewClosure())
$pnlGuide.Controls.Add($pnlGuideResult)

$lblGuideResultSpeed = New-Object System.Windows.Forms.Label; $lblGuideResultSpeed.Text = ""
$lblGuideResultSpeed.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$lblGuideResultSpeed.ForeColor = $ColText
$lblGuideResultSpeed.Location = New-Object System.Drawing.Point(14, 10); $lblGuideResultSpeed.Size = New-Object System.Drawing.Size(544, 26)
$pnlGuideResult.Controls.Add($lblGuideResultSpeed)

$lblGuideResultVerdict = New-Object System.Windows.Forms.Label; $lblGuideResultVerdict.Text = ""
$lblGuideResultVerdict.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblGuideResultVerdict.ForeColor = $ColMuted
$lblGuideResultVerdict.Location = New-Object System.Drawing.Point(14, 38); $lblGuideResultVerdict.Size = New-Object System.Drawing.Size(544, 36)
$pnlGuideResult.Controls.Add($lblGuideResultVerdict)

# Phase history
$sep7 = New-Object System.Windows.Forms.Panel; $sep7.Size = New-Object System.Drawing.Size(780,1)
$sep7.Location = New-Object System.Drawing.Point(10, 398); $sep7.BackColor = $ColBorder
$pnlGuide.Controls.Add($sep7)

$lblGuideHist = New-Object System.Windows.Forms.Label; $lblGuideHist.Text = "Phase History"
$lblGuideHist.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $lblGuideHist.ForeColor = $ColText
$lblGuideHist.Location = New-Object System.Drawing.Point(10, 408); $lblGuideHist.AutoSize = $true
$pnlGuide.Controls.Add($lblGuideHist)

$lnkGuideReset = New-Object System.Windows.Forms.LinkLabel; $lnkGuideReset.Text = "Start Over"
$lnkGuideReset.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lnkGuideReset.LinkColor = $ColMuted
$lnkGuideReset.Location = New-Object System.Drawing.Point(530, 410); $lnkGuideReset.AutoSize = $true
$pnlGuide.Controls.Add($lnkGuideReset)

$rtbGuide = New-Object System.Windows.Forms.RichTextBox
$rtbGuide.Size = New-Object System.Drawing.Size(780, 220); $rtbGuide.Location = New-Object System.Drawing.Point(10, 430); $rtbGuide.Anchor = $AnchorTLRB
$rtbGuide.BackColor = $ColLogBg; $rtbGuide.ForeColor = [System.Drawing.Color]::FromArgb(203,213,225)
$rtbGuide.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $rtbGuide.ReadOnly = $true
$rtbGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbGuide.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbGuide.Text = "Phase results will appear here as you work through each step."
$pnlGuide.Controls.Add($rtbGuide)

function Save-GuideSession {
    if (-not $sync.OutputFile -or -not (Test-Path $sync.OutputFile)) { return }
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = "`n" + ("=" * 64) + "`n FAULT ISOLATION SESSION  $ts`n" + ("=" * 64) + "`n" + $rtbGuide.Text
    Add-Content -Path $sync.OutputFile -Value $content -ErrorAction SilentlyContinue
}

# ---- Guide State & Logic ---------------------------------------------------
$script:guide = @{
    Phase        = 0       # 0=setup, 1=baseline done, 2=nic done, 3=cable done, 4=concluded
    SuspectPort  = ""
    TestPort     = ""
    BaseSpeed    = 0
    PhaseHistory = [System.Collections.ArrayList]::new()
}

function Get-GuideLinkSpeed {
    param([string]$PortName, [int]$MaxSeconds = 12)
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    $peak = 0
    while ((Get-Date) -lt $deadline) {
        try {
            $a = Get-NetAdapter -Name $PortName -ErrorAction Stop
            if ($a.Status -eq "Up") {
                $ls = $a.LinkSpeed.ToString()
                if ($ls -match '(\d+(?:\.\d+)?)\s*Gbps') { $s = [int]([double]$Matches[1]*1000) }
                elseif ($ls -match '(\d+(?:\.\d+)?)\s*Mbps') { $s = [int]$Matches[1] }
                else { $s = 0 }
                if ($s -gt $peak) { $peak = $s }
                if ($peak -ge 1000) { break }
            }
        } catch { }
        Start-Sleep -Milliseconds 600
        [System.Windows.Forms.Application]::DoEvents()
    }
    return $peak
}

function Update-GuideStepDots {
    param([int]$ActivePhase)
    for ($i = 0; $i -lt 4; $i++) {
        $phaseNum = $i + 1
        if ($phaseNum -lt $ActivePhase) {
            $guideStepDots[$i].Label.ForeColor = $ColGreen
        } elseif ($phaseNum -eq $ActivePhase) {
            $guideStepDots[$i].Label.ForeColor = [System.Drawing.Color]::White
        } else {
            $guideStepDots[$i].Label.ForeColor = [System.Drawing.Color]::FromArgb(180,190,200)
        }
    }
}

function Add-GuideHistory {
    param([string]$Phase, [string]$Config, [string]$Speed, [string]$Verdict, [string]$Color = "Info")
    $rtbGuide.SelectionStart = $rtbGuide.TextLength; $rtbGuide.SelectionLength = 0
    $col = switch ($Color) { "Pass" {[System.Drawing.Color]::FromArgb(74,222,128)} "Fail" {[System.Drawing.Color]::FromArgb(252,165,165)} default {[System.Drawing.Color]::FromArgb(148,163,184)} }
    $rtbGuide.SelectionColor = $col
    $rtbGuide.SelectionFont  = New-Object System.Drawing.Font("Segoe UI Semibold",8.5)
    $rtbGuide.AppendText("$Phase`n")
    $rtbGuide.SelectionStart = $rtbGuide.TextLength; $rtbGuide.SelectionLength = 0
    $rtbGuide.SelectionColor = [System.Drawing.Color]::FromArgb(148,163,184)
    $rtbGuide.SelectionFont  = New-Object System.Drawing.Font("Segoe UI",8)
    $rtbGuide.AppendText("  $Config`n  Speed: $Speed`n  $Verdict`n`n")
    $rtbGuide.ScrollToCaret()
}

function Show-GuideResult {
    param([string]$SpeedText, [string]$Verdict, [string]$StatusColor)
    $col = switch ($StatusColor) { "Pass" {$ColGreen} "Fail" {$ColRed} default {$ColYellow} }
    $lblGuideResultSpeed.Text    = $SpeedText
    $lblGuideResultSpeed.ForeColor = $col
    $lblGuideResultVerdict.Text  = $Verdict
    $pnlGuideResult.Visible      = $true
    $pnlGuideResult.Refresh()
}

# Wire up action button
$btnGuideAction.Add_Click({
    switch ($script:guide.Phase) {
        0 {
            # Phase 0 → run baseline on suspect port
            $portName = $cboGuidePortA.Text -replace '\s.*',''
            if (-not $portName) { return }
            $script:guide.SuspectPort = $portName

            $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
            $rtbGuide.Clear()
            $speed = Get-GuideLinkSpeed -PortName $portName
            $script:guide.BaseSpeed = $speed
            $btnGuideAction.Enabled = $true

            $speedLabel = if ($speed -ge 1000) { "1 Gbps" } elseif ($speed -gt 0) { "$speed Mbps" } else { "No link" }
            $config = "Port: $portName  |  Cable: (original)  |  Camera: (original)"

            if ($speed -ge 1000) {
                Show-GuideResult "Baseline: $speedLabel — Port is operating normally." "The selected port is already running at 1 Gbps. No fault detected on this port. Select a different port or run the full diagnostic." "Pass"
                Add-GuideHistory "Phase 1 — Baseline" $config $speedLabel "Port healthy — no fault on this port." "Pass"
                $lblGuidePhase.Text = "BASELINE — PORT HEALTHY"
                $lblGuideInstr.Text = "This port is operating normally at 1 Gbps. Select a different port above, or use Overview > Run Full Diagnostic."
                $btnGuideAction.Text = "  Recheck Port"
                $btnGuideAction.Enabled = $true
                Update-GuideStepDots -ActivePhase 1
                return
            }

            $baseMsg   = if ($speed -eq 0) { "No link detected" } else { "Degraded link confirmed" }
            $baseInstr = if ($speed -eq 0) {
                "No link on $portName. First verify the camera is powered on and the cable is seated firmly at both ends. If the problem persists with a confirmed-connected camera, proceed to isolate which component is at fault."
            } else {
                "Degraded link confirmed. Move the SAME cable and SAME camera from $portName to the port selected below."
            }
            Add-GuideHistory "Phase 1 — Baseline" $config $speedLabel "$baseMsg — beginning isolation." "Fail"
            Show-GuideResult "Baseline: $speedLabel — $baseMsg." $baseInstr "Fail"
            $script:guide.Phase = 1
            Update-GuideStepDots -ActivePhase 2

            # Populate test port dropdown (all ports except suspect)
            $cboGuidePortB.Items.Clear()
            try {
                $others = Get-NetAdapter | Where-Object { $d = $_.InterfaceDescription; ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0 -and $_.Name -ne $portName } | Sort-Object Name
                foreach ($n in $others) { $cboGuidePortB.Items.Add($n.Name) | Out-Null }
            } catch { }
            if ($cboGuidePortB.Items.Count -gt 0) { $cboGuidePortB.SelectedIndex = 0 }

            $lblGuidePortA.Visible = $false; $cboGuidePortA.Visible = $false
            $lblGuidePortB.Visible = $true;  $cboGuidePortB.Visible = $true
            $lblGuidePhase.Text = "PHASE 2 — DOES THE FAULT FOLLOW THE NIC PORT?"
            $lblGuideInstr.Text = "Move the SAME cable and SAME camera from $portName to the port selected below. Press Check when reconnected."
            $btnGuideAction.Text = "  Check Now"
            $btnGuideAction.Enabled = $true
        }
        1 {
            # Phase 1 → check after moving cable+CHU to test port
            $testPort = $cboGuidePortB.Text -replace '\s.*',''
            if (-not $testPort) { return }
            $script:guide.TestPort = $testPort

            # Pre-check: read test port speed before assuming the tech has moved anything.
            # If it is already degraded, the isolation result would be misleading.
            $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Pre-checking port..."
            $preSpeed = Get-GuideLinkSpeed -PortName $testPort -MaxSeconds 4
            if ($preSpeed -gt 0 -and $preSpeed -lt 1000) {
                $btnGuideAction.Enabled = $true; $btnGuideAction.Text = "  Check Now"
                $dlg = [System.Windows.Forms.MessageBox]::Show(
                    "$testPort is already showing degraded speed ($preSpeed Mbps) before you moved anything.`n`nIf this port has its own independent fault, Phase 2 results will be unreliable — the test needs a known-good port to be valid.`n`nClick Cancel to pick a different test port, or OK to proceed anyway.",
                    "Test Port May Be Faulty",
                    [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($dlg -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
                $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
            }
            $speed = Get-GuideLinkSpeed -PortName $testPort
            $btnGuideAction.Enabled = $true

            $speedLabel = if ($speed -ge 1000) { "1 Gbps" } elseif ($speed -gt 0) { "$speed Mbps" } else { "No link" }
            $config = "Port: $testPort  |  Cable: (original)  |  Camera: (original)"

            if ($speed -ge 1000) {
                $verdict = "Fault cleared on $testPort — cable and camera are healthy on a different port. Original port ($($script:guide.SuspectPort)) is likely faulty."
                Show-GuideResult "Phase 2: $speedLabel — Fault follows the original NIC port." $verdict "Pass"
                Add-GuideHistory "Phase 2 — NIC Port Test" $config $speedLabel $verdict "Pass"
                $lblGuidePhase.Text = "CONCLUSION — FAULTY NIC PORT"
                $lblGuideInstr.Text = "The cable and camera work fine on $testPort. The original port ($($script:guide.SuspectPort)) is the source of the fault. Replace or disable that NIC port."
                $btnGuideAction.Text = "  Run Full Diagnostic"
                $script:guide.Phase = 4
                Update-GuideStepDots -ActivePhase 4
                Save-GuideSession
            } else {
                $verdict = "Fault persists on $testPort — the original NIC port is likely healthy. The fault is in the cable or camera."
                Show-GuideResult "Phase 2: $speedLabel — Fault follows cable/camera, not the NIC port." $verdict "Warn"
                Add-GuideHistory "Phase 2 — NIC Port Test" $config $speedLabel $verdict "Info"
                $script:guide.Phase = 2
                $lblGuidePortB.Visible = $false; $cboGuidePortB.Visible = $false
                $lblGuidePhase.Text = "PHASE 3 — DOES THE FAULT FOLLOW THE CABLE?"
                $lblGuideInstr.Text = "Stay on $testPort with the same camera. Replace ONLY the cable with a known-good cable. Press Check when reconnected."
                $btnGuideAction.Text = "  Check Now"
                Update-GuideStepDots -ActivePhase 3
            }
        }
        2 {
            # Phase 2 → check after swapping cable
            $testPort = $script:guide.TestPort
            $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
            $speed = Get-GuideLinkSpeed -PortName $testPort
            $btnGuideAction.Enabled = $true

            $speedLabel = if ($speed -ge 1000) { "1 Gbps" } elseif ($speed -gt 0) { "$speed Mbps" } else { "No link" }
            $config = "Port: $testPort  |  Cable: (NEW - known good)  |  Camera: (original)"

            if ($speed -ge 1000) {
                $verdict = "Link restored with new cable. The original cable is the source of the fault — bad cable or termination."
                Show-GuideResult "Phase 3: $speedLabel — Fault follows the cable." $verdict "Pass"
                Add-GuideHistory "Phase 3 — Cable Test" $config $speedLabel $verdict "Pass"
                $lblGuidePhase.Text = "CONCLUSION — FAULTY CABLE"
                $lblGuideInstr.Text = "Replacing the cable resolved the issue. The original cable (or its termination) is the source of the fault. Replace the cable end-to-end."
                $btnGuideAction.Text = "  Run Full Diagnostic"
                $script:guide.Phase = 4
                Update-GuideStepDots -ActivePhase 4
                Save-GuideSession
            } else {
                $verdict = "Still degraded with new cable. Cable is not the fault — the camera is the likely cause."
                Show-GuideResult "Phase 3: $speedLabel — Fault is not the cable." $verdict "Warn"
                Add-GuideHistory "Phase 3 — Cable Test" $config $speedLabel $verdict "Info"
                $script:guide.Phase = 3
                $lblGuidePhase.Text = "PHASE 4 — DOES THE FAULT FOLLOW THE CAMERA?"
                $lblGuideInstr.Text = "Stay on $testPort with the new cable. Connect a known-good camera. Press Check when reconnected."
                $btnGuideAction.Text = "  Check Now"
                Update-GuideStepDots -ActivePhase 4
            }
        }
        3 {
            # Phase 3 → check after swapping camera
            $testPort = $script:guide.TestPort
            $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
            $speed = Get-GuideLinkSpeed -PortName $testPort
            $btnGuideAction.Enabled = $true

            $speedLabel = if ($speed -ge 1000) { "1 Gbps" } elseif ($speed -gt 0) { "$speed Mbps" } else { "No link" }
            $config = "Port: $testPort  |  Cable: (NEW)  |  Camera: (NEW - known good)"

            if ($speed -ge 1000) {
                $verdict = "Link restored with new camera. The original camera unit is the source of the fault."
                Show-GuideResult "Phase 4: $speedLabel — Fault follows the camera." $verdict "Pass"
                Add-GuideHistory "Phase 4 — Camera Test" $config $speedLabel $verdict "Pass"
                $lblGuidePhase.Text = "CONCLUSION — FAULTY CAMERA (CHU)"
                $lblGuideInstr.Text = "Replacing the camera resolved the issue. The original camera is the source of the fault. Replace the camera unit."
            } else {
                $verdict = "Still degraded with known-good cable and camera. The fault is likely in the NIC hardware itself or the VPU motherboard."
                Show-GuideResult "Phase 4: $speedLabel — Fault persists with known-good equipment." $verdict "Fail"
                Add-GuideHistory "Phase 4 — Camera Test" $config $speedLabel $verdict "Fail"
                $lblGuidePhase.Text = "CONCLUSION — NIC / HARDWARE FAULT"
                $lblGuideInstr.Text = "Known-good cable and camera still fail on $testPort. This indicates a fault in the NIC hardware or VPU motherboard. Run the full diagnostic and escalate."
            }
            $btnGuideAction.Text = "  Run Full Diagnostic"
            $script:guide.Phase = 4
            Update-GuideStepDots -ActivePhase 4
            Save-GuideSession
        }
        4 {
            # Phase 4 (concluded) → jump to Overview and trigger diagnostic
            $navOverview.PerformClick()
            $btnRun.PerformClick()
        }
    }
})

$lnkGuideReset.Add_LinkClicked({ Reset-Guide })

# ---- History Panel ---------------------------------------------------------
$pnlHistory = New-Object System.Windows.Forms.Panel
$pnlHistory.Size = $center.Size; $pnlHistory.Location = $center.Location
$pnlHistory.BackColor = $ColBg; $pnlHistory.Visible = $false
$pnlHistory.Anchor = $AnchorTLRB
$form.Controls.Add($pnlHistory)

$lblHistTitle = New-Object System.Windows.Forms.Label
$lblHistTitle.Text = "Run History"
$lblHistTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHistTitle.ForeColor = $ColText
$lblHistTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHistTitle.AutoSize = $true
$pnlHistory.Controls.Add($lblHistTitle)

$lblHistSub = New-Object System.Windows.Forms.Label
$lblHistSub.Text = "Past diagnostic runs — double-click a row to open the full report."
$lblHistSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblHistSub.ForeColor = $ColMuted
$lblHistSub.Location = New-Object System.Drawing.Point(10, 42); $lblHistSub.Size = New-Object System.Drawing.Size(540, 18)
$pnlHistory.Controls.Add($lblHistSub)

$lnkHistRefresh = New-Object System.Windows.Forms.LinkLabel; $lnkHistRefresh.Text = "Refresh"
$lnkHistRefresh.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lnkHistRefresh.LinkColor = $ColMuted
$lnkHistRefresh.Location = New-Object System.Drawing.Point(544, 44); $lnkHistRefresh.AutoSize = $true
$pnlHistory.Controls.Add($lnkHistRefresh)
$lnkHistRefresh.Add_LinkClicked({ Update-HistoryList })

$lvHistory = New-Object System.Windows.Forms.ListView
$lvHistory.Size = New-Object System.Drawing.Size(780, 594)
$lvHistory.Location = New-Object System.Drawing.Point(10, 68); $lvHistory.Anchor = $AnchorTLRB
$lvHistory.View = [System.Windows.Forms.View]::Details
$lvHistory.FullRowSelect = $true
$lvHistory.GridLines = $false
$lvHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lvHistory.BackColor = [System.Drawing.Color]::White
$lvHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lvHistory.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$lvHistory.UseCompatibleStateImageBehavior = $false
$pnlHistory.Controls.Add($lvHistory)
$lvHistory.Columns.Add("Date / Time",   142) | Out-Null
$lvHistory.Columns.Add("Result",         92) | Out-Null
$lvHistory.Columns.Add("Summary",       468) | Out-Null
$lvHistory.Columns.Add("Size",           58) | Out-Null

$lvHistory.Add_DoubleClick({
    if ($lvHistory.SelectedItems.Count -gt 0) {
        $path = $lvHistory.SelectedItems[0].Tag
        if ($path -and (Test-Path $path)) { Start-Process notepad.exe $path }
    }
})

# ---- Help Panel ------------------------------------------------------------
$pnlHelp = New-Object System.Windows.Forms.Panel
$pnlHelp.Size = $center.Size; $pnlHelp.Location = $center.Location
$pnlHelp.BackColor = $ColBg; $pnlHelp.Visible = $false
$pnlHelp.Anchor = $AnchorTLRB
$form.Controls.Add($pnlHelp)

$lblHelpTitle = New-Object System.Windows.Forms.Label
$lblHelpTitle.Text = "How to Use This Tool"
$lblHelpTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHelpTitle.ForeColor = $ColText
$lblHelpTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHelpTitle.AutoSize = $true
$pnlHelp.Controls.Add($lblHelpTitle)

$rtbHelp = New-Object System.Windows.Forms.RichTextBox
$rtbHelp.Size = New-Object System.Drawing.Size(780, 636); $rtbHelp.Location = New-Object System.Drawing.Point(10, 46); $rtbHelp.Anchor = $AnchorTLRB
$rtbHelp.BackColor = $ColBg; $rtbHelp.ForeColor = $ColText
$rtbHelp.Font = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.ReadOnly = $true
$rtbHelp.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbHelp.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$pnlHelp.Controls.Add($rtbHelp)

$helpSections = @(
    @{ H="What this tool does";           B="Diagnoses camera NIC link-speed problems on Pixellot VPUs. It measures link speed on each Intel NIC port, checks for Intel SmartSpeed downgrade events (physical-layer evidence), pings each camera, and analyses the Pixellot application log. Results appear in plain language with a recommended next action." }
    @{ H="Overview tab — running a diagnostic"; B="Click Run Full Diagnostic and wait about 60–90 seconds. The port cards (P1–P4) update live as each port is measured. When complete, the right panel shows numbered next steps.`n`nIf a port shows a degraded link, the SmartSpeed card tells you how many downgrade events occurred in the last 48 hours — that count is the key evidence to quote when escalating." }
    @{ H="Reading the port cards";        B="Green / 1 Gbps = healthy link.`nRed / 100 Mbps = degraded (physical fault, use Isolate to pinpoint the cause).`nGrey / No link = no cable connected or device off.`n100M OCR = expected for OCR scoreboard cameras (100 Mbps-only, no action needed).`n`nClicking a red port card takes you straight to Isolate with that port pre-selected." }
    @{ H="Isolate tab — fault isolation"; B="Use Isolate when Overview shows a degraded port and you need to know whether to replace the cable, the NIC port, or the camera. Do not replace anything until Isolate tells you what is at fault.`n`nIsolate uses the 'one change at a time' method:`n  Phase 1 — Baseline: confirm the fault exists.`n  Phase 2 — NIC Port: move cable+camera to another port.`n  Phase 3 — Cable: swap in a known-good cable.`n  Phase 4 — Camera: swap in a known-good camera.`n`nEach phase measures link speed and tells you whether the fault followed the changed component." }
    @{ H="History tab";                   B="Shows all past diagnostic runs from the CameraLink_Results folder. Green rows are All Clear; red rows show Issues Found with the affected port(s). Double-click any row to open the full report in Notepad.`n`nIf the same port appears as Issues Found across many runs, the trend line on the Overview summary card will note this — useful evidence when requesting a replacement." }
    @{ H="Escalating to support";         B="After a run, click Copy Summary in the Actions section. This generates a structured paragraph with port status, SmartSpeed count, camera results, and recommended next steps — paste it directly into your ticket or support chat.`n`nThe Run ID in the summary matches the filename in CameraLink_Results so the agent can ask you to email the full report if needed." }
    @{ H="What is a SmartSpeed event?";   B="Intel SmartSpeed Event ID 40 fires when the NIC tried to establish a gigabit link but the physical medium could not sustain it. It only fires on physical-layer failures — it never fires when a device (like an OCR camera) simply doesn't support gigabit.`n`nAny non-zero SmartSpeed count on a camera NIC is definitive evidence of a cable, termination, or NIC fault. Zero events on a 100 Mbps port means the device is 100-Mbps-only (OCR camera)." }
    @{ H="Frequently asked questions";    B="Q: The VPU Model shows 'Not detected' — is that a problem?`nA: No. The tool still runs a full diagnostic. VPU model detection requires the Pixellot agent log to be present and recently updated.`n`nQ: Ethernet 47 / 48 show No link — is that a fault?`nA: No link is normal for ports that don't have a camera connected. Only ports that should have a camera but show 100 Mbps are faults.`n`nQ: Isolate says 'NIC / hardware fault' — what now?`nA: Known-good cable and camera still fail on the test port. Run a full diagnostic, use Copy Summary, and escalate to L2 support for hardware replacement." }
)
$firstHelp = $true
foreach ($s in $helpSections) {
    if (-not $firstHelp) {
        $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
        $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI",5); $rtbHelp.SelectionColor = $ColBg; $rtbHelp.AppendText("`n")
    }
    $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
    $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $rtbHelp.SelectionColor = $ColText; $rtbHelp.AppendText("$($s.H)`n")
    $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
    $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.SelectionColor = $ColMuted; $rtbHelp.AppendText("$($s.B)`n")
    $firstHelp = $false
}

# Nav wiring
function Set-ActiveNav {
    param($Active)
    foreach ($nb in @($navOverview,$navTests,$navHistory,$navHelp)) {
        $nb.BackColor = $ColSidebar; $nb.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    }
    $Active.BackColor = $ColNavActive; $Active.ForeColor = [System.Drawing.Color]::White
}

function Show-Panel {
    param($Panel)
    foreach ($p in @($center,$pnlGuide,$pnlHistory,$pnlHelp)) { $p.Visible = $false }
    $Panel.Visible = $true
}

$navOverview.Add_Click({
    Show-Panel $center; Set-ActiveNav $navOverview; Show-OverviewSteps
})

$navTests.Add_Click({
    Show-Panel $pnlGuide; Set-ActiveNav $navTests; Show-GuideSteps
})

$navHistory.Add_Click({
    Show-Panel $pnlHistory; Set-ActiveNav $navHistory; Update-HistoryList
})

$navHelp.Add_Click({
    Show-Panel $pnlHelp; Set-ActiveNav $navHelp
})

$btnGoGuide.Add_Click({
    $firstFail = $sync.PortResults | Where-Object { $_.Result -eq "FAIL" } | Select-Object -First 1
    $navTests.PerformClick()
    Reset-Guide
    if ($firstFail) {
        $idx = $cboGuidePortA.Items.IndexOf($firstFail.Name)
        if ($idx -ge 0) { $cboGuidePortA.SelectedIndex = $idx }
    }
})

# ---------- Form Load -------------------------------------------------------
$form.Add_Load({
    $cboNic.Items.Add("All Ports") | Out-Null
    try {
        foreach ($n in $script:detectedNics) {
            $short = $n.InterfaceDescription -replace 'Intel\(R\) 82574L Gigabit Network Connection','CHU NIC'
            $short = $short -replace 'Intel\(R\) I210 Gigabit Network Connection','CHU NIC'
            $cboNic.Items.Add("$($n.Name)  ($short)") | Out-Null
            $cboGuidePortA.Items.Add($n.Name) | Out-Null
        }
    } catch { }
    if ($cboNic.Items.Count -gt 0) { $cboNic.SelectedIndex = 0 }
    if ($cboGuidePortA.Items.Count -gt 0) { $cboGuidePortA.SelectedIndex = 0 }
    Update-GuideStepDots -ActivePhase 1

    try {
        $osCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($osCaption) { $lblQiOs.Text = "OS: $($osCaption -replace 'Microsoft Windows ','Win ')" }
    } catch { }

    # Async update check — compares remote $ScriptVersion to current; shows notice if newer
    try {
        $wc = New-Object System.Net.WebClient
        Register-ObjectEvent -InputObject $wc -EventName DownloadStringCompleted `
            -MessageData @{ Sync = $sync; CurVer = $ScriptVersion } -Action {
            try {
                $data = $Event.MessageData
                if (-not $EventArgs.Error -and
                    $EventArgs.Result -match '\$ScriptVersion\s*=\s*"(\d+\.\d+\.\d+)"') {
                    if ([version]$Matches[1] -gt [version]$data.CurVer) {
                        $data.Sync.UpdateAvailable = $Matches[1]
                    }
                }
            } catch { }
        } | Out-Null
        $wc.DownloadStringAsync([uri]$ScriptUrl)
    } catch { }
})

$form.Add_FormClosing({
    $timer.Stop(); $sync.Cancelled = $true
    try { if ($script:runspace) { $script:runspace.Close(); $script:runspace.Dispose() } } catch { }
})

[System.Windows.Forms.Application]::Run($form)
