# =============================================================================
#  CameraConnectivity.psm1  -  Camera diagnostic engine, panels, and guide
# =============================================================================

# ---------- Diagnostic engine (runs in background runspace) -----------------
$DiagScript = {
    param($sync, $NicDriverPatterns, $RenegotiateWaitSec, $EventLogHours,
          $PixellotLogPaths, $RtspPort, $OutputFile, $RunId, $ScriptVersion,
          [string]$OcrMacOui = "00-D0-89",
          [string]$FilterNic = "",
          [string]$PoeDllPath = "",
          [bool]$PoeMgmtSupported = $true)

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

    # -- Init ------------------------------------------------------------------
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

    # -- VPU model detection ---------------------------------------------------
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

    # -- Find NIC ports --------------------------------------------------------
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

    # -- SmartSpeed pre-scan ---------------------------------------------------
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

    # -- NIC port link uptime (reuses $events already fetched above) -----------
    $sync.NicLinkUptimes.Clear()
    foreach ($nic in $nicPorts) {
        $lastUp = $null
        foreach ($evt in ($events | Where-Object { $_.Id -in @(27,32) } |
                                    Sort-Object TimeCreated -Descending)) {
            $a = Get-EventAdapterName -Evt $evt -KnownDescs $knownDescs
            if ($a -ne $nic.InterfaceDescription) { continue }
            $msg  = try { $evt.Message } catch { "" }
            $isUp = ($evt.Id -eq 32) -or
                    ($evt.Id -eq 27 -and $msg -match '\d+\s*(Gbps|Mbps)') -or
                    ($evt.Id -eq 27 -and $msg -notmatch '(?i)disconnect|down')
            if ($isUp) { $lastUp = $evt.TimeCreated; break }
        }
        $uptimeStr = if ($lastUp) {
            $span = (Get-Date) - $lastUp
            if     ($span.TotalDays -ge 1)  { "{0}d {1}h" -f [int]$span.TotalDays, $span.Hours }
            elseif ($span.TotalHours -ge 1) { "{0}h {1}m" -f [int]$span.TotalHours, $span.Minutes }
            else                            { "{0}m"       -f [int]$span.TotalMinutes }
        } else { ">48h" }
        $sync.NicLinkUptimes.Add(@{ Name = $nic.Name; Uptime = $uptimeStr }) | Out-Null
    }

    # -- Link speed check ------------------------------------------------------
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
                # Any events (ID 27/33) but no ID 40 ? connected at 100M without ever attempting gigabit ? confirmed OCR.
                # Zero events ? could be OCR or a brand-new cable fault with no prior history yet.
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
                    Add-Log "  [PASS]  Pixellot OCR camera identified ($histNote) - 100 Mbps expected. Skipping remediation." "Pass"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    Set-Card $nm "100 Mbps (OCR)" "ok"
                    Add-Summary $nm "100 Mbps  OCR camera" "Pass"
                } elseif ($hasAnyHistory) {
                    Add-Log "  [PASS]  Link-at-100M events present, no ID 40 - confirmed 100 Mbps-only device (OCR camera). Skipping remediation." "Pass"
                    $portResults += [PSCustomObject]@{ Name=$nm; Speed=100; Result="PASS (OCR)"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                    Set-Card $nm "100 Mbps (OCR)" "ok"
                    Add-Summary $nm "100 Mbps  OCR camera" "Pass"
                } else {
                    Add-Log "  [WARN]  No SmartSpeed history and MAC not yet in ARP cache - likely OCR camera, but cannot rule out new cable fault." "Warn"
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

    # -- SmartSpeed event display ----------------------------------------------
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

    # -- Camera discovery + ARP -----------------------------------------------
    # Discovers cameras dynamically from the ARP/neighbor table on each camera NIC.
    # Filter: link-local (169.254.x.x) + unicast MAC - excludes any non-camera device
    # (e.g. an internet uplink accidentally plugged into a camera port, which gets a
    # DHCP/routable address and will not appear in the 169.254.x.x range).
    # OCR cameras are identified by MAC OUI; all other link-local devices are S2/CHU.
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
        Add-Log "  [INFO] No cameras found in ARP table - cameras may not be powered or not yet communicating." "Gray"
        Add-Summary "ARP Table" "No cameras found" "Gray"
    }
    $sync.StepsDone["ArpGateway"] = "pass"
    Add-Log ""

    # -- Camera connectivity ---------------------------------------------------
    $sync.CurrentStep = "Testing camera connectivity..."
    Add-Section "Cameras"
    Add-Log "-- Camera Connectivity (Ping + RTSP Port 554) --" "Cyan"
    Add-Log ""
    $camResults = @()
    $mainPingCount = 0; $mainTotal = 0

    if ($discoveredCameras.Count -eq 0) {
        Add-Log "  [INFO] No cameras discovered - skipping connectivity tests." "Gray"
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

    # -- Application log analysis ----------------------------------------------
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

    # -- PoE power monitoring --------------------------------------------------
    $sync.CurrentStep = "Reading PoE power..."
    Add-Section "PoE Status"
    Add-Log "-- PoE Power Monitoring (ADLINK SmartPoE) --" "Cyan"
    Add-Log ""
    $sync.PoePortData.Clear()
    if (-not $PoeMgmtSupported) {
        Add-Log "  [INFO] PoE power management not supported on this NIC model (GIE64 / 82574L)." "Gray"
        Add-Summary "PoE Budget" "N/A (GIE64)" "Gray"
        Set-Card "PoEBudget" "N/A" "neutral"
    } elseif ($PoeDllPath -and ([System.Management.Automation.PSTypeName]'AdlinkPoE').Type) {
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
                Add-Log ("  NIC Temp     : {0:F1} ?C" -f $temp) "Info"
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
                    $portLvl  = if ($voltage -gt 1.0) { "Pass" } else { "Gray" }
                    Add-Log    ("  {0,-5} : {1:F2} V  {2:F3} A  {3:F1} W  [{4}]" -f $pLabel, $voltage, $current, $watts, $stateStr) $portLvl
                    Add-Summary "PoE $pLabel" ("{0:F1} W  ({1})" -f $watts, $stateStr) $portLvl
                    $sync.PoePortData.Add(@{ Port=$pLabel; Voltage=$voltage; Current=$current; Watts=$watts; PoeOn=($voltage -gt 1.0) }) | Out-Null
                }
                $sync.PoeConsumed = $consumed; $sync.PoeTotal = $total; $sync.PoeTemp = $temp
                Add-Log ""

                $sync.PoeBudgetLow = ($total -gt 0) -and ($total -lt 55)
                if ($sync.PoeBudgetLow) {
                    Add-Log ("  [WARN]  Total power budget {0:F1} W is below the 55 W minimum." -f $total) "Fail"
                    Add-Log "          The Molex power connector on the PoE NIC may be disconnected." "Fail"
                    Add-Summary "PoE Budget" ("{0:F0} W  LOW" -f $total) "Fail"
                    Set-Card "PoEBudget" ("{0:F0} W" -f $total) "fail"
                } else {
                    Add-Log ("  [PASS]  Total power budget {0:F1} W - adequate." -f $total) "Pass"
                    Add-Summary "PoE Budget" ("{0:F0} W  OK" -f $total) "Pass"
                    Set-Card "PoEBudget" ("{0:F0} W" -f $total) "ok"
                }
                [void][AdlinkPoE]::SmartPoE_Release_Card($cardNum)
            } else {
                Add-Log "  [INFO] SmartPoE_Register_Card returned $regRet - PoE card not detected on this system." "Gray"
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
        Add-Log "  [INFO] SmartPoE.dll not found - PoE monitoring not available on this system." "Gray"
        Add-Summary "PoE Budget" "N/A" "Gray"
    }
    $sync.StepsDone["PoePower"] = "pass"
    Add-Log ""

    # -- Build Next Steps ------------------------------------------------------
    $failPorts    = @($portResults | Where-Object { $_.Result -eq "FAIL" })
    $forcedPorts  = @($portResults | Where-Object { $_.Result -eq "PASS (forced)" })
    $uncertainOcr = @($portResults | Where-Object { $_.Result -eq "PASS (OCR?)" })
    $rtspFaults   = @($camResults  | Where-Object { $_.Ping -and -not $_.Rtsp })
    $noPingMain   = @($camResults  | Where-Object { -not $_.Optional -and -not $_.Ping })
    # allClear only when every active fault category is empty; historical SmartSpeed events on
    # currently-passing ports are informational only and do not block all-clear
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
                H = "$s. Isolate Fault - $($r.Name)$bNote"
                B = "Use the Isolate tab to determine whether the fault is the cable, NIC port, or camera before replacing anything."
            }) | Out-Null
            $s++
        }
        foreach ($r in $forcedPorts) {
            $sync.NextSteps.Add(@{
                H = "$s. Replace cable on $($r.Name) - preventive"
                B = "This port was forced to 1 Gbps and is currently holding, but SmartSpeed history confirms the cable or termination is marginal. Replace the cable before the link degrades again."
            }) | Out-Null
            $s++
        }
        foreach ($r in $uncertainOcr) {
            $sync.NextSteps.Add(@{
                H = "$s. Verify $($r.Name) - OCR camera or new cable fault?"
                B = "This port is at 100 Mbps with no SmartSpeed history. On an established VPU this is an OCR (scoreboard) camera - no action needed. On a new or first-time installation a bad cable also produces no history. If this is a CHU port, use the Isolate tab to test the cable."
            }) | Out-Null
            $s++
        }
        foreach ($c in $rtspFaults) {
            $sync.NextSteps.Add(@{
                H = "$s. PoE reset $($c.IP)"
                B = "RTSP is stalled - reset PoE power in VPU Manager (Settings > Cameras), wait 2 min, then re-run."
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
        if ($PoeMgmtSupported -and $sync.PoeBudgetLow) {
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
                    " Log is from $($sync.AppLogTime.ToString('MM/dd HH:mm')) - if a cable was recently replaced, these failures may be stale; re-run after the VPU reconnects to confirm."
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
    Add-Summary "-----------------" "Complete" "Cyan"

    $sync.LastRunLine = if ($allClear) { "All tests passed - No issues detected" } else { "$($failPorts.Count) port fault(s) detected" }
    Add-Content -Path $OutputFile -Value "`nSTATUS: $(if ($allClear) { 'ALL_CLEAR' } else { 'ISSUES_FOUND' })" -ErrorAction SilentlyContinue
    Add-Content -Path $OutputFile -Value "Full results saved: $OutputFile" -ErrorAction SilentlyContinue
    $sync.CurrentStep = if ($allClear) { "All tests passed. No issues detected." } else { "Diagnostic complete. Review next steps in right panel." }
    $sync.Running = $false
    $sync.Complete = $true
}


# ---- Camera Connectivity (was "Center Panel") ------------------------------
$center = New-Object System.Windows.Forms.Panel
$center.Size      = New-Object System.Drawing.Size($NarrowW, $ContentH)
$center.Location  = New-Object System.Drawing.Point($SideW, $ContentY)
$center.BackColor = $ColBg
$center.Anchor    = $AnchorTLRB
$center.Visible   = $false
$form.Controls.Add($center)

# NIC scope selector (moved from sidebar into camera panel)
$lblNicHdr = New-Object System.Windows.Forms.Label
$lblNicHdr.Text      = "Test Scope"
$lblNicHdr.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblNicHdr.ForeColor = $ColMuted
$lblNicHdr.Location  = New-Object System.Drawing.Point(10, 16)
$lblNicHdr.AutoSize  = $true
$center.Controls.Add($lblNicHdr)

$cboNic = New-Object System.Windows.Forms.ComboBox
$cboNic.Size          = New-Object System.Drawing.Size(180, 22)
$cboNic.Location      = New-Object System.Drawing.Point(10, 34)
$cboNic.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboNic.BackColor     = $ColCard
$cboNic.Font          = New-Object System.Drawing.Font("Segoe UI", 8.5)
$center.Controls.Add($cboNic)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text      = [char]0x25B6 + "  Run Full Diagnostic"
$btnRun.Size      = New-Object System.Drawing.Size(270, 40)
$btnRun.Location  = New-Object System.Drawing.Point(200, 14)
$btnRun.BackColor = $ColAccent
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRun.FlatAppearance.BorderSize = 0
$btnRun.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnRun.Cursor    = [System.Windows.Forms.Cursors]::Hand
$center.Controls.Add($btnRun)
$btnRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 270, 40)), 7))

$btnRetest = New-Object System.Windows.Forms.Button
$btnRetest.Text      = "Retest Last Step"
$btnRetest.Size      = New-Object System.Drawing.Size(160, 40)
$btnRetest.Location  = New-Object System.Drawing.Point(478, 14)
$btnRetest.BackColor = $ColNavHover
$btnRetest.ForeColor = $ColText
$btnRetest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRetest.FlatAppearance.BorderSize = 0
$btnRetest.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnRetest.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnRetest.Enabled   = $false
$center.Controls.Add($btnRetest)
$btnRetest.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 160, 40)), 7))

$lblEta = New-Object System.Windows.Forms.Label; $lblEta.Text = "est. ~2 min"
$lblEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblEta.ForeColor = $ColMuted
$lblEta.Location = New-Object System.Drawing.Point(480, 24); $lblEta.AutoSize = $true
$center.Controls.Add($lblEta)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text      = "Cancel"
$btnCancel.Size      = New-Object System.Drawing.Size(110, 40)
$btnCancel.Location  = New-Object System.Drawing.Point(646, 14)
$btnCancel.BackColor = $ColRed
$btnCancel.ForeColor = [System.Drawing.Color]::White
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.FlatAppearance.BorderSize = 0
$btnCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnCancel.Visible   = $false
$center.Controls.Add($btnCancel)
$btnCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 40)), 7))

$lblRunSteps = New-Object System.Windows.Forms.Label
$lblRunSteps.Text      = "Runs: Port Speed  *  Ping  *  ARP  *  CHU Detection"
$lblRunSteps.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblRunSteps.ForeColor = $ColMuted
$lblRunSteps.Location  = New-Object System.Drawing.Point(200, 60)
$lblRunSteps.Size      = New-Object System.Drawing.Size(560, 18)
$center.Controls.Add($lblRunSteps)

$lblNicCardHdr = New-Object System.Windows.Forms.Label
$lblNicCardHdr.Text      = "NIC Card"
$lblNicCardHdr.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblNicCardHdr.ForeColor = $ColMuted
$lblNicCardHdr.Location  = New-Object System.Drawing.Point(780, 16)
$lblNicCardHdr.AutoSize  = $true
$center.Controls.Add($lblNicCardHdr)

$lblNicCardVal = New-Object System.Windows.Forms.Label
$lblNicCardVal.Text      = "Detecting..."
$lblNicCardVal.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblNicCardVal.ForeColor = $ColText
$lblNicCardVal.Location  = New-Object System.Drawing.Point(780, 34)
$lblNicCardVal.AutoSize  = $true
$center.Controls.Add($lblNicCardVal)

$lblCurStat = New-Object System.Windows.Forms.Label; $lblCurStat.Text = "Current Results"
$lblCurStat.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblCurStat.ForeColor = $ColText
$lblCurStat.Location = New-Object System.Drawing.Point(10, 88); $lblCurStat.AutoSize = $true
$center.Controls.Add($lblCurStat)

$lnkClear = New-Object System.Windows.Forms.LinkLabel; $lnkClear.Text = "Clear"
$lnkClear.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lnkClear.LinkColor = $ColMuted
$lnkClear.Location = New-Object System.Drawing.Point(1220, 90); $lnkClear.AutoSize = $true
$center.Controls.Add($lnkClear)

# Fixed bottom-row cards: SmartSpeed, Ping, ARP, CHU, PoE  (244px each, 10px gaps - fills 1260px)
$cardDefs = @(
    @{Key="SmartSpeed"; Title="SmartSpeed";    Sub="Intel events (48h)"; X=10;   Y=204; Icon=[char]0xE7BA; W=244}
    @{Key="PingCHU";    Title="Ping (CHU)";    Sub="Camera head unit";   X=264;  Y=204; Icon=[char]0xE701; W=244}
    @{Key="ArpEntry";   Title="ARP Entry";     Sub="L2 neighbor table";  X=518;  Y=204; Icon=[char]0xE9D5; W=244}
    @{Key="ChuDetect";  Title="CHU Detection"; Sub="Camera response";    X=772;  Y=204; Icon=[char]0xE722; W=244}
    @{Key="PoEBudget";  Title="PoE Budget";    Sub="ADLINK SmartPoE";    X=1026; Y=204; Icon=[char]0xE7E8; W=244}
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
    $portCardW = [int]((1260 - ($numPorts - 1) * 10) / $numPorts)
    $portCardX = 10; $portNum = 1
    foreach ($n in $script:detectedNics) {
        $c = New-StatusCard -Title "P$portNum" -Sub $n.Name -X $portCardX -Y 106 -CardW $portCardW -CardH 90
        $cards[$n.Name] = $c
        $sync.Cards[$n.Name] = @{ Value = "--"; Status = "neutral" }
        $center.Controls.Add($c.Panel)
        # Click a degraded port card ? jump to Guide with that port pre-selected
        $capturedName = $n.Name
        $portClickHandler = {
            $navTests.PerformClick()
            Reset-Guide
            $idx = -1
            for ($i = 0; $i -lt $cboGuidePortA.Items.Count; $i++) {
                if (($cboGuidePortA.Items[$i] -as [string]) -like "$capturedName*") { $idx = $i; break }
            }
            if ($idx -ge 0) { $cboGuidePortA.SelectedIndex = $idx }
        }.GetNewClosure()
        foreach ($ctrl in @($c.Panel) + @($c.Panel.Controls)) {
            $ctrl.Add_Click($portClickHandler)
            $ctrl.Cursor = [System.Windows.Forms.Cursors]::Hand
        }
        $portCardX += $portCardW + 10; $portNum++
    }
}

$pnlSummaryCard = New-Object System.Windows.Forms.Panel
$pnlSummaryCard.Size = New-Object System.Drawing.Size(1260, 56); $pnlSummaryCard.Location = New-Object System.Drawing.Point(10, 304)
$pnlSummaryCard.BackColor = $ColCard
$pnlSummaryCard.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 1260, 56)), 8))
$pnlSummaryCard.Add_Paint({
    $g = $args[1].Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rr  = New-Object System.Drawing.Rectangle(0, 0, 1259, 55)
    $bp  = [GfxHelper]::RoundedRect($rr, 8)
    $pen = New-Object System.Drawing.Pen($ColBorder, 1)
    $g.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
})
$center.Controls.Add($pnlSummaryCard)

$lblLastRun = New-Object System.Windows.Forms.Label; $lblLastRun.Text = "Last Run Summary"
$lblLastRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $lblLastRun.ForeColor = $ColText
$lblLastRun.BackColor = [System.Drawing.Color]::Transparent
$lblLastRun.Location = New-Object System.Drawing.Point(14, 7); $lblLastRun.AutoSize = $true
$pnlSummaryCard.Controls.Add($lblLastRun)

$lblLastRunVal = New-Object System.Windows.Forms.Label; $lblLastRunVal.Text = "No runs yet"
$lblLastRunVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblLastRunVal.ForeColor = $ColMuted
$lblLastRunVal.BackColor = [System.Drawing.Color]::Transparent
$lblLastRunVal.Location = New-Object System.Drawing.Point(14, 28); $lblLastRunVal.Size = New-Object System.Drawing.Size(1230, 18)
$pnlSummaryCard.Controls.Add($lblLastRunVal)

$lblLogHdr = New-Object System.Windows.Forms.Label; $lblLogHdr.Text = "Live Log"
$lblLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblLogHdr.ForeColor = $ColText
$lblLogHdr.Location = New-Object System.Drawing.Point(10, 370); $lblLogHdr.AutoSize = $true
$center.Controls.Add($lblLogHdr)

$btnLogHighlights = New-Object System.Windows.Forms.Button; $btnLogHighlights.Text = "Highlights"
$btnLogHighlights.Size = New-Object System.Drawing.Size(90, 22); $btnLogHighlights.Location = New-Object System.Drawing.Point(1070, 369)
$btnLogHighlights.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnLogHighlights.FlatAppearance.BorderSize = 0
$btnLogHighlights.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
$btnLogHighlights.BackColor = $ColAccent; $btnLogHighlights.ForeColor = [System.Drawing.Color]::White
$btnLogHighlights.Cursor = [System.Windows.Forms.Cursors]::Hand
$center.Controls.Add($btnLogHighlights)
$btnLogHighlights.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,90,22)),4))

$btnLogDetailed = New-Object System.Windows.Forms.Button; $btnLogDetailed.Text = "Detailed"
$btnLogDetailed.Size = New-Object System.Drawing.Size(80, 22); $btnLogDetailed.Location = New-Object System.Drawing.Point(1170, 369)
$btnLogDetailed.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnLogDetailed.FlatAppearance.BorderSize = 0
$btnLogDetailed.Font = New-Object System.Drawing.Font("Segoe UI", 7.5)
$btnLogDetailed.BackColor = $ColNavHover; $btnLogDetailed.ForeColor = $ColMuted
$btnLogDetailed.Cursor = [System.Windows.Forms.Cursors]::Hand
$center.Controls.Add($btnLogDetailed)
$btnLogDetailed.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,80,22)),4))

$lblStatus = New-Object System.Windows.Forms.Label; $lblStatus.Text = ""
$lblStatus.Font = New-Object System.Drawing.Font("Consolas", 8); $lblStatus.ForeColor = $ColMuted
$lblStatus.Location = New-Object System.Drawing.Point(10, 392); $lblStatus.Size = New-Object System.Drawing.Size(1260, 18)
$center.Controls.Add($lblStatus)

$dgvLog = New-LogGrid -X 10 -Y 412 -W 1260 -H 190 -LabelColW 180
$center.Controls.Add($dgvLog)

# ---- Right Panel (Camera Connectivity only) --------------------------------
$rightBorder = New-Object System.Windows.Forms.Panel
$rightBorder.Size      = New-Object System.Drawing.Size(1, $ContentH)
$rightBorder.Location  = New-Object System.Drawing.Point($RightX, $ContentY)
$rightBorder.BackColor = $ColBorder
$rightBorder.Anchor    = $AnchorTRB
$form.Controls.Add($rightBorder)

$right = New-Object System.Windows.Forms.Panel
$right.Size      = New-Object System.Drawing.Size($RightW, $ContentH)
$right.Location  = New-Object System.Drawing.Point(([int]$RightX + 1), $ContentY)
$right.BackColor = $ColCard
$right.Anchor    = $AnchorTRB
$form.Controls.Add($right)

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
$rtbSteps.Size = New-Object System.Drawing.Size(239, 380); $rtbSteps.Location = New-Object System.Drawing.Point(10, 44); $rtbSteps.Anchor = $AnchorTLRB
$rtbSteps.BackColor = $ColCard; $rtbSteps.ForeColor = $ColText
$rtbSteps.Font = New-Object System.Drawing.Font("Segoe UI", 9); $rtbSteps.ReadOnly = $true
$rtbSteps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbSteps.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbSteps.Text = "Run the diagnostic to`nsee guidance here."
$right.Controls.Add($rtbSteps)

$btnGoGuide = New-Object System.Windows.Forms.Button
$btnGoGuide.Text = "Open Fault Isolator  ?"
$btnGoGuide.Size = New-Object System.Drawing.Size(239, 34); $btnGoGuide.Location = New-Object System.Drawing.Point(10, 432)
$btnGoGuide.BackColor = $ColAccent; $btnGoGuide.ForeColor = [System.Drawing.Color]::White
$btnGoGuide.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGoGuide.FlatAppearance.BorderSize = 0
$btnGoGuide.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnGoGuide.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnGoGuide.Visible = $true
$right.Controls.Add($btnGoGuide)
$btnGoGuide.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 239, 34)), 6))

$sepAct = New-Object System.Windows.Forms.Panel; $sepAct.Size = New-Object System.Drawing.Size(239, 1)
$sepAct.Location = New-Object System.Drawing.Point(10, 474); $sepAct.BackColor = $ColBorder
$sepAct.Anchor = $AnchorBLR
$right.Controls.Add($sepAct)

$lblActHdr = New-Object System.Windows.Forms.Label; $lblActHdr.Text = "Actions"
$lblActHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblActHdr.ForeColor = $ColText
$lblActHdr.Location = New-Object System.Drawing.Point(10, 482); $lblActHdr.AutoSize = $true
$lblActHdr.Anchor = $AnchorBL
$right.Controls.Add($lblActHdr)

$btnAdapterSettings = New-Object System.Windows.Forms.Button; $btnAdapterSettings.Text = "Open Adapter Settings"
$btnAdapterSettings.Size = New-Object System.Drawing.Size(239, 28); $btnAdapterSettings.Location = New-Object System.Drawing.Point(10, 504)
$btnAdapterSettings.Anchor = $AnchorBLR
$btnAdapterSettings.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAdapterSettings.FlatAppearance.BorderColor = $ColBorder; $btnAdapterSettings.FlatAppearance.BorderSize = 1
$btnAdapterSettings.BackColor = $ColNavHover; $btnAdapterSettings.ForeColor = $ColText
$btnAdapterSettings.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnAdapterSettings.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btnAdapterSettings.Cursor = [System.Windows.Forms.Cursors]::Hand
$right.Controls.Add($btnAdapterSettings)
$btnAdapterSettings.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 239, 28)), 5))

foreach ($pair in @(("btnExport","Export Report",536),("btnCopySummary","Copy Summary",568),("btnCopy","Copy Log",600),("btnSave","Save Log",632))) {
    $b = New-Object System.Windows.Forms.Button; $b.Text = $pair[1]
    $b.Size = New-Object System.Drawing.Size(239, 28); $b.Location = New-Object System.Drawing.Point(10, $pair[2])
    $b.Anchor = $AnchorBLR
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $ColBorder; $b.FlatAppearance.BorderSize = 1
    $b.BackColor = $ColNavHover; $b.ForeColor = $ColText
    $b.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $right.Controls.Add($b)
    $b.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 239, 28)), 5))
    Set-Variable -Name $pair[0] -Value $b
}

# ---------- Timer (polls $sync every 300ms, updates UI) ---------------------
$script:runspace    = $null
$script:spinIdx     = 0
$script:logMode     = "Highlights"
$script:allLogItems = [System.Collections.ArrayList]::new()

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    $item = $null
    while ($sync.SummaryQueue.TryDequeue([ref]$item)) {
        $script:allLogItems.Add($item) | Out-Null
        if ($script:logMode -eq "Detailed" -or (Test-HighlightItem $item)) {
            Render-LogItem $item
        }
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
    if ($sync.VpuModel -and $sync.VpuModel -ne "" -and -not $lblVpuVal.Text.StartsWith($sync.VpuModel)) { $lblVpuVal.Text = $sync.VpuModel }

    if ($sync.Running) {
        $pnlBadge.BackColor = $ColBadgeRunBg
        $lblBadge.ForeColor = $ColYellow; $lblBadge.Text = "Running"
        $pnlBadgeDot.BackColor = $ColAccent
        $pnlSbarDot.BackColor = $ColAccent
        $lblSbarStatus.Text = "Status: Running"
        $lblSideStatus.Text = "Running..."; $pnlSideDot.BackColor = $ColAccent
        if (-not $btnCancel.Visible) { $btnCancel.Visible = $true }
    }

    if ($sync.UpdateAvailable -and -not $lblUpdate.Visible) {
        $lblUpdate.Text = "Update available: v$($sync.UpdateAvailable)"
        $lblUpdate.Visible = $true; $btnUpdate.Visible = $true
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
            $pnlBadge.BackColor = $ColBadgeOkBg
            $lblBadge.ForeColor = $ColGreen; $lblBadge.Text = "All Clear"
            $pnlBadgeDot.BackColor = $ColGreen
            $pnlSbarDot.BackColor = $ColGreen; $lblSbarStatus.Text = "Status: All Clear"
            $pnlSideDot.BackColor = $ColGreen; $lblSideStatus.Text = "All Clear"
        } else {
            $pnlBadge.BackColor = $ColBadgeErrBg
            $lblBadge.ForeColor = $ColRed; $lblBadge.Text = "Issues Found"
            $pnlBadgeDot.BackColor = $ColRed
            $pnlSbarDot.BackColor = $ColRed; $lblSbarStatus.Text = "Status: Issues Found"
            $pnlSideDot.BackColor = $ColRed; $lblSideStatus.Text = "Issues Found"
        }
        $lblSbarLastRun.Text = "Last Run: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

        Show-OverviewSteps

        $dt = Get-Date -Format "yyyy-MM-dd HH:mm"
        $trend = Get-PortTrendSummary
        $trendSuffix = if ($trend) { "   .   $trend" } else { "" }
        $lblLastRunVal.Text = "$($sync.LastRunLine)   $dt$trendSuffix"
        $btnGoGuide.Visible = $true
        Update-GuidePortDropdown
    }
})

# ---------- Button Handlers -------------------------------------------------
$btnRun.Add_Click({
    if ($sync.Running) { return }

    # Prune log folder - keep the 49 most recent files (new run will be the 50th)
    try {
        $pruneFiles = @(Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -Skip 49)
        $pruneFiles | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }

    $newRunId  = Get-Date -Format "yyyyMMdd_HHmmss"
    $newOutput = Join-Path $OutputDir "Pulse_Results_$newRunId.txt"
    $sync.Running = $false; $sync.Complete = $false; $sync.AllClear = $false
    $sync.PortResults.Clear(); $sync.CamResults.Clear()
    $sync.AppIssues.Clear();   $sync.NextSteps.Clear()
    $sync.TotalDowngrades = 0; $sync.LastRunLine = ""; $sync.VpuModel = ""
    $sync.PoeBudgetLow = $false; $sync.PoeAvailable = $false
    $sync.Cancelled = $false; $sync.CurrentStep = "Starting..."
    $sync.OutputFile = $newOutput; $sync.RunId = $newRunId
    foreach ($k in $cards.Keys) { $sync.Cards[$k] = @{ Value="--"; Status="neutral" } }
    $sync.StepsDone.Clear()
    $item2 = $null; while ($sync.SummaryQueue.TryDequeue([ref]$item2)) { }
    $script:allLogItems.Clear()

    $dgvLog.Rows.Clear(); $rtbSteps.Text = "Diagnostic running..."
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
        RtspPort           = $RtspPort
        OutputFile         = $newOutput
        RunId              = $newRunId
        ScriptVersion      = $ScriptVersion
        OcrMacOui          = $OcrMacOui
        FilterNic          = $filterNicVal
        PoeDllPath         = if ($PoeDllPath) { $PoeDllPath } else { "" }
        PoeMgmtSupported   = if ($script:nicCardInfo) { [bool]$script:nicCardInfo.PoeMgmtSupported } else { $true }
    }) | Out-Null
    $ps.BeginInvoke() | Out-Null
    $timer.Start()
})

$btnRetest.Add_Click({ $btnRun.PerformClick() })

$btnCancel.Add_Click({
    $sync.Cancelled = $true
    $btnCancel.Visible = $false
})

$btnAdapterSettings.Add_Click({ Start-Process "ncpa.cpl" })

$btnUpdate.Add_Click({
    $btnUpdate.Text = "  Launching..."; $btnUpdate.Enabled = $false
    try {
        Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"irm '$ScriptUrl' | iex`""
        $form.Close()
    } catch {
        $btnUpdate.Enabled = $true; $btnUpdate.Text = "  Update Now"
        [System.Windows.Forms.MessageBox]::Show("Could not launch update.`nRe-run the one-liner manually to update.", "Update Failed", "OK", "Warning") | Out-Null
    }
})

$btnLogHighlights.Add_Click({
    $script:logMode = "Highlights"
    $btnLogHighlights.BackColor = $ColAccent;    $btnLogHighlights.ForeColor = [System.Drawing.Color]::White
    $btnLogDetailed.BackColor   = $ColNavHover;  $btnLogDetailed.ForeColor   = $ColMuted
    Refresh-Log
})

$btnLogDetailed.Add_Click({
    $script:logMode = "Detailed"
    $btnLogDetailed.BackColor   = $ColAccent;    $btnLogDetailed.ForeColor   = [System.Drawing.Color]::White
    $btnLogHighlights.BackColor = $ColNavHover;  $btnLogHighlights.ForeColor = $ColMuted
    Refresh-Log
})

$cboNic.Add_SelectedIndexChanged({
    if (-not $sync.Running) {
        if ($cboNic.SelectedIndex -le 0) {
            $btnRun.Text = [char]0x25B6 + "  Run Full Diagnostic"
            $lblRunSteps.Text = "Runs: Port Speed  *  Ping  *  ARP  *  CHU Detection"
        } else {
            $nicName = ($cboNic.SelectedItem -as [string]) -replace '\s+\(.*', ''
            $btnRun.Text = [char]0x25B6 + "  Test $nicName Only"
            $lblRunSteps.Text = "Scope: $nicName only  *  Port Speed  *  Ping  *  ARP  *  CHU Detection"
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
    $lines += "=" * 48
    $lines += "VPU DIAGNOSTIC SUMMARY"
    $lines += "Date:       $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $lines += "Computer:   $($env:COMPUTERNAME)"
    $lines += "VPU Model:  $($sync.VpuModel)"
    $lines += "Run ID:     $($sync.RunId)"
    $lines += ""
    $lines += "RESULT: $(if ($sync.AllClear) { 'ALL CLEAR' } else { 'ISSUES FOUND' })"
    $lines += "=" * 48
    $lines += ""
    $lines += "PORT STATUS"
    foreach ($r in @($sync.PortResults)) {
        $status = switch ($r.Result) {
            "PASS"          { "1 Gbps - OK" }
            "PASS (forced)" { "1 Gbps - OK (forced)" }
            "PASS (OCR)"    { "100 Mbps - OCR camera (expected)" }
            "FAIL"          { "DEGRADED - physical layer fault" }
            "NO LINK"       { "No link" }
            default         { $r.Result }
        }
        $lines += "  $($r.Name.PadRight(16)) $status"
    }
    $lines += ""
    $lines += "SIGNAL QUALITY"
    $ssLine = if ($sync.TotalDowngrades -gt 0) { "$($sync.TotalDowngrades) SmartSpeed downgrade event(s) in 48h - physical layer fault confirmed" } else { "No SmartSpeed downgrade events" }
    $lines += "  $ssLine"
    $lines += ""
    $lines += "CAMERA CONNECTIVITY"
    foreach ($c in @($sync.CamResults)) {
        $cs = if ($c.Ping -and $c.Rtsp) { "Ping OK / RTSP OK" } elseif ($c.Ping) { "Ping OK / RTSP FAIL" } elseif ($c.Optional) { "Not installed (optional)" } else { "No response" }
        $lines += "  $($c.IP.PadRight(18)) $($c.Label) - $cs"
    }
    if ($sync.AppIssues.Count -gt 0) {
        $lines += ""
        $lines += "APPLICATION LOG FINDINGS"
        foreach ($issue in @($sync.AppIssues)) { $lines += "  $issue" }
    }
    if ($sync.PoeAvailable) {
        $lines += ""
        $lines += "POE STATUS"
        $poeVal  = $sync.Cards['PoEBudget'].Value
        $poeNote = if ($sync.PoeBudgetLow) { " - BELOW 55 W THRESHOLD - check Molex connector on PoE NIC" } else { " - adequate" }
        $lines += "  Total budget: $poeVal$poeNote"
    }
    $lines += ""
    $lines += "NEXT STEPS"
    foreach ($step in @($sync.NextSteps)) { $lines += "  - $($step.H)" }
    $lines += ""
    if ($sync.OutputFile) { $lines += "Full report: $(Split-Path $sync.OutputFile -Leaf)" }
    $lines += "=" * 48
    [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
    [System.Windows.Forms.MessageBox]::Show("Summary copied to clipboard. Paste into your ticket or support chat.", "Copy Summary", "OK", "Information") | Out-Null
})

$btnCopy.Add_Click({
    if ($dgvLog.Rows.Count -gt 0) {
        $lines = foreach ($row in $dgvLog.Rows) {
            $lbl = "$($row.Cells[0].Value)"; $res = "$($row.Cells[1].Value)"
            if ($lbl) { "{0,-24}{1}" -f $lbl, $res } else { $res }
        }
        [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
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
    $dgvLog.Rows.Clear()
    $script:allLogItems.Clear()
    foreach ($k in $cards.Keys) { Update-CardStatus -Card $cards[$k] -Value "--" -Status "neutral" }
    $lblLastRunVal.Text = "No runs yet"
})

# ---------- Helper functions ------------------------------------------------
function Test-HighlightItem {
    param($item)
    if ($item.L -eq "Section") { return $item.Result -in @("Ports", "Signal Quality", "PoE Status") }
    return ($item.Label -notmatch '^\d') -and
           ($item.Label -notlike 'App Log*') -and
           ($item.Label -ne 'ARP Table') -and
           ($item.Label -ne 'VPU Model')
}

function Render-LogItem {
    param($item)
    Add-LogRow $dgvLog $item.Label $item.Result $item.L
}

function Refresh-Log {
    $dgvLog.Rows.Clear()
    foreach ($logItem in @($script:allLogItems)) {
        if ($script:logMode -eq "Detailed" -or (Test-HighlightItem $logItem)) {
            Render-LogItem $logItem
        }
    }
}

function Get-PortTrendSummary {
    $files = @(Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
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
        @{ H="Phase 1 - Baseline";   B="Confirm the link is degraded on the suspect port. Establishes a reference speed before any changes." }
        @{ H="Phase 2 - NIC Port";   B="Move the SAME cable and camera to a different NIC port. If 1 Gbps: NIC port is faulty. If still degraded: continue." }
        @{ H="Phase 3 - Cable";      B="Stay on the same test port and camera. Swap only the cable for a known-good one. If 1 Gbps: cable is faulty. If still degraded: continue." }
        @{ H="Phase 4 - Camera";     B="Stay on test port and new cable. Swap only the camera for a known-good unit. If 1 Gbps: camera is faulty. If still degraded: NIC/motherboard fault." }
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

function Update-GuidePortDropdown {
    $prevName = if ($cboGuidePortA.SelectedIndex -ge 0) {
        ($cboGuidePortA.SelectedItem -as [string]) -replace '\s+?.*', ''
    } else { $null }

    $cboGuidePortA.Items.Clear()
    foreach ($n in $script:detectedNics) {
        $pr = @($sync.PortResults) | Where-Object { $_.Name -eq $n.Name } | Select-Object -First 1
        $flag = if ($pr -and $pr.Result -in @("FAIL", "PASS (forced)")) { "  ? FAULT" } else { "" }
        $cboGuidePortA.Items.Add("$($n.Name)$flag") | Out-Null
    }

    $newIdx = -1
    if ($prevName) {
        for ($i = 0; $i -lt $cboGuidePortA.Items.Count; $i++) {
            if (($cboGuidePortA.Items[$i] -as [string]) -like "$prevName*") { $newIdx = $i; break }
        }
    }
    if ($newIdx -ge 0) { $cboGuidePortA.SelectedIndex = $newIdx }
    elseif ($cboGuidePortA.Items.Count -gt 0) { $cboGuidePortA.SelectedIndex = 0 }
}

function Update-HistoryList {
    $lvHistory.Items.Clear()
    $files = @(Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
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
                $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " - " + ($ports -join ", ") } else { "" })
            } else {
                # Fallback for files written before v1.5.0
                $failLines = @($lines | Where-Object { $_ -match 'DEGRADED' })
                if ($failLines.Count -gt 0) {
                    $resultText = "Issues Found"; $resultColor = $ColRed
                    $ports = $failLines | ForEach-Object {
                        if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                    } | Where-Object { $_ }
                    $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " - " + ($ports -join ", ") } else { "" })
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
        $item.BackColor = $ColCard
        $item.Tag       = $f.FullName
        $lvHistory.Items.Add($item) | Out-Null
    }
}

# ---- Guide Panel (Fault Isolation Wizard) ----------------------------------
$pnlGuide = New-Object System.Windows.Forms.Panel
$pnlGuide.Size     = New-Object System.Drawing.Size($NarrowW, $ContentH)
$pnlGuide.Location = New-Object System.Drawing.Point($SideW, $ContentY)
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
$lblGuideSub.Text = "One change at a time - force the fault to reveal what it follows."
$lblGuideSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblGuideSub.ForeColor = $ColMuted
$lblGuideSub.Location = New-Object System.Drawing.Point(10, 42); $lblGuideSub.Size = New-Object System.Drawing.Size(1240, 18)
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
$pnlGuideInstr.Size = New-Object System.Drawing.Size(1260, 108)
$pnlGuideInstr.Location = New-Object System.Drawing.Point(10, 100)
$pnlGuideInstr.BackColor = $ColAccent
$pnlGuide.Controls.Add($pnlGuideInstr)
$pnlGuideInstr.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,1260,108)), 8))

$lblGuidePhase = New-Object System.Windows.Forms.Label
$lblGuidePhase.Text = "SELECT A PORT TO BEGIN"
$lblGuidePhase.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$lblGuidePhase.ForeColor = [System.Drawing.Color]::FromArgb(187, 222, 251)
$lblGuidePhase.Location = New-Object System.Drawing.Point(14, 10); $lblGuidePhase.Size = New-Object System.Drawing.Size(1230, 18)
$pnlGuideInstr.Controls.Add($lblGuidePhase)

$lblGuideInstr = New-Object System.Windows.Forms.Label
$lblGuideInstr.Text = "Select the NIC port that is showing degraded speed (100 Mbps) and click Start."
$lblGuideInstr.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblGuideInstr.ForeColor = [System.Drawing.Color]::White
$lblGuideInstr.Location = New-Object System.Drawing.Point(14, 32); $lblGuideInstr.Size = New-Object System.Drawing.Size(1230, 66)
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
$btnGuideAction.Size = New-Object System.Drawing.Size(1260, 40); $btnGuideAction.Location = New-Object System.Drawing.Point(10, 250)
$btnGuideAction.BackColor = $ColAccent; $btnGuideAction.ForeColor = [System.Drawing.Color]::White
$btnGuideAction.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnGuideAction.FlatAppearance.BorderSize = 0
$btnGuideAction.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnGuideAction.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnGuideAction.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,1260,40)), 6))
$pnlGuide.Controls.Add($btnGuideAction)

# Result card (hidden until a check completes)
$pnlGuideResult = New-Object System.Windows.Forms.Panel
$pnlGuideResult.Size = New-Object System.Drawing.Size(1260, 84)
$pnlGuideResult.Location = New-Object System.Drawing.Point(10, 302)
$pnlGuideResult.BackColor = $ColCard
$pnlGuideResult.Visible = $false
$pnlGuideResult.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,1260,84)), 8))
$pnlGuideResult.Add_Paint({
    $g = $args[1].Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rr = New-Object System.Drawing.Rectangle(0,0,1259,83)
    $bp = [GfxHelper]::RoundedRect($rr,8)
    $pen = New-Object System.Drawing.Pen($ColBorder,1)
    $g.DrawPath($pen,$bp); $pen.Dispose(); $bp.Dispose()
})
$pnlGuide.Controls.Add($pnlGuideResult)

$lblGuideResultSpeed = New-Object System.Windows.Forms.Label; $lblGuideResultSpeed.Text = ""
$lblGuideResultSpeed.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$lblGuideResultSpeed.ForeColor = $ColText
$lblGuideResultSpeed.Location = New-Object System.Drawing.Point(14, 10); $lblGuideResultSpeed.Size = New-Object System.Drawing.Size(1230, 26)
$pnlGuideResult.Controls.Add($lblGuideResultSpeed)

$lblGuideResultVerdict = New-Object System.Windows.Forms.Label; $lblGuideResultVerdict.Text = ""
$lblGuideResultVerdict.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblGuideResultVerdict.ForeColor = $ColMuted
$lblGuideResultVerdict.Location = New-Object System.Drawing.Point(14, 38); $lblGuideResultVerdict.Size = New-Object System.Drawing.Size(1230, 36)
$pnlGuideResult.Controls.Add($lblGuideResultVerdict)

# Phase history
$sep7 = New-Object System.Windows.Forms.Panel; $sep7.Size = New-Object System.Drawing.Size(1260,1)
$sep7.Location = New-Object System.Drawing.Point(10, 398); $sep7.BackColor = $ColBorder
$pnlGuide.Controls.Add($sep7)

$lblGuideHist = New-Object System.Windows.Forms.Label; $lblGuideHist.Text = "Phase History"
$lblGuideHist.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $lblGuideHist.ForeColor = $ColText
$lblGuideHist.Location = New-Object System.Drawing.Point(10, 408); $lblGuideHist.AutoSize = $true
$pnlGuide.Controls.Add($lblGuideHist)

$lnkGuideReset = New-Object System.Windows.Forms.LinkLabel; $lnkGuideReset.Text = "Start Over"
$lnkGuideReset.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lnkGuideReset.LinkColor = $ColMuted
$lnkGuideReset.Location = New-Object System.Drawing.Point(1190, 410); $lnkGuideReset.AutoSize = $true
$pnlGuide.Controls.Add($lnkGuideReset)

$rtbGuide = New-Object System.Windows.Forms.RichTextBox
$rtbGuide.Size = New-Object System.Drawing.Size(1260, 172); $rtbGuide.Location = New-Object System.Drawing.Point(10, 430); $rtbGuide.Anchor = $AnchorTLRB
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
            # Phase 0 ? run baseline on suspect port
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
                Show-GuideResult "Baseline: $speedLabel - Port is operating normally." "The selected port is already running at 1 Gbps. No fault detected on this port. Select a different port or run the full diagnostic." "Pass"
                Add-GuideHistory "Phase 1 - Baseline" $config $speedLabel "Port healthy - no fault on this port." "Pass"
                $lblGuidePhase.Text = "BASELINE - PORT HEALTHY"
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
            Add-GuideHistory "Phase 1 - Baseline" $config $speedLabel "$baseMsg - beginning isolation." "Fail"
            Show-GuideResult "Baseline: $speedLabel - $baseMsg." $baseInstr "Fail"
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
            $lblGuidePhase.Text = "PHASE 2 - DOES THE FAULT FOLLOW THE NIC PORT?"
            $lblGuideInstr.Text = "Move the SAME cable and SAME camera from $portName to the port selected below. Press Check when reconnected."
            $btnGuideAction.Text = "  Check Now"
            $btnGuideAction.Enabled = $true
        }
        1 {
            # Phase 1 ? check after moving cable+CHU to test port
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
                    "$testPort is already showing degraded speed ($preSpeed Mbps) before you moved anything.`n`nIf this port has its own independent fault, Phase 2 results will be unreliable - the test needs a known-good port to be valid.`n`nClick Cancel to pick a different test port, or OK to proceed anyway.",
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
                $verdict = "Fault cleared on $testPort - cable and camera are healthy on a different port. Original port ($($script:guide.SuspectPort)) is likely faulty."
                Show-GuideResult "Phase 2: $speedLabel - Fault follows the original NIC port." $verdict "Pass"
                Add-GuideHistory "Phase 2 - NIC Port Test" $config $speedLabel $verdict "Pass"
                $lblGuidePhase.Text = "CONCLUSION - FAULTY NIC PORT"
                $lblGuideInstr.Text = "The cable and camera work fine on $testPort. The original port ($($script:guide.SuspectPort)) is the source of the fault. Replace or disable that NIC port."
                $btnGuideAction.Text = "  Run Full Diagnostic"
                $script:guide.Phase = 4
                Update-GuideStepDots -ActivePhase 4
                Save-GuideSession
            } else {
                $verdict = "Fault persists on $testPort - the original NIC port is likely healthy. The fault is in the cable or camera."
                Show-GuideResult "Phase 2: $speedLabel - Fault follows cable/camera, not the NIC port." $verdict "Warn"
                Add-GuideHistory "Phase 2 - NIC Port Test" $config $speedLabel $verdict "Info"
                $script:guide.Phase = 2
                $lblGuidePortB.Visible = $false; $cboGuidePortB.Visible = $false
                $lblGuidePhase.Text = "PHASE 3 - DOES THE FAULT FOLLOW THE CABLE?"
                $lblGuideInstr.Text = "Stay on $testPort with the same camera. Replace ONLY the cable with a known-good cable. Press Check when reconnected."
                $btnGuideAction.Text = "  Check Now"
                Update-GuideStepDots -ActivePhase 3
            }
        }
        2 {
            # Phase 2 ? check after swapping cable
            $testPort = $script:guide.TestPort
            $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
            $speed = Get-GuideLinkSpeed -PortName $testPort
            $btnGuideAction.Enabled = $true

            $speedLabel = if ($speed -ge 1000) { "1 Gbps" } elseif ($speed -gt 0) { "$speed Mbps" } else { "No link" }
            $config = "Port: $testPort  |  Cable: (NEW - known good)  |  Camera: (original)"

            if ($speed -ge 1000) {
                $verdict = "Link restored with new cable. The original cable is the source of the fault - bad cable or termination."
                Show-GuideResult "Phase 3: $speedLabel - Fault follows the cable." $verdict "Pass"
                Add-GuideHistory "Phase 3 - Cable Test" $config $speedLabel $verdict "Pass"
                $lblGuidePhase.Text = "CONCLUSION - FAULTY CABLE"
                $lblGuideInstr.Text = "Replacing the cable resolved the issue. The original cable (or its termination) is the source of the fault. Replace the cable end-to-end."
                $btnGuideAction.Text = "  Run Full Diagnostic"
                $script:guide.Phase = 4
                Update-GuideStepDots -ActivePhase 4
                Save-GuideSession
            } else {
                $verdict = "Still degraded with new cable. Cable is not the fault - the camera is the likely cause."
                Show-GuideResult "Phase 3: $speedLabel - Fault is not the cable." $verdict "Warn"
                Add-GuideHistory "Phase 3 - Cable Test" $config $speedLabel $verdict "Info"
                $script:guide.Phase = 3
                $lblGuidePhase.Text = "PHASE 4 - DOES THE FAULT FOLLOW THE CAMERA?"
                $lblGuideInstr.Text = "Stay on $testPort with the new cable. Connect a known-good camera. Press Check when reconnected."
                $btnGuideAction.Text = "  Check Now"
                Update-GuideStepDots -ActivePhase 4
            }
        }
        3 {
            # Phase 3 ? check after swapping camera
            $testPort = $script:guide.TestPort
            $btnGuideAction.Enabled = $false; $btnGuideAction.Text = "  Checking..."
            $speed = Get-GuideLinkSpeed -PortName $testPort
            $btnGuideAction.Enabled = $true

            $speedLabel = if ($speed -ge 1000) { "1 Gbps" } elseif ($speed -gt 0) { "$speed Mbps" } else { "No link" }
            $config = "Port: $testPort  |  Cable: (NEW)  |  Camera: (NEW - known good)"

            if ($speed -ge 1000) {
                $verdict = "Link restored with new camera. The original camera unit is the source of the fault."
                Show-GuideResult "Phase 4: $speedLabel - Fault follows the camera." $verdict "Pass"
                Add-GuideHistory "Phase 4 - Camera Test" $config $speedLabel $verdict "Pass"
                $lblGuidePhase.Text = "CONCLUSION - FAULTY CAMERA (CHU)"
                $lblGuideInstr.Text = "Replacing the camera resolved the issue. The original camera is the source of the fault. Replace the camera unit."
            } else {
                $verdict = "Still degraded with known-good cable and camera. The fault is likely in the NIC hardware itself or the VPU motherboard."
                Show-GuideResult "Phase 4: $speedLabel - Fault persists with known-good equipment." $verdict "Fail"
                Add-GuideHistory "Phase 4 - Camera Test" $config $speedLabel $verdict "Fail"
                $lblGuidePhase.Text = "CONCLUSION - NIC / HARDWARE FAULT"
                $lblGuideInstr.Text = "Known-good cable and camera still fail on $testPort. This indicates a fault in the NIC hardware or VPU motherboard. Run the full diagnostic and escalate."
            }
            $btnGuideAction.Text = "  Run Full Diagnostic"
            $script:guide.Phase = 4
            Update-GuideStepDots -ActivePhase 4
            Save-GuideSession
        }
        4 {
            # Phase 4 (concluded) ? jump to Overview and trigger diagnostic
            $navOverview.PerformClick()
            $btnRun.PerformClick()
        }
    }
})

$lnkGuideReset.Add_LinkClicked({ Reset-Guide })

# ---------- Services background script ---------------------------------------

$navOverview.Add_Click({ $navCamera.PerformClick() })
$navTests.Add_Click({    Show-Panel $pnlGuide $true; Set-ActiveNav $navCamera; Show-GuideSteps })
$navHistory.Add_Click({  $navReports.PerformClick() })
$navHelp.Add_Click({     $navAbout.PerformClick() })

$btnGoGuide.Add_Click({
    $firstFail = $sync.PortResults | Where-Object { $_.Result -eq "FAIL" } | Select-Object -First 1
    $navTests.PerformClick()
    Reset-Guide
    if ($firstFail) {
        $idx = -1
        for ($i = 0; $i -lt $cboGuidePortA.Items.Count; $i++) {
            if (($cboGuidePortA.Items[$i] -as [string]) -like "$($firstFail.Name)*") { $idx = $i; break }
        }
        if ($idx -ge 0) { $cboGuidePortA.SelectedIndex = $idx }
    }
})

