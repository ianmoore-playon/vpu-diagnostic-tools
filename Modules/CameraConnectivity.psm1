# =============================================================================
#  CameraConnectivity.psm1  —  Camera diagnostic engine + panel build functions
# =============================================================================

$DiagScript = {
    param($sync, $NicDriverPatterns, $RenegotiateWaitSec, $EventLogHours,
          $PixellotLogPaths, $RtspPort, $OutputFile, $RunId, $ScriptVersion,
          [string]$OcrMacOui = "00-D0-89",
          [string]$FilterNic = "",
          [string]$PoeDllPath = "")

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
    $sync.PoeBudgetLow = $false; $sync.PoeAvailable = $false
    $item = $null
    while ($sync.SummaryQueue.TryDequeue([ref]$item)) { }
    $sync.StepsDone.Clear()

    "" | Set-Content -Path $OutputFile -ErrorAction SilentlyContinue
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # ── VPU model detection ───────────────────────────────────────────────────
    $sync.CurrentStep = "Detecting VPU model..."
    $VpuModel = $null; $VpuUnitId = $null; $VpuType = $null

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

    # ── Camera discovery + ARP ───────────────────────────────────────────────
    Add-Section "Network"
    $sync.CurrentStep = "Discovering cameras..."
    Add-Log "-- Camera Discovery (ARP neighbor table) --" "Cyan"
    Add-Log ""
    $discoveredCameras = @()
    foreach ($nic in $nicPorts) {
        if ($sync.Cancelled) { break }
        $idx = (Get-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue).ifIndex
        if (-not $idx) { continue }
        $neighbors = Get-NetNeighbor -InterfaceIndex $idx -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress  -like "169.254.*" -and
                $_.State      -ne  "Unreachable" -and
                ([Convert]::ToInt32(($_.LinkLayerAddress -split '-')[0], 16) -band 1) -eq 0
            }
        foreach ($nb in $neighbors) {
            if ($discoveredCameras | Where-Object { $_.IP -eq $nb.IPAddress }) { continue }
            $isOcr = $nb.LinkLayerAddress -like "$OcrMacOui-*"
            $discoveredCameras += [PSCustomObject]@{
                IP       = $nb.IPAddress
                MAC      = $nb.LinkLayerAddress
                Label    = if ($isOcr) { "OCR Camera" } else { "S2 Camera" }
                Optional = $isOcr
                NicName  = $nic.Name
            }
            Add-Log ("  Found  : {0,-18} MAC: {1}  Type: {2}" -f $nb.IPAddress, $nb.LinkLayerAddress, (if ($isOcr) { "OCR Camera" } else { "S2 Camera" })) "Info"
        }
    }
    Add-Log ""
    if ($discoveredCameras.Count -gt 0) {
        Set-Card "ArpEntry" "Found" "ok"
        Add-Log ("  [PASS] {0} camera(s) discovered." -f $discoveredCameras.Count) "Pass"
        Add-Summary "ARP Table" "$($discoveredCameras.Count) camera(s) discovered" "Pass"
    } else {
        Set-Card "ArpEntry" "Not Found" "neutral"
        Add-Log "  [INFO] No cameras found in ARP table — cameras may not be powered or not yet communicating." "Gray"
        Add-Summary "ARP Table" "No cameras found" "Gray"
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

    if ($discoveredCameras.Count -eq 0) {
        Add-Log "  [INFO] No cameras discovered — skipping connectivity tests." "Gray"
        Add-Summary "Cameras" "None discovered" "Gray"
        Set-Card "PingCHU"   "No Cameras" "neutral"
        Set-Card "ChuDetect" "Not Found"  "neutral"
        $sync.StepsDone["CamPing"] = "pass"
    } else {
        foreach ($cam in $discoveredCameras) {
            if ($sync.Cancelled) { break }
            $sync.CurrentStep = "Pinging $($cam.IP)..."
            Add-Log ("  {0,-18} {1}  (MAC: {2})" -f $cam.IP, $cam.Label, $cam.MAC) "Info"
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
                $note = if ($cam.Optional) { " (optional)" } else { "" }
                Add-Log ("  Ping    : No response$note") "Gray"
                Add-Log "  RTSP 554: Skipped" "Gray"
                $noteStr = if ($cam.Optional) { "No response (optional)" } else { "No response" }
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
                $camDef  = $discoveredCameras | Where-Object { $_.IP -eq $ip } | Select-Object -First 1
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

    # ── PoE power monitoring ──────────────────────────────────────────────────
    $sync.CurrentStep = "Reading PoE power..."
    Add-Section "PoE Status"
    Add-Log "-- PoE Power Monitoring (ADLINK SmartPoE) --" "Cyan"
    Add-Log ""
    if ($PoeDllPath -and ([System.Management.Automation.PSTypeName]'AdlinkPoE').Type) {
        try {
            $cardNum = [uint16]0
            $regRet  = [AdlinkPoE]::SmartPoE_Register_Card($cardNum)
            if ($regRet -eq 0) {
                $sync.PoeAvailable = $true

                $consumed  = [double]0.0; $remaining = [double]0.0
                [void][AdlinkPoE]::SmartPoE_Get_POEConsPowbudget($cardNum, [ref]$consumed)
                [void][AdlinkPoE]::SmartPoE_Get_POELeftPowbudget($cardNum, [ref]$remaining)
                $total = $consumed + $remaining

                $temp = [double]0.0
                [void][AdlinkPoE]::SmartPoE_Get_Temperature($cardNum, [ref]$temp)

                Add-Log ("  Total Budget : {0:F1} W  (Consumed: {1:F1} W  |  Available: {2:F1} W)" -f $total, $consumed, $remaining) "Info"
                Add-Log ("  NIC Temp     : {0:F1} °C" -f $temp) "Info"
                Add-Log ""

                for ($port = 0; $port -lt 4; $port++) {
                    if ($sync.Cancelled) { break }
                    $pLabel   = "P$($port + 1)"
                    $portNum  = [uint16]$port
                    $voltage  = [double]0.0; $current = [double]0.0
                    [void][AdlinkPoE]::SmartPoE_Get_PSEPortVoltage($cardNum, $portNum, [ref]$voltage)
                    [void][AdlinkPoE]::SmartPoE_Get_PSEPortCurrent($cardNum, $portNum, [ref]$current)
                    $watts    = $voltage * $current
                    $stateStr = if ($voltage -gt 1.0) { "PoE ON" } else { "PoE OFF" }
                    $portLvl  = if ($pgGood -eq 1) { "Pass" } else { "Gray" }
                    Add-Log    ("  {0,-5} : {1:F2} V  {2:F3} A  {3:F1} W  [{4}]" -f $pLabel, $voltage, $current, $watts, $stateStr) $portLvl
                    Add-Summary "PoE $pLabel" ("{0:F1} W  ({1})" -f $watts, $stateStr) $portLvl
                }
                Add-Log ""

                $sync.PoeBudgetLow = ($total -gt 0) -and ($total -lt 55)
                if ($sync.PoeBudgetLow) {
                    Add-Log ("  [WARN]  Total power budget {0:F1} W is below the 55 W minimum." -f $total) "Fail"
                    Add-Log "          The Molex power connector on the PoE NIC may be disconnected." "Fail"
                    Add-Summary "PoE Budget" ("{0:F0} W  LOW" -f $total) "Fail"
                    Set-Card "PoEBudget" ("{0:F0} W" -f $total) "fail"
                } else {
                    Add-Log ("  [PASS]  Total power budget {0:F1} W — adequate." -f $total) "Pass"
                    Add-Summary "PoE Budget" ("{0:F0} W  OK" -f $total) "Pass"
                    Set-Card "PoEBudget" ("{0:F0} W" -f $total) "ok"
                }
                [void][AdlinkPoE]::SmartPoE_Release_Card($cardNum)
            } else {
                Add-Log "  [INFO] SmartPoE_Register_Card returned $regRet — PoE card not detected on this system." "Gray"
                Add-Summary "PoE Budget" "Card not found" "Gray"
            }
        } catch {
            $poeErrType = $_.Exception.GetType().Name
            $poeErrMsg  = $_.Exception.Message -replace "[\r\n]+"," "
            Add-Log ("  [WARN] PoE query failed ({0}): {1}" -f $poeErrType, $poeErrMsg) "Warn"
            if ($_.Exception.InnerException) {
                $inner = $_.Exception.InnerException
                Add-Log ("         Inner: ({0}): {1}" -f $inner.GetType().Name, ($inner.Message -replace "[\r\n]+"," ")) "Warn"
            }
            Add-Summary "PoE Budget" $poeErrType "Warn"
            Set-Card "PoEBudget" "Error" "warn"
        }
    } else {
        Add-Log "  [INFO] SmartPoE.dll not found — PoE monitoring not available on this system." "Gray"
        Add-Summary "PoE Budget" "N/A" "Gray"
    }
    $sync.StepsDone["PoePower"] = "pass"
    Add-Log ""

    # ── Build Next Steps ──────────────────────────────────────────────────────
    $failPorts    = @($portResults | Where-Object { $_.Result -eq "FAIL" })
    $forcedPorts  = @($portResults | Where-Object { $_.Result -eq "PASS (forced)" })
    $uncertainOcr = @($portResults | Where-Object { $_.Result -eq "PASS (OCR?)" })
    $rtspFaults   = @($camResults  | Where-Object { $_.Ping -and -not $_.Rtsp })
    $noPingMain   = @($camResults  | Where-Object { -not $_.Optional -and -not $_.Ping })
    $allClear = ($failPorts.Count -eq 0) -and ($forcedPorts.Count -eq 0) -and
                ($uncertainOcr.Count -eq 0) -and ($rtspFaults.Count -eq 0) -and
                ($sync.AppIssues.Count -eq 0) -and ($noPingMain.Count -eq 0) -and
                (-not $sync.PoeBudgetLow)
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
        if ($sync.PoeBudgetLow) {
            $sync.NextSteps.Add(@{
                H = "$s. Check Molex power connector on PoE NIC"
                B = "Total PoE power budget is below 55 W. The Molex connector that powers the PoE NIC card may be disconnected or loose inside the VPU. Cameras may fail to initialize or drop during streaming. Inspect and firmly reseat the internal Molex connector on the camera NIC card."
            }) | Out-Null
            $s++
        }
        foreach ($issue in $sync.AppIssues) {
            if ($issue -like "*cable ruled out*") {
                $ip = if ($issue -match '(\d+\.\d+\.\d+\.\d+)') { $Matches[1] } else { "camera" }
                $camDef = $discoveredCameras | Where-Object { $_.IP -eq $ip } | Select-Object -First 1
                $tag = if ($camDef) { "$ip ($($camDef.Label))" } else { $ip }
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
