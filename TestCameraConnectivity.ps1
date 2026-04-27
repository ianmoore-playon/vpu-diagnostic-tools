# =============================================================================
#  VPU Cable & NIC Troubleshooter  v3.9
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
$ScriptVersion      = "3.10"
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
$RtspPort = 554

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
        LinkSpeed = @{ Value = "--"; Status = "neutral" }
        NicStatus = @{ Value = "--"; Status = "neutral" }
        PingCHU   = @{ Value = "--"; Status = "neutral" }
        Gateway   = @{ Value = "--"; Status = "neutral" }
        ArpEntry  = @{ Value = "--"; Status = "neutral" }
        ChuDetect = @{ Value = "--"; Status = "neutral" }
    }
    PortResults = [System.Collections.ArrayList]::new()
    CamResults  = [System.Collections.ArrayList]::new()
    AppIssues   = [System.Collections.ArrayList]::new()
    NextSteps   = [System.Collections.ArrayList]::new()
    Hardware    = @{ CHU = "--"; CameraPort = "--"; CableStatus = "--" }
})

# ---------- Diagnostic engine (runs in background runspace) -----------------
$DiagScript = {
    param($sync, $NicDriverPatterns, $RenegotiateWaitSec, $EventLogHours,
          $PixellotLogPaths, $CameraIPs, $RtspPort, $OutputFile, $RunId, $ScriptVersion)

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
    $sync.TotalDowngrades = 0; $sync.LastRunLine = ""
    $sync.Hardware = @{ CHU = "--"; CameraPort = "--"; CableStatus = "--" }
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
    Add-Summary "VPU Model" $sync.VpuModel (if ($VpuModel) { "Info" } else { "Warn" })

    # ── Find NIC ports ────────────────────────────────────────────────────────
    $sync.CurrentStep = "Detecting NIC ports..."
    Add-Log "-- Detecting Camera NIC Ports --" "Cyan"
    Add-Log ""
    Add-Section "Hardware"
    $nicPorts = Get-NetAdapter | Where-Object {
        $d = $_.InterfaceDescription
        ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
    } | Sort-Object Name

    if ($nicPorts.Count -eq 0) {
        Add-Log "  [FAIL] No camera NIC adapters found." "Fail"
        Set-Card "NicStatus" "Not Found" "fail"
        Add-Summary "NIC Detection" "No camera NICs found" "Fail"
        $sync.NextSteps.Add(@{
            H = "Wrong machine - no VPU hardware detected"
            B = "This tool requires a Pixellot VPU with Intel 82574L or I210 camera NICs. No compatible NICs were found on this machine. Run the tool directly on the VPU."
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
            Add-Summary $nm "1 Gbps  OK" "Pass"
        } elseif ($spd -eq 100) {
            Add-Log "  Speed   : 100 Mbps  [DEGRADED]" "Fail"
            if (-not $ssHistory.ContainsKey($nic.InterfaceDescription)) {
                Add-Log "  [PASS]  No SmartSpeed history - 100 Mbps-only device (OCR camera). Skipping remediation." "Pass"
                $ocrAdapters[$nic.InterfaceDescription] = $true
                $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                Add-Summary $nm "100 Mbps  OCR camera" "Pass"
            } else {
                Add-Log "  [ACTION] SmartSpeed history confirmed - attempting to force 1 Gbps..." "Warn"
                $sync.CurrentStep = "Forcing 1 Gbps on $nm..."
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
                        Add-Summary $nm "DEGRADED  cable fault" "Fail"
                    }
                } else {
                    Add-Log "  [FAIL]  Could not apply SpeedDuplex setting." "Fail"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="FAIL"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    $anyFail = $true
                    Add-Summary $nm "DEGRADED  (SpeedDuplex failed)" "Fail"
                }
            }
        } elseif ($spd -eq 0) {
            Add-Log "  Speed   : No link - no cable or device powered off." "Gray"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=0; Result="NO LINK"; Blinking=$false; Desc=$nic.InterfaceDescription }
            Add-Summary $nm "No link" "Gray"
        } else {
            Add-Log ("  Speed   : {0} Mbps - unexpected" -f $spd) "Warn"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="UNKNOWN"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
            Add-Summary $nm "$spd Mbps  unexpected" "Warn"
        }
        Add-Log ""
    }

    if ($anyFail)           { Set-Card "LinkSpeed" "100 Mbps" "fail";    Set-Card "NicStatus" "Degraded" "fail" }
    elseif ($bestSpeed -eq 1000) { Set-Card "LinkSpeed" "1 Gbps"  "ok"; Set-Card "NicStatus" "Up"       "ok"   }
    elseif ($bestSpeed -eq 0)    { Set-Card "LinkSpeed" "No Link" "neutral"; Set-Card "NicStatus" "Down" "fail" }
    else                         { Set-Card "LinkSpeed" "$bestSpeed Mbps" "warn"; Set-Card "NicStatus" "Partial" "warn" }

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
    } else {
        Add-Log "  [PASS] No SmartSpeed downgrade events on CHU ports." "Pass"
        $sync.StepsDone["SmartSpeed"] = "pass"
        Add-Summary "SmartSpeed Events" "None in ${EventLogHours}h" "Pass"
    }
    Add-Log ""

    # ── Gateway check ─────────────────────────────────────────────────────────
    Add-Section "Network"
    $sync.CurrentStep = "Checking gateway..."
    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
           Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) {
        if (Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            Set-Card "Gateway" "Reachable" "ok";    Add-Log ("  [PASS] Gateway {0} reachable." -f $gw) "Pass"
            Add-Summary "Gateway" "$gw  reachable" "Pass"
        } else {
            Set-Card "Gateway" "Unreachable" "fail"; Add-Log ("  [WARN] Gateway {0} not responding." -f $gw) "Warn"
            Add-Summary "Gateway" "$gw  not responding" "Fail"
        }
    } else {
        Set-Card "Gateway" "No Route" "neutral"; Add-Log "  [INFO] No default gateway configured." "Gray"
        Add-Summary "Gateway" "No route configured" "Gray"
    }

    # ── ARP check ─────────────────────────────────────────────────────────────
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
        $sync.Hardware.CHU = $arpEntries[0].LinkLayerAddress
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

    $sync.Hardware.CameraPort = if ($mainPingCount -gt 0) { "Responding" } else { "No Response" }
    $sync.Hardware.CableStatus = if ($anyFail) { "Degraded" } elseif ($bestSpeed -eq 1000) { "OK (1 Gbps)" } else { "--" }

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
    $failPorts  = $portResults | Where-Object { $_.Result -eq "FAIL" }
    $rtspFaults = $camResults  | Where-Object { $_.Ping -and -not $_.Rtsp }
    $noPingMain = $camResults  | Where-Object { -not $_.Optional -and -not $_.Ping }
    $allClear   = ($failPorts.Count -eq 0) -and ($rtspFaults.Count -eq 0) -and
                  ($sync.TotalDowngrades -eq 0) -and ($sync.AppIssues.Count -eq 0) -and
                  ($noPingMain.Count -eq 0)
    $sync.AllClear = $allClear

    if ($allClear) {
        $sync.NextSteps.Add(@{ H="All tests passed."; B="No action required. All NIC ports and cameras are healthy." }) | Out-Null
    } else {
        $s = 1
        foreach ($r in $failPorts) {
            $bNote = if ($r.Blinking) { " (intermittent)" } else { "" }
            $sync.NextSteps.Add(@{
                H = "$s. Replace cable on $($r.Name)$bNote"
                B = "The NIC could not hold gigabit. Swap in a known-good cable and check both RJ45 ends for bent pins. Re-run this tool after swapping to confirm the link comes up at 1 Gbps."
            }) | Out-Null
            $s++
        }
        foreach ($c in $rtspFaults) {
            $sync.NextSteps.Add(@{
                H = "$s. PoE reset $($c.IP)"
                B = "Camera is reachable by ping but RTSP port 554 is not responding — the camera software has likely stalled. In VPU Manager go to Settings > Cameras, select this camera, and click Reset PoE Power. Wait 2 minutes, then re-run."
            }) | Out-Null
            $s++
        }
        foreach ($c in $noPingMain) {
            $sync.NextSteps.Add(@{
                H = "$s. PoE reset $($c.IP)"
                B = "Camera is not responding to ping. In VPU Manager go to Settings > Cameras, select this camera, and click Reset PoE Power. Wait 2 minutes, then re-run. If unresponsive after 2 resets, check that the cable is firmly seated and the camera is powered on."
            }) | Out-Null
            $s++
        }
        foreach ($issue in $sync.AppIssues) {
            if ($issue -like "*cable ruled out*") {
                $ip = if ($issue -match '(\d+\.\d+\.\d+\.\d+)') { $Matches[1] } else { "camera" }
                $camLabel = ($CameraIPs | Where-Object { $_.IP -eq $ip } | Select-Object -First 1).Label
                $tag = if ($camLabel) { "$ip ($camLabel)" } else { $ip }
                $sync.NextSteps.Add(@{
                    H = "$s. Camera issue on $tag"
                    B = "Cable and NIC port are healthy (1 Gbps confirmed). The camera is not completing the VPU handshake. Start with a PoE reset in VPU Manager (Settings > Cameras > Reset PoE Power). Wait 2 minutes and re-run. If failures continue after 2 resets, the camera likely needs replacement."
                }) | Out-Null
                $s++
            }
        }
        if ($failPorts.Count -gt 0 -and ($rtspFaults.Count -gt 0 -or $noPingMain.Count -gt 0 -or $sync.AppIssues.Count -gt 0)) {
            $sync.NextSteps.Add(@{
                H = "$s. Re-run after each fix"
                B = "Fix one issue at a time and re-run the full diagnostic to confirm each fix before moving on."
            }) | Out-Null
        }
    }
    $sync.StepsDone["NextSteps"] = "pass"
    Add-Summary "─────────────────" "Complete" "Cyan"

    $sync.LastRunLine = if ($allClear) { "All tests passed - No issues detected" } else { "$($failPorts.Count) port fault(s) detected" }
    Add-Content -Path $OutputFile -Value "`nFull results saved: $OutputFile" -ErrorAction SilentlyContinue
    $sync.CurrentStep = if ($allClear) { "All tests passed. No issues detected." } else { "Diagnostic complete. Review next steps in right panel." }
    $sync.Running = $false
    $sync.Complete = $true
}

# ---------- GUI Helper Functions --------------------------------------------
function New-SidebarButton {
    param([string]$Text, [int]$Y, [bool]$Active = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text; $btn.Size = New-Object System.Drawing.Size(185, 38)
    $btn.Location = New-Object System.Drawing.Point(7, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $ColNavHover
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $btn.Padding = New-Object System.Windows.Forms.Padding(14,0,0,0)
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
    $dotC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColMuted} }
    $valC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColText}  }
    $Card.DotPanel.BackColor   = $dotC
    $Card.ValueLabel.ForeColor = $valC
}

# ---------- Form ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "VPU Cable & NIC Troubleshooter  v$ScriptVersion"
$form.Size = New-Object System.Drawing.Size(1024, 680)
$form.MinimumSize = New-Object System.Drawing.Size(1024, 680)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $ColBg
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# ---- Left Sidebar ----------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Size = New-Object System.Drawing.Size(200, 680); $sidebar.Location = New-Object System.Drawing.Point(0, 0)
$sidebar.BackColor = $ColSidebar; $form.Controls.Add($sidebar)

$lblSideIcon = New-Object System.Windows.Forms.Label
$lblSideIcon.Text = [char]0xF785
$lblSideIcon.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 22)
$lblSideIcon.ForeColor = $ColAccent
$lblSideIcon.Location = New-Object System.Drawing.Point(10, 10); $lblSideIcon.Size = New-Object System.Drawing.Size(40, 46)
$sidebar.Controls.Add($lblSideIcon)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "VPU Cable & NIC`nTroubleshooter"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Location = New-Object System.Drawing.Point(54, 14); $lblTitle.Size = New-Object System.Drawing.Size(134, 42)
$sidebar.Controls.Add($lblTitle)

$sep1 = New-Object System.Windows.Forms.Panel; $sep1.Size = New-Object System.Drawing.Size(176,1)
$sep1.Location = New-Object System.Drawing.Point(12,60); $sep1.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
$sidebar.Controls.Add($sep1)

$navOverview = New-SidebarButton ([char]0x2302 + "  Overview") 68  $true
$navTests    = New-SidebarButton ([char]0x2630 + "  Guide")    110
$navResults  = New-SidebarButton ([char]0x25A6 + "  Results")  152
$navHistory  = New-SidebarButton ([char]0x25F7 + "  History")  194
$navSettings = New-SidebarButton ([char]0x2699 + "  Settings") 236
$sidebar.Controls.AddRange(@($navOverview,$navTests,$navResults,$navHistory,$navSettings))

$sep2 = New-Object System.Windows.Forms.Panel; $sep2.Size = New-Object System.Drawing.Size(176,1)
$sep2.Location = New-Object System.Drawing.Point(12,282); $sep2.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
$sidebar.Controls.Add($sep2)

$lblNicHdr = New-Object System.Windows.Forms.Label; $lblNicHdr.Text = "Selected NIC"
$lblNicHdr.Font = New-Object System.Drawing.Font("Segoe UI",7.5); $lblNicHdr.ForeColor = [System.Drawing.Color]::FromArgb(100,116,139)
$lblNicHdr.Location = New-Object System.Drawing.Point(12,292); $lblNicHdr.AutoSize = $true
$sidebar.Controls.Add($lblNicHdr)

$cboNic = New-Object System.Windows.Forms.ComboBox
$cboNic.Size = New-Object System.Drawing.Size(176,22); $cboNic.Location = New-Object System.Drawing.Point(12,310)
$cboNic.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboNic.BackColor = [System.Drawing.Color]::FromArgb(51,65,85); $cboNic.ForeColor = [System.Drawing.Color]::White
$cboNic.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$sidebar.Controls.Add($cboNic)

$pnlConnDot = New-Object System.Windows.Forms.Panel
$pnlConnDot.Size = New-Object System.Drawing.Size(8, 8); $pnlConnDot.Location = New-Object System.Drawing.Point(12, 337)
$pnlConnDot.BackColor = $ColGreen
$pnlConnDot.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,8,8)), 4))
$sidebar.Controls.Add($pnlConnDot)

$lblConnStatus = New-Object System.Windows.Forms.Label; $lblConnStatus.Text = "Connected"
$lblConnStatus.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lblConnStatus.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
$lblConnStatus.Location = New-Object System.Drawing.Point(24, 334); $lblConnStatus.AutoSize = $true
$sidebar.Controls.Add($lblConnStatus)

$sep3 = New-Object System.Windows.Forms.Panel; $sep3.Size = New-Object System.Drawing.Size(176,1)
$sep3.Location = New-Object System.Drawing.Point(12,352); $sep3.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
$sidebar.Controls.Add($sep3)

$lblQiHdr = New-Object System.Windows.Forms.Label; $lblQiHdr.Text = "Quick Info"
$lblQiHdr.Font = New-Object System.Drawing.Font("Segoe UI",7.5); $lblQiHdr.ForeColor = [System.Drawing.Color]::FromArgb(100,116,139)
$lblQiHdr.Location = New-Object System.Drawing.Point(12,354); $lblQiHdr.AutoSize = $true
$sidebar.Controls.Add($lblQiHdr)

$lblQiOs   = New-Object System.Windows.Forms.Label; $lblQiOs.Text   = "OS: Windows"
$lblQiVpu  = New-Object System.Windows.Forms.Label; $lblQiVpu.Text  = "VPU: $($env:COMPUTERNAME)"
$lblQiUser = New-Object System.Windows.Forms.Label; $lblQiUser.Text = "User: $($env:USERNAME)"
foreach ($pair in @(($lblQiOs,372),($lblQiVpu,390),($lblQiUser,408))) {
    $pair[0].Font = New-Object System.Drawing.Font("Segoe UI",8.5); $pair[0].ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    $pair[0].Location = New-Object System.Drawing.Point(12,$pair[1]); $pair[0].Size = New-Object System.Drawing.Size(176,18)
    $sidebar.Controls.Add($pair[0])
}

$sep4 = New-Object System.Windows.Forms.Panel; $sep4.Size = New-Object System.Drawing.Size(176,1)
$sep4.Location = New-Object System.Drawing.Point(12,434); $sep4.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
$sidebar.Controls.Add($sep4)

$lblVpuHdr = New-Object System.Windows.Forms.Label; $lblVpuHdr.Text = "VPU Model"
$lblVpuHdr.Font = New-Object System.Drawing.Font("Segoe UI",7.5); $lblVpuHdr.ForeColor = [System.Drawing.Color]::FromArgb(100,116,139)
$lblVpuHdr.Location = New-Object System.Drawing.Point(12,443); $lblVpuHdr.AutoSize = $true
$sidebar.Controls.Add($lblVpuHdr)

$lblVpuVal = New-Object System.Windows.Forms.Label; $lblVpuVal.Text = "Detecting..."
$lblVpuVal.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblVpuVal.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
$lblVpuVal.Location = New-Object System.Drawing.Point(12,460); $lblVpuVal.Size = New-Object System.Drawing.Size(176,40)
$sidebar.Controls.Add($lblVpuVal)

# ---- Center Panel ----------------------------------------------------------
$center = New-Object System.Windows.Forms.Panel
$center.Size = New-Object System.Drawing.Size(592,680); $center.Location = New-Object System.Drawing.Point(200,0)
$center.BackColor = $ColBg; $form.Controls.Add($center)

$btnRun = New-Object System.Windows.Forms.Button; $btnRun.Text = "  Run Full Diagnostic"
$btnRun.Size = New-Object System.Drawing.Size(222,38); $btnRun.Location = New-Object System.Drawing.Point(10,12)
$btnRun.BackColor = $ColAccent; $btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRun.FlatAppearance.BorderSize = 0
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$center.Controls.Add($btnRun)
$btnRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,222,38)), 6))

$btnRetest = New-Object System.Windows.Forms.Button; $btnRetest.Text = "Retest Last Step"
$btnRetest.Size = New-Object System.Drawing.Size(150,38); $btnRetest.Location = New-Object System.Drawing.Point(242,12)
$btnRetest.BackColor = [System.Drawing.Color]::FromArgb(226,232,240); $btnRetest.ForeColor = $ColText
$btnRetest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRetest.FlatAppearance.BorderSize = 0
$btnRetest.Font = New-Object System.Drawing.Font("Segoe UI",10)
$btnRetest.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnRetest.Enabled = $false
$center.Controls.Add($btnRetest)
$btnRetest.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,150,38)), 6))

$lblCurStat = New-Object System.Windows.Forms.Label; $lblCurStat.Text = "Current Results"
$lblCurStat.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblCurStat.ForeColor = $ColText
$lblCurStat.Location = New-Object System.Drawing.Point(10,82); $lblCurStat.AutoSize = $true
$center.Controls.Add($lblCurStat)

$lblRunSteps = New-Object System.Windows.Forms.Label
$lblRunSteps.Text = "Runs: Link Speed  •  NIC Status  •  Ping  •  Gateway  •  ARP  •  CHU Detection"
$lblRunSteps.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblRunSteps.ForeColor = $ColMuted
$lblRunSteps.Location = New-Object System.Drawing.Point(10, 54); $lblRunSteps.Size = New-Object System.Drawing.Size(560, 16)
$center.Controls.Add($lblRunSteps)

$lnkClear = New-Object System.Windows.Forms.LinkLabel; $lnkClear.Text = "Clear"
$lnkClear.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lnkClear.LinkColor = $ColMuted
$lnkClear.Location = New-Object System.Drawing.Point(553,84); $lnkClear.AutoSize = $true
$center.Controls.Add($lnkClear)

$cardDefs = @(
    @{Key="LinkSpeed"; Title="Link Speed";    Sub="Expected: 1 Gbps";      X=10;  Y=106; Icon=[char]0xE704}
    @{Key="NicStatus"; Title="NIC Status";    Sub="Intel I210 / 82574L";   X=200; Y=106; Icon=[char]0xE7F4}
    @{Key="PingCHU";   Title="Ping (CHU)";    Sub="Camera head unit";      X=390; Y=106; Icon=[char]0xE701}
    @{Key="Gateway";   Title="Gateway";       Sub="Default route";          X=10;  Y=194; Icon=[char]0xE88E}
    @{Key="ArpEntry";  Title="ARP Entry";     Sub="L2 neighbor table";      X=200; Y=194; Icon=[char]0xE9D5}
    @{Key="ChuDetect"; Title="CHU Detection"; Sub="Camera response";        X=390; Y=194; Icon=[char]0xE722}
)
$cards = @{}
foreach ($cd in $cardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y $cd.Y -Icon $cd.Icon -Sub $cd.Sub
    $cards[$cd.Key] = $c
    $center.Controls.Add($c.Panel)
}

$pnlSummaryCard = New-Object System.Windows.Forms.Panel
$pnlSummaryCard.Size = New-Object System.Drawing.Size(580, 54); $pnlSummaryCard.Location = New-Object System.Drawing.Point(2, 278)
$pnlSummaryCard.BackColor = [System.Drawing.Color]::White
$pnlSummaryCard.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,580,54)), 8))
$pnlSummaryCard.Add_Paint({
    param($s,$e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rr  = New-Object System.Drawing.Rectangle(0,0,579,53)
    $bp  = [GfxHelper]::RoundedRect($rr, 8)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210,218,228), 1)
    $e.Graphics.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
})
$center.Controls.Add($pnlSummaryCard)

$lblLastRun = New-Object System.Windows.Forms.Label; $lblLastRun.Text = "Last Run Summary"
$lblLastRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblLastRun.ForeColor = $ColText
$lblLastRun.Location = New-Object System.Drawing.Point(14,284); $lblLastRun.AutoSize = $true
$center.Controls.Add($lblLastRun)

$lblLastRunVal = New-Object System.Windows.Forms.Label; $lblLastRunVal.Text = "No runs yet"
$lblLastRunVal.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblLastRunVal.ForeColor = $ColMuted
$lblLastRunVal.Location = New-Object System.Drawing.Point(14,304); $lblLastRunVal.Size = New-Object System.Drawing.Size(556,18)
$center.Controls.Add($lblLastRunVal)

$lblLogHdr = New-Object System.Windows.Forms.Label; $lblLogHdr.Text = "Live Log"
$lblLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblLogHdr.ForeColor = $ColText
$lblLogHdr.Location = New-Object System.Drawing.Point(10,329); $lblLogHdr.AutoSize = $true
$center.Controls.Add($lblLogHdr)

$lblStatus = New-Object System.Windows.Forms.Label; $lblStatus.Text = ""
$lblStatus.Font = New-Object System.Drawing.Font("Consolas", 8); $lblStatus.ForeColor = $ColMuted
$lblStatus.Location = New-Object System.Drawing.Point(10, 350); $lblStatus.Size = New-Object System.Drawing.Size(570, 18)
$center.Controls.Add($lblStatus)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Size = New-Object System.Drawing.Size(570,289); $rtbLog.Location = New-Object System.Drawing.Point(10,370)
$rtbLog.BackColor = $ColLogBg; $rtbLog.ForeColor = [System.Drawing.Color]::FromArgb(203,213,225)
$rtbLog.Font = New-Object System.Drawing.Font("Consolas",8); $rtbLog.ReadOnly = $true
$rtbLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$center.Controls.Add($rtbLog)

# ---- Right Panel -----------------------------------------------------------
$rightBorder = New-Object System.Windows.Forms.Panel; $rightBorder.Size = New-Object System.Drawing.Size(1,680)
$rightBorder.Location = New-Object System.Drawing.Point(792,0); $rightBorder.BackColor = $ColBorder
$form.Controls.Add($rightBorder)

$right = New-Object System.Windows.Forms.Panel
$right.Size = New-Object System.Drawing.Size(231,680); $right.Location = New-Object System.Drawing.Point(793,0)
$right.BackColor = [System.Drawing.Color]::White; $form.Controls.Add($right)

$pnlBadge = New-Object System.Windows.Forms.Panel
$pnlBadge.Size = New-Object System.Drawing.Size(90,26); $pnlBadge.Location = New-Object System.Drawing.Point(127,13)
$pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(220,252,231)
$right.Controls.Add($pnlBadge)
$pnlBadge.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,90,26)), 13))

$pnlBadgeDot = New-Object System.Windows.Forms.Panel
$pnlBadgeDot.Size = New-Object System.Drawing.Size(7,7); $pnlBadgeDot.Location = New-Object System.Drawing.Point(11, 9)
$pnlBadgeDot.BackColor = $ColGreen
$pnlBadgeDot.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,7,7)), 3))
$pnlBadge.Controls.Add($pnlBadgeDot)

$lblBadge = New-Object System.Windows.Forms.Label; $lblBadge.Text = "Ready"
$lblBadge.Font = New-Object System.Drawing.Font("Segoe UI Semibold",8.5); $lblBadge.ForeColor = $ColGreen
$lblBadge.Location = New-Object System.Drawing.Point(20,0); $lblBadge.Size = New-Object System.Drawing.Size(68,26)
$lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlBadge.Controls.Add($lblBadge)

# Blue "Next Steps / Guidance" header bar
$pnlNextHdr = New-Object System.Windows.Forms.Panel
$pnlNextHdr.Size = New-Object System.Drawing.Size(231,32); $pnlNextHdr.Location = New-Object System.Drawing.Point(0,50)
$pnlNextHdr.BackColor = $ColAccent
$right.Controls.Add($pnlNextHdr)
$lblNextHdr = New-Object System.Windows.Forms.Label; $lblNextHdr.Text = "Next Steps / Guidance"
$lblNextHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9); $lblNextHdr.ForeColor = [System.Drawing.Color]::White
$lblNextHdr.Location = New-Object System.Drawing.Point(10,6); $lblNextHdr.AutoSize = $true
$pnlNextHdr.Controls.Add($lblNextHdr)

$rtbSteps = New-Object System.Windows.Forms.RichTextBox
$rtbSteps.Size = New-Object System.Drawing.Size(211,296); $rtbSteps.Location = New-Object System.Drawing.Point(10,90)
$rtbSteps.BackColor = [System.Drawing.Color]::White; $rtbSteps.ForeColor = $ColText
$rtbSteps.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $rtbSteps.ReadOnly = $true
$rtbSteps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbSteps.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbSteps.Text = "Run the diagnostic to`nsee guidance here."
$right.Controls.Add($rtbSteps)

$sep5 = New-Object System.Windows.Forms.Panel; $sep5.Size = New-Object System.Drawing.Size(211,1)
$sep5.Location = New-Object System.Drawing.Point(10,398); $sep5.BackColor = $ColBorder
$right.Controls.Add($sep5)

$lblHwHdr = New-Object System.Windows.Forms.Label; $lblHwHdr.Text = "Detected Hardware"
$lblHwHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblHwHdr.ForeColor = $ColText
$lblHwHdr.Location = New-Object System.Drawing.Point(10,408); $lblHwHdr.AutoSize = $true
$right.Controls.Add($lblHwHdr)

$hwRows = @{}
foreach ($pair in @(("CHU","CHU",430),("CameraPort","Camera Port",450),("CableStatus","Cable Status",470))) {
    $lk = New-Object System.Windows.Forms.Label; $lk.Text = $pair[1]
    $lk.Font = New-Object System.Drawing.Font("Segoe UI",7.5); $lk.ForeColor = $ColMuted
    $lk.Location = New-Object System.Drawing.Point(10,$pair[2]); $lk.Size = New-Object System.Drawing.Size(85,16)
    $lv = New-Object System.Windows.Forms.Label; $lv.Text = "--"
    $lv.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lv.ForeColor = $ColText
    $lv.Location = New-Object System.Drawing.Point(95,$pair[2]); $lv.Size = New-Object System.Drawing.Size(126,16)
    $right.Controls.Add($lk); $right.Controls.Add($lv)
    $hwRows[$pair[0]] = $lv
}

$sep6 = New-Object System.Windows.Forms.Panel; $sep6.Size = New-Object System.Drawing.Size(211,1)
$sep6.Location = New-Object System.Drawing.Point(10,498); $sep6.BackColor = $ColBorder
$right.Controls.Add($sep6)

$lblActHdr = New-Object System.Windows.Forms.Label; $lblActHdr.Text = "Actions"
$lblActHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblActHdr.ForeColor = $ColText
$lblActHdr.Location = New-Object System.Drawing.Point(10,506); $lblActHdr.AutoSize = $true
$right.Controls.Add($lblActHdr)

foreach ($pair in @(("btnExport","Export Report",530),("btnCopy","Copy Results",566),("btnSave","Save Log",602))) {
    $b = New-Object System.Windows.Forms.Button; $b.Text = $pair[1]
    $b.Size = New-Object System.Drawing.Size(211,30); $b.Location = New-Object System.Drawing.Point(10,$pair[2])
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $ColBorder; $b.FlatAppearance.BorderSize = 1
    $b.BackColor = [System.Drawing.Color]::White; $b.ForeColor = $ColText
    $b.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $right.Controls.Add($b)
    $b.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,211,30)), 5))
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

    $hwRows["CHU"].Text         = $sync.Hardware.CHU
    $hwRows["CameraPort"].Text  = $sync.Hardware.CameraPort
    $hwRows["CableStatus"].Text = $sync.Hardware.CableStatus
    $hwRows["CHU"].ForeColor        = if ($sync.Hardware.CHU -ne "--" -and $sync.Hardware.CHU -ne "") { $ColText } else { $ColMuted }
    $hwRows["CameraPort"].ForeColor = switch -Wildcard ($sync.Hardware.CameraPort) { "Responding" {$ColGreen} "No Response" {$ColRed} default {$ColMuted} }
    $hwRows["CableStatus"].ForeColor= switch -Wildcard ($sync.Hardware.CableStatus) { "OK*" {$ColGreen} "Degraded" {$ColRed} default {$ColMuted} }

    if ($sync.Running) {
        $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(219,234,254)
        $lblBadge.ForeColor = $ColAccent; $lblBadge.Text = "Running"
        $pnlBadgeDot.BackColor = $ColAccent
    }

    if ($sync.Complete -and -not $sync.Running) {
        $timer.Stop()
        $btnRun.Enabled = $true; $btnRun.Text = ([char]0x25B6 + "  Run Full Diagnostic")
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

        $rtbSteps.Clear()
        $firstItem = $true
        foreach ($step in $sync.NextSteps) {
            if (-not $firstItem) {
                $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
                $rtbSteps.SelectionFont  = New-Object System.Drawing.Font("Segoe UI",4)
                $rtbSteps.SelectionColor = [System.Drawing.Color]::White
                $rtbSteps.AppendText("`n")
            }
            $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
            $rtbSteps.SelectionFont  = New-Object System.Drawing.Font("Segoe UI Semibold",9)
            $rtbSteps.SelectionColor = $ColAccent
            $rtbSteps.AppendText("$($step.H)`n")
            $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
            $rtbSteps.SelectionFont  = New-Object System.Drawing.Font("Segoe UI",8.5)
            $rtbSteps.SelectionColor = $ColMuted
            $rtbSteps.AppendText("$($step.B)`n")
            $firstItem = $false
        }

        $dt = Get-Date -Format "yyyy-MM-dd HH:mm"
        $lblLastRunVal.Text = "$($sync.LastRunLine)   $dt"
    }
})

# ---------- Button Handlers -------------------------------------------------
$btnRun.Add_Click({
    if ($sync.Running) { return }

    $newRunId  = Get-Date -Format "yyyyMMdd_HHmmss"
    $newOutput = Join-Path $OutputDir "CameraLink_Results_$newRunId.txt"
    $sync.Running = $false; $sync.Complete = $false; $sync.AllClear = $false
    $sync.PortResults.Clear(); $sync.CamResults.Clear()
    $sync.AppIssues.Clear();   $sync.NextSteps.Clear()
    $sync.TotalDowngrades = 0; $sync.LastRunLine = ""; $sync.VpuModel = ""
    $sync.Cancelled = $false; $sync.CurrentStep = "Starting..."
    $sync.OutputFile = $newOutput; $sync.RunId = $newRunId
    $sync.Hardware = @{ CHU="--"; CameraPort="--"; CableStatus="--" }
    foreach ($k in $cards.Keys) { $sync.Cards[$k] = @{ Value="--"; Status="neutral" } }
    $sync.StepsDone.Clear()
    $item2 = $null; while ($sync.SummaryQueue.TryDequeue([ref]$item2)) { }

    $rtbLog.Clear(); $rtbSteps.Text = "Diagnostic running..."
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
    }) | Out-Null
    $ps.BeginInvoke() | Out-Null
    $timer.Start()
})

$btnRetest.Add_Click({ $btnRun.PerformClick() })

$btnExport.Add_Click({
    if ($sync.OutputFile -and (Test-Path $sync.OutputFile)) {
        Start-Process notepad.exe $sync.OutputFile
    } else {
        [System.Windows.Forms.MessageBox]::Show("Run the diagnostic first.", "Export Report", "OK", "Information") | Out-Null
    }
})

$btnCopy.Add_Click({
    if ($rtbLog.TextLength -gt 0) {
        [System.Windows.Forms.Clipboard]::SetText($rtbLog.Text)
        [System.Windows.Forms.MessageBox]::Show("Log copied to clipboard.", "Copy Results", "OK", "Information") | Out-Null
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

# ---- Guide Panel (Fault Isolation Wizard) ----------------------------------
$pnlGuide = New-Object System.Windows.Forms.Panel
$pnlGuide.Size = $center.Size; $pnlGuide.Location = $center.Location
$pnlGuide.BackColor = $ColBg; $pnlGuide.Visible = $false
$form.Controls.Add($pnlGuide)

# Title
$lblGuideTitle = New-Object System.Windows.Forms.Label
$lblGuideTitle.Text = "Fault Isolation Guide"
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
$pnlGuideInstr.Size = New-Object System.Drawing.Size(572, 108)
$pnlGuideInstr.Location = New-Object System.Drawing.Point(10, 100)
$pnlGuideInstr.BackColor = $ColAccent
$pnlGuide.Controls.Add($pnlGuideInstr)
$pnlGuideInstr.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,572,108)), 8))

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
$btnGuideAction.Size = New-Object System.Drawing.Size(572, 40); $btnGuideAction.Location = New-Object System.Drawing.Point(10, 250)
$btnGuideAction.BackColor = $ColAccent; $btnGuideAction.ForeColor = [System.Drawing.Color]::White
$btnGuideAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGuideAction.FlatAppearance.BorderSize = 0
$btnGuideAction.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnGuideAction.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGuideAction.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,572,40)), 6))
$pnlGuide.Controls.Add($btnGuideAction)

# Result card (hidden until a check completes)
$pnlGuideResult = New-Object System.Windows.Forms.Panel
$pnlGuideResult.Size = New-Object System.Drawing.Size(572, 84)
$pnlGuideResult.Location = New-Object System.Drawing.Point(10, 302)
$pnlGuideResult.BackColor = [System.Drawing.Color]::White
$pnlGuideResult.Visible = $false
$pnlGuideResult.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,572,84)), 8))
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
$sep7 = New-Object System.Windows.Forms.Panel; $sep7.Size = New-Object System.Drawing.Size(572,1)
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
$rtbGuide.Size = New-Object System.Drawing.Size(572, 220); $rtbGuide.Location = New-Object System.Drawing.Point(10, 430)
$rtbGuide.BackColor = $ColLogBg; $rtbGuide.ForeColor = [System.Drawing.Color]::FromArgb(203,213,225)
$rtbGuide.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $rtbGuide.ReadOnly = $true
$rtbGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbGuide.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbGuide.Text = "Phase results will appear here as you work through each step."
$pnlGuide.Controls.Add($rtbGuide)

# ---- Guide State & Logic ---------------------------------------------------
$script:guide = @{
    Phase        = 0       # 0=setup, 1=baseline done, 2=nic done, 3=cable done, 4=concluded
    SuspectPort  = ""
    TestPort     = ""
    BaseSpeed    = 0
    PhaseHistory = [System.Collections.ArrayList]::new()
}

function Get-GuideLinkSpeed {
    param([string]$PortName, [int]$MaxSeconds = 6)
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
    $phase = $script:guide.Phase

    # Phase 0 → run baseline on suspect port
    if ($phase -eq 0) {
        $portName = $cboGuidePortA.Text -replace '\s.*',''
        if (-not $portName) { return }
        $script:guide.SuspectPort = $portName

        $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
        $rtbGuide.Clear()
        $speed = Get-GuideLinkSpeed -PortName $portName -MaxSeconds 6
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

        Add-GuideHistory "Phase 1 — Baseline" $config $speedLabel "Degraded link confirmed — beginning isolation." "Fail"
        Show-GuideResult "Baseline: $speedLabel — Degraded link confirmed." "Beginning isolation. Move the SAME cable to a different NIC port." "Fail"
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
        return
    }

    # Phase 1 → check after moving cable+CHU to test port
    if ($phase -eq 1) {
        $testPort = $cboGuidePortB.Text -replace '\s.*',''
        if (-not $testPort) { return }
        $script:guide.TestPort = $testPort

        $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
        $speed = Get-GuideLinkSpeed -PortName $testPort -MaxSeconds 6
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
        return
    }

    # Phase 2 → check after swapping cable
    if ($phase -eq 2) {
        $testPort = $script:guide.TestPort
        $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
        $speed = Get-GuideLinkSpeed -PortName $testPort -MaxSeconds 6
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
        return
    }

    # Phase 3 → check after swapping camera
    if ($phase -eq 3) {
        $testPort = $script:guide.TestPort
        $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
        $speed = Get-GuideLinkSpeed -PortName $testPort -MaxSeconds 6
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
        return
    }

    # Phase 4 (concluded) → jump to Overview and trigger diagnostic
    if ($phase -eq 4) {
        $navOverview.PerformClick()
        $btnRun.PerformClick()
    }
})

$lnkGuideReset.Add_LinkClicked({
    $script:guide.Phase = 0; $script:guide.SuspectPort = ""; $script:guide.TestPort = ""; $script:guide.BaseSpeed = 0
    $rtbGuide.Text = "Phase results will appear here as you work through each step."
    $pnlGuideResult.Visible = $false
    $lblGuidePhase.Text = "SELECT A PORT TO BEGIN"
    $lblGuideInstr.Text = "Select the NIC port that is showing degraded speed (100 Mbps) and click Start."
    $btnGuideAction.Text = "  Start Baseline"; $btnGuideAction.Enabled = $true
    $lblGuidePortA.Visible = $true; $cboGuidePortA.Visible = $true
    $lblGuidePortB.Visible = $false; $cboGuidePortB.Visible = $false
    Update-GuideStepDots -ActivePhase 1
})

# Nav wiring
$navTests.Add_Click({
    $center.Visible    = $false
    $pnlGuide.Visible  = $true
    foreach ($nb in @($navOverview,$navTests,$navResults,$navHistory,$navSettings)) {
        $nb.BackColor = $ColSidebar; $nb.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    }
    $navTests.BackColor = $ColNavActive; $navTests.ForeColor = [System.Drawing.Color]::White
})

$navOverview.Add_Click({
    $pnlGuide.Visible  = $false
    $center.Visible    = $true
    foreach ($nb in @($navOverview,$navTests,$navResults,$navHistory,$navSettings)) {
        $nb.BackColor = $ColSidebar; $nb.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    }
    $navOverview.BackColor = $ColNavActive; $navOverview.ForeColor = [System.Drawing.Color]::White
})

# ---------- Form Load -------------------------------------------------------
$form.Add_Load({
    $cboNic.Items.Add("All Ports") | Out-Null
    try {
        $nics = Get-NetAdapter | Where-Object {
            $d = $_.InterfaceDescription
            ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
        } | Sort-Object Name
        foreach ($n in $nics) {
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
})

$form.Add_FormClosing({
    $timer.Stop(); $sync.Cancelled = $true
    try { if ($script:runspace) { $script:runspace.Close(); $script:runspace.Dispose() } } catch { }
})

[System.Windows.Forms.Application]::Run($form)
