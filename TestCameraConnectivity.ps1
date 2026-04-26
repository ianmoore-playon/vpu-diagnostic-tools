# =============================================================================
#  VPU Cable & NIC Troubleshooter  v3.0
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
$ScriptVersion      = "3.1"
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
    LogQueue   = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
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
        $sync.LogQueue.Enqueue(@{ M = $Message; L = $Level })
        Add-Content -Path $OutputFile -Value $Message -ErrorAction SilentlyContinue
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

    # ── Find NIC ports ────────────────────────────────────────────────────────
    $sync.CurrentStep = "Detecting NIC ports..."
    Add-Log "-- Detecting Camera NIC Ports --" "Cyan"
    Add-Log ""
    $nicPorts = Get-NetAdapter | Where-Object {
        $d = $_.InterfaceDescription
        ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
    } | Sort-Object Name

    if ($nicPorts.Count -eq 0) {
        Add-Log "  [FAIL] No camera NIC adapters found." "Fail"
        Set-Card "NicStatus" "Not Found" "fail"
        $sync.Running = $false; $sync.Complete = $true
        return
    }
    Add-Log ("  Found {0} camera NIC port(s):" -f $nicPorts.Count) "Info"
    foreach ($n in $nicPorts) { Add-Log ("    - {0}  ({1})" -f $n.Name, $n.InterfaceDescription) "Info" }
    Add-Log ""

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
        } elseif ($spd -eq 100) {
            Add-Log "  Speed   : 100 Mbps  [DEGRADED]" "Fail"
            if (-not $ssHistory.ContainsKey($nic.InterfaceDescription)) {
                Add-Log "  [PASS]  No SmartSpeed history - 100 Mbps-only device (OCR camera). Skipping remediation." "Pass"
                $ocrAdapters[$nic.InterfaceDescription] = $true
                $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
            } else {
                Add-Log "  [ACTION] SmartSpeed history confirmed - attempting to force 1 Gbps..." "Warn"
                $sync.CurrentStep = "Forcing 1 Gbps on $nm..."
                $forceOk = Set-AdapterSpeedDuplex -AdapterName $nm -Val "6"
                if ($forceOk) {
                    Add-Log ("  [INFO]  Waiting {0}s for re-negotiation..." -f $RenegotiateWaitSec) "Warn"
                    $sync.CurrentStep = "Waiting ${RenegotiateWaitSec}s for re-negotiation on $nm..."
                    Start-Sleep -Seconds $RenegotiateWaitSec
                    $newSpd = Get-AdapterSpeedMbps -AdapterName $nm
                    if ($newSpd -eq 1000) {
                        Add-Log "  [PASS]  Forced to 1 Gbps successfully." "Pass"
                        $portResults += [PSCustomObject]@{ Name=$nm; Speed=1000; Result="PASS (forced)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    } else {
                        $nsLabel = if ($newSpd -eq 0) { "Disconnected" } else { "$newSpd Mbps" }
                        Add-Log ("  [FAIL]  Still not 1 Gbps after forcing (current: {0}). Physical layer issue." -f $nsLabel) "Fail"
                        Add-Log "          Resetting to Auto Negotiation..." "Warn"
                        Set-AdapterSpeedDuplex -AdapterName $nm -Val "0" | Out-Null
                        Start-Sleep -Seconds 5
                        $autoSpd = Get-AdapterSpeedMbps -AdapterName $nm
                        if ($autoSpd -gt 0) { Add-Log ("  [INFO]  Link restored at {0} Mbps" -f $autoSpd) "Warn" }
                        $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="FAIL"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                        $anyFail = $true
                    }
                } else {
                    Add-Log "  [FAIL]  Could not apply SpeedDuplex setting." "Fail"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="FAIL"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    $anyFail = $true
                }
            }
        } elseif ($spd -eq 0) {
            Add-Log "  Speed   : No link - no cable or device powered off." "Gray"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=0; Result="NO LINK"; Blinking=$false; Desc=$nic.InterfaceDescription }
        } else {
            Add-Log ("  Speed   : {0} Mbps - unexpected" -f $spd) "Warn"
            $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="UNKNOWN"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
        }
        Add-Log ""
    }

    if ($anyFail)           { Set-Card "LinkSpeed" "100 Mbps" "fail";    Set-Card "NicStatus" "Degraded" "fail" }
    elseif ($bestSpeed -eq 1000) { Set-Card "LinkSpeed" "1 Gbps"  "ok"; Set-Card "NicStatus" "Up"       "ok"   }
    elseif ($bestSpeed -eq 0)    { Set-Card "LinkSpeed" "No Link" "neutral"; Set-Card "NicStatus" "Down" "fail" }
    else                         { Set-Card "LinkSpeed" "$bestSpeed Mbps" "warn"; Set-Card "NicStatus" "Partial" "warn" }

    foreach ($r in $portResults) { $sync.PortResults.Add($r) | Out-Null }

    # ── SmartSpeed event display ──────────────────────────────────────────────
    $sync.CurrentStep = "Processing SmartSpeed events..."
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
        Add-Log ("  [WARN] {0} downgrade(s) and {1} link warning(s) on CHU ports in the last {2}h." -f $dCnt, $wCnt, $EventLogHours) "Fail"
        Add-Log ""
        foreach ($evt in ($chuEvents | Sort-Object @{Expression='TimeCreated';Descending=$true} | Select-Object -First 10)) {
            $an = Get-EventAdapterName -Evt $evt -KnownDescs $knownDescs
            $shortName = if ($an -match '#(\d+)') { "CHU NIC #$($Matches[1])" } else { $an }
            $label = switch ($evt.Id) { 40 {"SmartSpeed Downgrade"} 33 {"Link at 100 Mbps"} 27 {"Link Warning"} default {"Event $($evt.Id)"} }
            Add-Log ("  {0}  {1}  ID {2} - {3}" -f $evt.TimeCreated.ToString("HH:mm:ss"), $shortName, $evt.Id, $label) "Warn"
        }
        Add-Log ""
        Add-Log "  -> Physical layer limitation confirmed. Likely cause: faulty cable or bad termination." "Info"
    } else {
        Add-Log "  [PASS] No SmartSpeed downgrade events on CHU ports." "Pass"
    }
    Add-Log ""

    # ── Gateway check ─────────────────────────────────────────────────────────
    $sync.CurrentStep = "Checking gateway..."
    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
           Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) {
        if (Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            Set-Card "Gateway" "Reachable" "ok";    Add-Log ("  [PASS] Gateway {0} reachable." -f $gw) "Pass"
        } else {
            Set-Card "Gateway" "Unreachable" "fail"; Add-Log ("  [WARN] Gateway {0} not responding." -f $gw) "Warn"
        }
    } else {
        Set-Card "Gateway" "No Route" "neutral"; Add-Log "  [INFO] No default gateway configured." "Gray"
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
    } else {
        Set-Card "ArpEntry" "Not Found" "neutral"
        Add-Log "  [INFO] No ARP entries found in camera subnet." "Gray"
    }
    Add-Log ""

    # ── Camera connectivity ───────────────────────────────────────────────────
    $sync.CurrentStep = "Testing camera connectivity..."
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
        } else {
            $note = if ($cam.Optional) { " (expected - optional camera not installed)" } else { "" }
            Add-Log ("  Ping    : No response$note") "Gray"
            Add-Log "  RTSP 554: Skipped" "Gray"
        }
        if (-not $cam.Optional) { $mainTotal++ }
        $camResults += [PSCustomObject]@{ IP=$cam.IP; Label=$cam.Label; Ping=$pingOk; Rtsp=$rtspOk; Optional=$cam.Optional }
        Add-Log ""
    }

    foreach ($r in $camResults) { $sync.CamResults.Add($r) | Out-Null }

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
                    if ($portResult -and $portResult.Result -eq "FAIL") {
                        Add-Log "  [CONFIRM] NIC port DEGRADED - app failures corroborate physical fault." "Fail"
                        $sync.AppIssues.Add("$ip ($model): app failures + NIC degraded = CONFIRMED physical fault") | Out-Null
                    } elseif ($portResult -and $portResult.Result -like "PASS*") {
                        Add-Log "  [NOTE]    NIC port OK (1 Gbps) - fault is at the camera level, not the cable." "Warn"
                        $sync.AppIssues.Add("$ip ($model): app failures but NIC OK - check camera hardware/config") | Out-Null
                    } else {
                        $sync.AppIssues.Add("$ip ($model): $fails app failure(s)") | Out-Null
                    }
                } elseif ($optAbsent) {
                    Add-Log "  Status    : Expected - optional camera (OCR) not installed on this unit." "Gray"
                } else {
                    Add-Log "  Status    : Connected successfully - no application-level failures." "Pass"
                }
                Add-Log ""
            }
        }
    } else {
        Add-Log "  No CamerasTester log found in Pixellot log paths." "Gray"
        Add-Log ""
    }

    # ── Build Next Steps ──────────────────────────────────────────────────────
    $failPorts  = $portResults | Where-Object { $_.Result -eq "FAIL" }
    $rtspFaults = $camResults  | Where-Object { $_.Ping -and -not $_.Rtsp }
    $allClear   = ($failPorts.Count -eq 0) -and ($rtspFaults.Count -eq 0) -and
                  ($sync.TotalDowngrades -eq 0) -and ($sync.AppIssues.Count -eq 0)
    $sync.AllClear = $allClear

    if ($allClear) {
        $sync.NextSteps.Add("All tests passed.") | Out-Null
        $sync.NextSteps.Add("No action required.") | Out-Null
    } else {
        $s = 1
        foreach ($r in $failPorts) {
            $bNote = if ($r.Blinking) { " (blinking port)" } else { "" }
            $sync.NextSteps.Add("$s. Replace cable on $($r.Name)$bNote") | Out-Null
            $sync.NextSteps.Add("   Gigabit needs all 4 wire pairs (8 wires).") | Out-Null
            $sync.NextSteps.Add("   Check brown/white-brown pair in crimp.") | Out-Null
            $sync.NextSteps.Add("   Inspect camera-side RJ45 port for damage.") | Out-Null
            $sync.NextSteps.Add("   Re-run after replacement to confirm 1 Gbps.") | Out-Null
            $s++
        }
        foreach ($c in $rtspFaults) {
            $sync.NextSteps.Add("$s. PoE reset $($c.IP) ($($c.Label))") | Out-Null
            $sync.NextSteps.Add("   Camera reachable but RTSP port 554 closed.") | Out-Null
            $sync.NextSteps.Add("   Reset power-cycles camera via VPU Manager.") | Out-Null
            $sync.NextSteps.Add("   If still closed after reset - replace camera.") | Out-Null
            $s++
        }
        foreach ($issue in $sync.AppIssues) {
            if ($issue -like "*but NIC OK*") {
                $ip = if ($issue -match '(\d+\.\d+\.\d+\.\d+)') { $Matches[1] } else { "camera" }
                $camLabel = ($CameraIPs | Where-Object { $_.IP -eq $ip } | Select-Object -First 1).Label
                $tag = if ($camLabel) { "$ip ($camLabel)" } else { $ip }
                $sync.NextSteps.Add("$s. Monitor $tag for app failures") | Out-Null
                $sync.NextSteps.Add("   NIC port is OK - cable is not the issue.") | Out-Null
                $sync.NextSteps.Add("   PoE reset in VPU Manager if failures repeat.") | Out-Null
                $sync.NextSteps.Add("   Persistent failures indicate camera fault.") | Out-Null
                $s++
            }
        }
        if ($failPorts.Count -gt 0) {
            $sync.NextSteps.Add("$s. Re-run tool after cable replacement") | Out-Null
            $sync.NextSteps.Add("   Confirm 1 Gbps and SmartSpeed events stop.") | Out-Null
        }
    }

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
    param([string]$Title, [int]$X, [int]$Y, [int]$W=178, [int]$H=78)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($W, $H); $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.BackColor = $ColCard; $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None

    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = $Title
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lbl.ForeColor = $ColMuted
    $lbl.Location = New-Object System.Drawing.Point(10, 10); $lbl.AutoSize = $true
    $panel.Controls.Add($lbl)

    $val = New-Object System.Windows.Forms.Label; $val.Text = "--"
    $val.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
    $val.ForeColor = $ColText; $val.Location = New-Object System.Drawing.Point(10, 28)
    $val.Size = New-Object System.Drawing.Size($W - 20, 34)
    $panel.Controls.Add($val)

    $dot = New-Object System.Windows.Forms.Panel; $dot.Size = New-Object System.Drawing.Size(10, 10)
    $dot.Location = New-Object System.Drawing.Point($W - 18, 10); $dot.BackColor = $ColMuted
    $panel.Controls.Add($dot)

    return @{ Panel=$panel; ValueLabel=$val; DotPanel=$dot }
}

function Update-CardStatus {
    param($Card, [string]$Value, [string]$Status)
    $Card.ValueLabel.Text = $Value
    $dotC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColMuted} }
    $valC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColText}  }
    $Card.DotPanel.BackColor   = $dotC
    $Card.ValueLabel.ForeColor = $valC
}

function Append-RtbLog {
    param($Rtb, [string]$Text, [string]$Level)
    $color = switch ($Level) {
        "Pass"  { [System.Drawing.Color]::FromArgb(74, 222,128) }
        "Fail"  { [System.Drawing.Color]::FromArgb(252,165,165) }
        "Warn"  { [System.Drawing.Color]::FromArgb(253,224, 71) }
        "Cyan"  { [System.Drawing.Color]::FromArgb(103,232,249) }
        "Gray"  { [System.Drawing.Color]::FromArgb(100,116,139) }
        default { [System.Drawing.Color]::FromArgb(203,213,225) }
    }
    $Rtb.SelectionStart = $Rtb.TextLength; $Rtb.SelectionLength = 0
    $Rtb.SelectionColor = $color; $Rtb.AppendText("$Text`n")
    $Rtb.ScrollToCaret()
}

# ---------- Form ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "VPU Cable & NIC Troubleshooter"
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

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "VPU Cable & NIC`nTroubleshooter"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Location = New-Object System.Drawing.Point(12, 14); $lblTitle.Size = New-Object System.Drawing.Size(176, 42)
$sidebar.Controls.Add($lblTitle)

$sep1 = New-Object System.Windows.Forms.Panel; $sep1.Size = New-Object System.Drawing.Size(176,1)
$sep1.Location = New-Object System.Drawing.Point(12,60); $sep1.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
$sidebar.Controls.Add($sep1)

$navOverview = New-SidebarButton "  Overview" 68  $true
$navTests    = New-SidebarButton "  Tests"    110
$navResults  = New-SidebarButton "  Results"  152
$navHistory  = New-SidebarButton "  History"  194
$navSettings = New-SidebarButton "  Settings" 236
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

$sep3 = New-Object System.Windows.Forms.Panel; $sep3.Size = New-Object System.Drawing.Size(176,1)
$sep3.Location = New-Object System.Drawing.Point(12,344); $sep3.BackColor = [System.Drawing.Color]::FromArgb(51,65,85)
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

$btnRetest = New-Object System.Windows.Forms.Button; $btnRetest.Text = "Retest Last Step"
$btnRetest.Size = New-Object System.Drawing.Size(150,38); $btnRetest.Location = New-Object System.Drawing.Point(242,12)
$btnRetest.BackColor = [System.Drawing.Color]::FromArgb(226,232,240); $btnRetest.ForeColor = $ColText
$btnRetest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRetest.FlatAppearance.BorderSize = 0
$btnRetest.Font = New-Object System.Drawing.Font("Segoe UI",10)
$btnRetest.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnRetest.Enabled = $false
$center.Controls.Add($btnRetest)

$lblStep = New-Object System.Windows.Forms.Label
$lblStep.Text = "Run: Link Speed > NIC Status > Ping > Gateway > ARP > CHU Detection"
$lblStep.Font = New-Object System.Drawing.Font("Segoe UI",7.5); $lblStep.ForeColor = $ColMuted
$lblStep.Location = New-Object System.Drawing.Point(10,58); $lblStep.Size = New-Object System.Drawing.Size(568,18)
$center.Controls.Add($lblStep)

$lblCurStat = New-Object System.Windows.Forms.Label; $lblCurStat.Text = "Current Status"
$lblCurStat.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblCurStat.ForeColor = $ColText
$lblCurStat.Location = New-Object System.Drawing.Point(10,82); $lblCurStat.AutoSize = $true
$center.Controls.Add($lblCurStat)

$lnkClear = New-Object System.Windows.Forms.LinkLabel; $lnkClear.Text = "Clear"
$lnkClear.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lnkClear.LinkColor = $ColMuted
$lnkClear.Location = New-Object System.Drawing.Point(553,84); $lnkClear.AutoSize = $true
$center.Controls.Add($lnkClear)

$cardDefs = @(
    @{Key="LinkSpeed"; Title="Link Speed";    X=10;  Y=106}
    @{Key="NicStatus"; Title="NIC Status";    X=200; Y=106}
    @{Key="PingCHU";   Title="Ping (CHU)";    X=390; Y=106}
    @{Key="Gateway";   Title="Gateway";        X=10;  Y=194}
    @{Key="ArpEntry";  Title="ARP Entry";      X=200; Y=194}
    @{Key="ChuDetect"; Title="CHU Detection";  X=390; Y=194}
)
$cards = @{}
foreach ($cd in $cardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y $cd.Y
    $cards[$cd.Key] = $c
    $center.Controls.Add($c.Panel)
}

$lblLastRun = New-Object System.Windows.Forms.Label; $lblLastRun.Text = "Last Run Summary"
$lblLastRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblLastRun.ForeColor = $ColText
$lblLastRun.Location = New-Object System.Drawing.Point(10,284); $lblLastRun.AutoSize = $true
$center.Controls.Add($lblLastRun)

$lblLastRunVal = New-Object System.Windows.Forms.Label; $lblLastRunVal.Text = "No runs yet"
$lblLastRunVal.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblLastRunVal.ForeColor = $ColMuted
$lblLastRunVal.Location = New-Object System.Drawing.Point(10,304); $lblLastRunVal.Size = New-Object System.Drawing.Size(568,18)
$center.Controls.Add($lblLastRunVal)

$lblLogHdr = New-Object System.Windows.Forms.Label; $lblLogHdr.Text = "Live Log"
$lblLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblLogHdr.ForeColor = $ColText
$lblLogHdr.Location = New-Object System.Drawing.Point(10,329); $lblLogHdr.AutoSize = $true
$center.Controls.Add($lblLogHdr)

$rtbLog = New-Object System.Windows.Forms.RichTextBox
$rtbLog.Size = New-Object System.Drawing.Size(570,308); $rtbLog.Location = New-Object System.Drawing.Point(10,350)
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

$lblBadge = New-Object System.Windows.Forms.Label; $lblBadge.Text = "Ready"
$lblBadge.Font = New-Object System.Drawing.Font("Segoe UI Semibold",8.5); $lblBadge.ForeColor = $ColGreen
$lblBadge.Size = New-Object System.Drawing.Size(90,26); $lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$pnlBadge.Controls.Add($lblBadge)

$lblNextHdr = New-Object System.Windows.Forms.Label; $lblNextHdr.Text = "Next Steps / Guidance"
$lblNextHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblNextHdr.ForeColor = $ColText
$lblNextHdr.Location = New-Object System.Drawing.Point(10,50); $lblNextHdr.AutoSize = $true
$right.Controls.Add($lblNextHdr)

$rtbSteps = New-Object System.Windows.Forms.RichTextBox
$rtbSteps.Size = New-Object System.Drawing.Size(211,218); $rtbSteps.Location = New-Object System.Drawing.Point(10,72)
$rtbSteps.BackColor = [System.Drawing.Color]::White; $rtbSteps.ForeColor = $ColText
$rtbSteps.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $rtbSteps.ReadOnly = $true
$rtbSteps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbSteps.Text = "Run the diagnostic to`nsee guidance here."
$right.Controls.Add($rtbSteps)

$sep5 = New-Object System.Windows.Forms.Panel; $sep5.Size = New-Object System.Drawing.Size(211,1)
$sep5.Location = New-Object System.Drawing.Point(10,298); $sep5.BackColor = $ColBorder
$right.Controls.Add($sep5)

$lblHwHdr = New-Object System.Windows.Forms.Label; $lblHwHdr.Text = "Detected Hardware"
$lblHwHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblHwHdr.ForeColor = $ColText
$lblHwHdr.Location = New-Object System.Drawing.Point(10,308); $lblHwHdr.AutoSize = $true
$right.Controls.Add($lblHwHdr)

$hwRows = @{}
foreach ($pair in @(("CHU","CHU",328),("CameraPort","Camera Port",348),("CableStatus","Cable Status",368))) {
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
$sep6.Location = New-Object System.Drawing.Point(10,397); $sep6.BackColor = $ColBorder
$right.Controls.Add($sep6)

$lblActHdr = New-Object System.Windows.Forms.Label; $lblActHdr.Text = "Actions"
$lblActHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",9.5); $lblActHdr.ForeColor = $ColText
$lblActHdr.Location = New-Object System.Drawing.Point(10,407); $lblActHdr.AutoSize = $true
$right.Controls.Add($lblActHdr)

foreach ($pair in @(("btnExport","Export Report",427),("btnCopy","Copy Results",462),("btnSave","Save Log",497))) {
    $b = New-Object System.Windows.Forms.Button; $b.Text = "  $($pair[1])"
    $b.Size = New-Object System.Drawing.Size(211,30); $b.Location = New-Object System.Drawing.Point(10,$pair[2])
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $ColBorder; $b.FlatAppearance.BorderSize = 1
    $b.BackColor = [System.Drawing.Color]::White; $b.ForeColor = $ColText
    $b.Font = New-Object System.Drawing.Font("Segoe UI",9)
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $right.Controls.Add($b)
    Set-Variable -Name $pair[0] -Value $b
}

# ---------- Timer (polls $sync every 300ms, updates UI) ---------------------
$script:runspace = $null

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    $item = $null
    while ($sync.LogQueue.TryDequeue([ref]$item)) {
        Append-RtbLog -Rtb $rtbLog -Text $item.M -Level $item.L
    }

    foreach ($key in $cards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $cards[$key].ValueLabel.Text -ne $sc.Value) {
            Update-CardStatus -Card $cards[$key] -Value $sc.Value -Status $sc.Status
        }
    }

    if ($sync.CurrentStep -and $lblStep.Text -ne $sync.CurrentStep) { $lblStep.Text = $sync.CurrentStep }
    if ($sync.VpuModel   -and $lblVpuVal.Text -ne $sync.VpuModel)   { $lblVpuVal.Text = $sync.VpuModel }

    $hwRows["CHU"].Text         = $sync.Hardware.CHU
    $hwRows["CameraPort"].Text  = $sync.Hardware.CameraPort
    $hwRows["CableStatus"].Text = $sync.Hardware.CableStatus

    if ($sync.Running) {
        $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(219,234,254)
        $lblBadge.ForeColor = $ColAccent; $lblBadge.Text = "Running"
    }

    if ($sync.Complete -and -not $sync.Running) {
        $timer.Stop()
        $btnRun.Enabled = $true; $btnRun.Text = "  Run Full Diagnostic"
        $btnRetest.Enabled = $true

        if ($sync.AllClear) {
            $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(220,252,231)
            $lblBadge.ForeColor = $ColGreen; $lblBadge.Text = "All Clear"
        } else {
            $pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(254,226,226)
            $lblBadge.ForeColor = $ColRed; $lblBadge.Text = "Issues Found"
        }

        $rtbSteps.Clear()
        foreach ($step in $sync.NextSteps) {
            $rtbSteps.SelectionStart = $rtbSteps.TextLength; $rtbSteps.SelectionLength = 0
            if ($step -match '^\d+\.') {
                $rtbSteps.SelectionFont  = New-Object System.Drawing.Font("Segoe UI Semibold",8.5)
                $rtbSteps.SelectionColor = $ColText
            } else {
                $rtbSteps.SelectionFont  = New-Object System.Drawing.Font("Segoe UI",8)
                $rtbSteps.SelectionColor = $ColMuted
            }
            $rtbSteps.AppendText("$step`n")
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

    $rtbLog.Clear(); $rtbSteps.Text = "Diagnostic running..."
    $btnRun.Enabled = $false; $btnRun.Text = "  Running..."
    $btnRetest.Enabled = $false

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

$navTests.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        "Guided Isolation Workflow (Tests A-D)`n`nComing in a future version.`n`nThis mode will walk you step by step through`ncontrolled swaps to pinpoint whether the fault`nis in the cable, NIC port, or camera/CHU port.",
        "Tests - Coming Soon", "OK", "Information") | Out-Null
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
        }
    } catch { }
    if ($cboNic.Items.Count -gt 0) { $cboNic.SelectedIndex = 0 }

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
