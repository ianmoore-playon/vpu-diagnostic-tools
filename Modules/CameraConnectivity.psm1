# =============================================================================
#  CameraConnectivity.psm1  -  Camera diagnostic engine, panels, and guide
# =============================================================================

# ---------- Diagnostic engine (runs in background runspace) -----------------
$DiagScript = {
    param($sync, $NicDriverPatterns, $RenegotiateWaitSec, $EventLogHours,
          $PixellotLogPaths, $RtspPort, $OutputFile, $RunId, $ScriptVersion,
          [string]$OcrMacOui = "00-D0-89",
          $PixCameraRoles = @{},
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
            if ($sync.Cancelled) { break }
            $s = Get-AdapterSpeedMbps -AdapterName $AdapterName
            if ($s -gt $peak) { $peak = $s }
            if ($peak -ge 1000) { break }
            # R10 fix: break Start-Sleep into short slices so Cancel takes
            # effect inside the window instead of waiting up to $IntervalMs ms.
            $slept = 0
            while ($slept -lt $IntervalMs) {
                if ($sync.Cancelled) { break }
                Start-Sleep -Milliseconds 100
                $slept += 100
            }
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
        # D17 fix: timeout up from 2000ms to 3000ms + 2 retries. A single dropped
        # SYN under load on RTSP/554 used to flag the camera as Critical.
        param([string]$IP, [int]$Port, [int]$TimeoutMs = 3000, [int]$Retries = 2)
        for ($attempt = 0; $attempt -le $Retries; $attempt++) {
            $tcp = $null
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $c   = $tcp.BeginConnect($IP, $Port, $null, $null)
                $ok  = $c.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
                if ($ok) { try { $tcp.EndConnect($c) } catch { $ok = $false } }
                if ($ok) { return $true }
            } catch { }
            finally { if ($tcp) { try { $tcp.Close() } catch { } } }
            if ($attempt -lt $Retries -and -not $sync.Cancelled) { Start-Sleep -Milliseconds 300 }
            if ($sync.Cancelled) { return $false }
        }
        return $false
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
                        # D4 fix: soften the wording. Most common cause is cable
                        # or termination, but the camera revision (some are 100 Mbps-
                        # only) or a switch admin-locked port can produce the same
                        # symptom. Don't bias the truck-roll toward a cable swap.
                        Add-Log ("  [FAIL]  Still not 1 Gbps after forcing (current: {0})." -f $nsLabel) "Fail"
                        Add-Log "          Likely cable or termination - also verify the camera revision supports gigabit and the switch port is not locked to 100M." "Warn"
                        Add-Log "          Resetting to Auto Negotiation..." "Warn"
                        Set-AdapterSpeedDuplex -AdapterName $nm -Val "0" | Out-Null
                        Restart-NetAdapter -Name $nm -Confirm:$false -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 5
                        $autoSpd = Get-AdapterSpeedMbps -AdapterName $nm
                        if ($autoSpd -gt 0) { Add-Log ("  [INFO]  Link restored at {0} Mbps" -f $autoSpd) "Warn" }
                        $portResults += [PSCustomObject]@{ Name=$nm; Speed=$spd; Result="FAIL"; Blinking=$blinking; Desc=$nic.InterfaceDescription }
                        $anyFail = $true
                        Set-Card $nm "100 Mbps" "fail"
                        Add-Summary $nm "DEGRADED  - check cable / camera revision / switch port" "Fail"
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
        # D9 fix: split by recency. A single transient downgrade weeks ago that
        # auto-recovered shouldn't paint the whole module Critical at every run.
        # Recent (last 4h) ID 40 = fail; older ID 40 = warn with historical note.
        $recentCutoff   = (Get-Date).AddHours(-4)
        $recentDgrade   = ($chuEvents | Where-Object { $_.Id -eq 40 -and $_.TimeCreated -ge $recentCutoff }).Count
        $olderDgrade    = ($chuEvents | Where-Object { $_.Id -eq 40 -and $_.TimeCreated -lt $recentCutoff }).Count
        $dCnt           = $recentDgrade + $olderDgrade
        $wCnt           = ($chuEvents | Where-Object { $_.Id -eq 27 }).Count
        $ssLevel        = if ($recentDgrade -gt 0) { "Fail" } else { "Warn" }
        $msg = if ($recentDgrade -gt 0) {
                   "$recentDgrade recent downgrade(s) within the last 4h ($olderDgrade older, $wCnt link warning(s))"
               } else {
                   "$olderDgrade historical downgrade(s) (none in last 4h) + $wCnt link warning(s) in ${EventLogHours}h"
               }
        Add-Log "  [$($ssLevel.ToUpper())] $msg" $ssLevel
        Add-Log ""
        foreach ($evt in ($chuEvents | Sort-Object @{Expression='TimeCreated';Descending=$true} | Select-Object -First 10)) {
            $an = Get-EventAdapterName -Evt $evt -KnownDescs $knownDescs
            $shortName = if ($an -match '#(\d+)') { "CHU NIC #$($Matches[1])" } else { $an }
            $label = switch ($evt.Id) { 40 {"SmartSpeed Downgrade"} 33 {"Link at 100 Mbps"} 27 {"Link Warning"} default {"Event $($evt.Id)"} }
            $age   = if ($evt.TimeCreated -ge $recentCutoff) { "" } else { "  (historical)" }
            Add-Log ("  {0}  {1}  ID {2} - {3}{4}" -f $evt.TimeCreated.ToString("MM/dd HH:mm:ss"), $shortName, $evt.Id, $label, $age) "Warn"
        }
        Add-Log ""
        if ($recentDgrade -gt 0) {
            Add-Log "  -> Recent physical-layer events. Likely cause: faulty cable, bad termination, or 100M-only camera. Inspect the affected port." "Info"
        } elseif ($olderDgrade -gt 0) {
            Add-Log "  -> Historical only. Monitor; no action required unless the events recur." "Info"
        }
        $sync.StepsDone["SmartSpeed"] = if ($recentDgrade -gt 0) { "fail" } else { "pass" }
        $ssSummary = if ($recentDgrade -gt 0) { "$recentDgrade recent downgrade(s)" }
                     elseif ($olderDgrade -gt 0) { "$olderDgrade historical downgrade(s)" }
                     else { "$wCnt warning(s), 0 downgrades" }
        Add-Summary "SmartSpeed Events" $ssSummary $ssLevel
        $ssCardVal    = if ($recentDgrade -gt 0) { "$recentDgrade recent" }
                        elseif ($olderDgrade -gt 0) { "$olderDgrade historical" }
                        elseif ($wCnt -gt 0) { "$wCnt warnings" }
                        else { "None" }
        $ssCardStatus = if ($recentDgrade -gt 0) { "fail" } elseif ($olderDgrade -gt 0 -or $wCnt -gt 0) { "warn" } else { "ok" }
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
        # Pull the NIC's link speed once per port so we can speed-fallback
        # for cameras that aren't in cameras.cfg (different agent install
        # path, swapped camera, etc.). OCR cameras are 100 Mbps-only on
        # all known revisions, main cameras are gigabit.
        $linkSpeed = ""
        try { $linkSpeed = "$((Get-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue).LinkSpeed)" } catch { }
        foreach ($nb in $neighbors) {
            if ($discoveredCameras | Where-Object { $_.IP -eq $nb.IPAddress }) { continue }
            # Authoritative role from cameras.cfg / pip.cfg (passed in via
            # $PixCameraRoles). Falls back to a speed-based label when the
            # IP isn't in the config; we deliberately do *not* try to
            # subtype Pixellot devices via the 4th MAC octet because
            # different camera revisions share overlapping prefixes.
            $roleLabel = $null
            if ($PixCameraRoles -and $PixCameraRoles.ContainsKey($nb.IPAddress)) {
                $roleLabel = [string]$PixCameraRoles[$nb.IPAddress]
            }
            # $OcrMacOui is the OCR-specific Pixellot OUI ("00-D0-89"). When the
            # ARP entry matches it, the device is authoritatively an OCR camera
            # regardless of current link state — D3 fix. Previously a stale ARP
            # entry on a flapped OCR could be relabeled "Main Camera (probable)"
            # and then escalate as a false Critical when the ping failed.
            $isOcrByMac = ($nb.LinkLayerAddress -like "$OcrMacOui-*")
            $is100M = ($linkSpeed -match '^\s*100\s*Mbps')
            $is1G   = ($linkSpeed -match '\b\d+\s*Gbps\b' -or $linkSpeed -match '^\s*1000\s*Mbps')
            $label = if ($roleLabel)                       { $roleLabel } `
                     elseif ($isOcrByMac -and $is100M)     { "OCR Camera" } `
                     elseif ($isOcrByMac -and $is1G)       { "OCR Camera (unexpected gigabit link)" } `
                     elseif ($isOcrByMac)                  { "OCR Camera (link down)" } `
                     elseif ($is1G)                        { "Main Camera (probable)" } `
                     else                                  { "Unknown device" }
            $isOcr = ($roleLabel -and $roleLabel -match 'OCR|Scoreboard') -or
                     ($label -like 'OCR Camera*') -or
                     $isOcrByMac
            $discoveredCameras += [PSCustomObject]@{
                IP       = $nb.IPAddress
                MAC      = $nb.LinkLayerAddress
                Label    = $label
                Optional = $isOcr
                NicName  = $nic.Name
            }
            Add-Log ("  Found  : {0,-18} MAC: {1}  Role: {2}" -f $nb.IPAddress, $nb.LinkLayerAddress, $label) "Info"
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
            # D7 fix: debounce momentary packet loss with up to 3 rounds.
            # 2 ICMP per round; one full second between rounds.
            $pingOk = $false
            for ($pingTry = 1; $pingTry -le 3; $pingTry++) {
                if ($sync.Cancelled) { break }
                $pingOk = Test-Connection -ComputerName $cam.IP -Count 2 -Quiet -ErrorAction SilentlyContinue
                if ($pingOk) { break }
                if ($pingTry -lt 3) { Start-Sleep -Seconds 1 }
            }
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

        # Ping (CHU) reflects ICMP reachability of every discovered camera —
        # it answers "is the camera at the network layer?" using whatever IP
        # ARP discovery returned (no hardcoded IPs).
        if ($mainPingCount -eq $mainTotal -and $mainTotal -gt 0) {
            Set-Card "PingCHU" "Success" "ok"
        } elseif ($mainPingCount -gt 0) {
            Set-Card "PingCHU" "Partial" "warn"
        } else {
            Set-Card "PingCHU" "No Response" "fail"
        }

        # CHU Detection now reflects RTSP port 554 — "is the camera actually
        # serving its video stream?". An OCR camera doesn't expose RTSP, so we
        # only count non-optional (S2/CHU) cameras. This makes the two cards
        # complementary rather than duplicated.
        $rtspMain = @($camResults | Where-Object { -not $_.Optional })
        $rtspOkN  = @($rtspMain | Where-Object { $_.Rtsp }).Count
        $rtspTot  = $rtspMain.Count
        if ($rtspTot -eq 0) {
            Set-Card "ChuDetect" "No CHU" "neutral"
        } elseif ($rtspOkN -eq $rtspTot) {
            Set-Card "ChuDetect" "Online" "ok"
        } elseif ($rtspOkN -gt 0) {
            Set-Card "ChuDetect" "Partial" "warn"
        } else {
            Set-Card "ChuDetect" "Offline" "fail"
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
        $logContent = Get-Content -Path $latestLog.FullName -Tail 5000 -ErrorAction SilentlyContinue
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
        $sync.StepsDone["PoePower"] = "pass"   # N/A by design on this NIC family
    } elseif ($PoeDllPath -and ([System.Management.Automation.PSTypeName]'AdlinkPoE').Type) {
        # R9 fix: track register success separately so SmartPoE_Release_Card runs
        # in a `finally` even when an inner call (Voltage/Current/Budget) throws.
        # The AdlinkPoE DLL is prone to AccessViolation on certain platforms;
        # leaking the card handle eventually exhausts the register slot.
        $poeStepStatus = "warn"   # D16 default: warn unless we explicitly succeed
        $cardNum       = [uint16]0
        $regOk         = $false
        try {
            $regRet = [AdlinkPoE]::SmartPoE_Register_Card($cardNum)
            if ($regRet -eq 0) {
                $regOk             = $true
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

                $poeOnCount = 0
                for ($port = 0; $port -lt 4; $port++) {
                    if ($sync.Cancelled) { break }
                    $pLabel   = "P$($port + 1)"
                    $portNum  = [uint16]$port
                    $voltage  = [double]0.0; $current = [double]0.0
                    [void][AdlinkPoE]::SmartPoE_Get_PSEPortVoltage($cardNum, $portNum, [ref]$voltage)
                    [void][AdlinkPoE]::SmartPoE_Get_PSEPortCurrent($cardNum, $portNum, [ref]$current)
                    $watts    = $voltage * $current
                    $isPoeOn  = ($voltage -gt 1.0)
                    if ($isPoeOn) { $poeOnCount++ }
                    $stateStr = if ($isPoeOn) { "PoE ON" } else { "PoE OFF" }
                    $portLvl  = if ($isPoeOn) { "Pass" } else { "Gray" }
                    Add-Log    ("  {0,-5} : {1:F2} V  {2:F3} A  {3:F1} W  [{4}]" -f $pLabel, $voltage, $current, $watts, $stateStr) $portLvl
                    Add-Summary "PoE $pLabel" ("{0:F1} W  ({1})" -f $watts, $stateStr) $portLvl
                    $sync.PoePortData.Add(@{ Port=$pLabel; Voltage=$voltage; Current=$current; Watts=$watts; PoeOn=$isPoeOn }) | Out-Null
                }
                $sync.PoeConsumed = $consumed; $sync.PoeTotal = $total; $sync.PoeTemp = $temp
                Add-Log ""

                # D8 fix: 55 W was below the 4xPoE+ spec floor (4 * 25.5 W = 102 W).
                # The "check Molex" advice only makes sense when the card is supposed
                # to be carrying 3+ PoE+ ports. For 1-2 active PoE ports, a smaller
                # budget is normal. Scale the threshold to the number of PoE-on
                # ports; cite the spec in the log.
                $expectedBudget = $poeOnCount * 25.5
                $sync.PoeBudgetLow = ($total -gt 0) -and ($poeOnCount -ge 3) -and ($total -lt $expectedBudget)
                if ($sync.PoeBudgetLow) {
                    Add-Log ("  [WARN]  Total power budget {0:F1} W is below the expected {1:F1} W for {2} PoE-on ports (IEEE 802.3at 25.5 W/port)." -f $total, $expectedBudget, $poeOnCount) "Fail"
                    Add-Log "          The Molex power connector on the PoE NIC may be disconnected." "Fail"
                    Add-Summary "PoE Budget" ("{0:F0} W  LOW" -f $total) "Fail"
                    Set-Card "PoEBudget" ("{0:F0} W" -f $total) "fail"
                    $poeStepStatus = "fail"
                } else {
                    Add-Log ("  [PASS]  Total power budget {0:F1} W - adequate for {1} active PoE port(s)." -f $total, $poeOnCount) "Pass"
                    Add-Summary "PoE Budget" ("{0:F0} W  OK" -f $total) "Pass"
                    Set-Card "PoEBudget" ("{0:F0} W" -f $total) "ok"
                    $poeStepStatus = "pass"
                }
            } else {
                Add-Log "  [INFO] SmartPoE_Register_Card returned $regRet - PoE card not detected on this system." "Gray"
                Add-Summary "PoE Budget" "Card not found" "Gray"
                $poeStepStatus = "warn"
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
            $poeStepStatus = "warn"
        } finally {
            # R9 fix: always release the card handle if registration succeeded,
            # even when an inner call threw. Prevents handle leaks across runs.
            if ($regOk) { try { [void][AdlinkPoE]::SmartPoE_Release_Card($cardNum) } catch { } }
        }
        # D16 fix: reflect the real outcome here instead of hard-coding "pass".
        $sync.StepsDone["PoePower"] = $poeStepStatus
    } else {
        Add-Log "  [INFO] SmartPoE.dll not found - PoE monitoring not available on this system." "Gray"
        Add-Summary "PoE Budget" "N/A" "Gray"
        Set-Card "PoEBudget" "N/A" "neutral"
        $sync.StepsDone["PoePower"] = "pass"   # N/A path: nothing to fail
    }
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


# ---- Camera Connectivity (v1.0.46 redesign — section header + two-column) --
$center = New-Object System.Windows.Forms.Panel
$center.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
$center.Location  = New-Object System.Drawing.Point($SideW, $ContentY)
$center.BackColor = $ColBg
$center.Anchor    = $AnchorTLRB
$center.Visible   = $false
$form.Controls.Add($center)

# Section header — title / subtitle / Overall Status pill (top-right)
$camHeader = New-SectionHeader -Parent $center `
    -Title    "Camera Connectivity" `
    -Subtitle "Validate link speed, ping cameras, and isolate physical-layer faults"

# ---- Toolbar strip (Y=110..168): Test Scope + Run hint + Detected NIC card --
$pnlCamToolbar = New-Object System.Windows.Forms.Panel
$pnlCamToolbar.Size      = New-Object System.Drawing.Size(1224, 58)
$pnlCamToolbar.Location  = New-Object System.Drawing.Point(28, 110)
$pnlCamToolbar.BackColor = $ColCard
$pnlCamToolbar.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 1224, 58)), 8))
$pnlCamToolbar.Anchor    = $AnchorTLR
$center.Controls.Add($pnlCamToolbar)

$lblNicHdr = New-Object System.Windows.Forms.Label
$lblNicHdr.Text      = "Test Scope"
$lblNicHdr.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblNicHdr.ForeColor = $ColMuted
$lblNicHdr.BackColor = [System.Drawing.Color]::Transparent
$lblNicHdr.Location  = New-Object System.Drawing.Point(16, 6)
$lblNicHdr.AutoSize  = $true
$pnlCamToolbar.Controls.Add($lblNicHdr)

# Helper — extract just the NIC interface name (e.g. "Ethernet 24") from a
# cboNic item text. v1.0.49 changed the format from "<NicName>  (<short>)"
# to "Port N — <NicName> — <Device>", so call sites use this helper instead
# of inlining a fragile regex. Returns empty string for "All Ports".
function Get-NicNameFromCbo {
    param([string]$Text)
    if (-not $Text -or $Text -eq "All Ports") { return "" }
    # Both em-dash (—) and ASCII hyphen-minus are accepted to be tolerant
    # of the build-time character normalisation that happens in Run.ps1.
    $parts = $Text -split '\s+[—–\-]\s+'
    if ($parts.Count -ge 2) { return $parts[1].Trim() }
    return $Text.Trim()
}

$cboNic = New-Object System.Windows.Forms.ComboBox
$cboNic.Size          = New-Object System.Drawing.Size(320, 22)   # widened from 220 to fit "Ethernet 24 — Main Camera (1 Gbps)"
$cboNic.Location      = New-Object System.Drawing.Point(16, 26)
$cboNic.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
# v1.0.49: explicit dark/light foreground + flat style. The default ComboBox
# in DropDownList mode renders the selected item using the system theme's
# button text color, which on the dark theme can come out as near-black on
# our dark blue card background — practically invisible. Setting ForeColor
# to $ColText guarantees the same readable color used elsewhere on the panel.
$cboNic.FlatStyle     = [System.Windows.Forms.FlatStyle]::Flat
$cboNic.BackColor     = $ColCard
$cboNic.ForeColor     = $ColText
$cboNic.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$pnlCamToolbar.Controls.Add($cboNic)

$lblRunSteps = New-Object System.Windows.Forms.Label
$lblRunSteps.Text      = "Runs: Port Speed  *  Ping  *  ARP  *  CHU Detection"
$lblRunSteps.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblRunSteps.ForeColor = $ColMuted
$lblRunSteps.BackColor = [System.Drawing.Color]::Transparent
$lblRunSteps.Location  = New-Object System.Drawing.Point(252, 28)
$lblRunSteps.Size      = New-Object System.Drawing.Size(580, 18)
$pnlCamToolbar.Controls.Add($lblRunSteps)

$lblNicCardHdr = New-Object System.Windows.Forms.Label
$lblNicCardHdr.Text      = "Detected NIC"
$lblNicCardHdr.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblNicCardHdr.ForeColor = $ColMuted
$lblNicCardHdr.BackColor = [System.Drawing.Color]::Transparent
$lblNicCardHdr.Location  = New-Object System.Drawing.Point(880, 6)
$lblNicCardHdr.Size      = New-Object System.Drawing.Size(330, 16)
$lblNicCardHdr.Anchor    = $AnchorTR
$pnlCamToolbar.Controls.Add($lblNicCardHdr)

$lblNicCardVal = New-Object System.Windows.Forms.Label
# U-polish: was "Detecting..." which stuck forever if the WMI/NIC scan
# threw during Form_Load. Render an em-dash so an unreached update path
# doesn't look like an in-progress operation.
$lblNicCardVal.Text      = "--"
$lblNicCardVal.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblNicCardVal.ForeColor = $ColText
$lblNicCardVal.BackColor = [System.Drawing.Color]::Transparent
$lblNicCardVal.Location  = New-Object System.Drawing.Point(880, 28)
$lblNicCardVal.Size      = New-Object System.Drawing.Size(330, 22)
$lblNicCardVal.Anchor    = $AnchorTR
$pnlCamToolbar.Controls.Add($lblNicCardVal)

# Hidden compat: $btnRetest is wired by the timer/handlers but the redesigned
# bottom action bar replaces it. Keep as off-screen no-op so click code paths
# don't NPE.
$btnRetest = New-Object System.Windows.Forms.Button
$btnRetest.Visible = $false
$btnRetest.Size    = New-Object System.Drawing.Size(0, 0)
$center.Controls.Add($btnRetest)

# Hidden compat ETA label — surfaced via $lblStatus during runs.
$lblEta = New-Object System.Windows.Forms.Label
$lblEta.Text    = "est. ~2 min"
$lblEta.Visible = $false
$center.Controls.Add($lblEta)

# ---- Detected NIC list (used by diagram + diagnostic) ----------------------
$portRowW = 1040; $portRowX0 = 28   # v1.0.49: tightened from 1224 so the status cards row ends at X=1068, well clear of the right-edge sidebar at X=1124
# R3 fix: wrap the dot-source-time Get-NetAdapter call in a 6-second job so a
# stuck WMI / NetTCPIP layer can't block module load (and therefore the entire
# UI thread + window paint). Sick-WMI is one of the failure modes Pulse exists
# to diagnose; the tool itself must survive it.
$script:detectedNics = @()
# Use a runspace-hosted timeout (~80ms overhead) instead of Start-Job (~500ms+)
# or ThreadJob (may not be present on locked-down LTSC images). 6-second cap.
$detectPs   = $null
$detectAsync= $null
try {
    $detectPs = [powershell]::Create()
    $detectPs.AddScript({
        param($Patterns)
        Get-NetAdapter | Where-Object {
            $d = $_.InterfaceDescription
            ($Patterns | Where-Object { $d -like $_ }).Count -gt 0
        } | Sort-Object {
            try { (Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction Stop).Function } catch { 999 }
        }, Name
    }).AddArgument($NicDriverPatterns) | Out-Null
    $detectAsync = $detectPs.BeginInvoke()
    if ($detectAsync.AsyncWaitHandle.WaitOne(6000)) {
        $script:detectedNics = @($detectPs.EndInvoke($detectAsync))
    } else {
        Write-Warning "NIC detection timed out at module load (WMI/NetTCPIP not responding within 6s); cards will populate from the live monitor instead."
        $detectPs.Stop()
    }
} catch {
    # Fallback: try the synchronous call once. Better to have an empty
    # $detectedNics than crash module load.
    try {
        $script:detectedNics = @(Get-NetAdapter | Where-Object {
            $d = $_.InterfaceDescription
            ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
        })
    } catch { $script:detectedNics = @() }
} finally {
    if ($detectPs) { try { $detectPs.Dispose() } catch { } }
}

# ---- $cards hashtable ------------------------------------------------------
# The Camera diagnostic timer iterates $cards.Keys and calls Update-CardStatus
# for each entry. Per-NIC entries ($cards[$n.Name]) are kept as hidden stub
# cards so the timer doesn't NPE; the visible per-port info is rendered via
# the NIC Port Layout below. Diagnostic results are mirrored into the port
# detail boxes' Status text by Update-CamPortBoxesFromDiag (called from the
# timer).
$cards = @{}
foreach ($n in $script:detectedNics) {
    $stub = New-StatusCard -Title $n.Name -X 0 -Y 0 -CardW 100 -CardH 90
    $stub.Panel.Visible = $false
    $cards[$n.Name] = $stub
    $sync.Cards[$n.Name] = @{ Value = "--"; Status = "neutral" }
    $center.Controls.Add($stub.Panel)
}

# ---- NIC Port Layout (relocated from Hardware tab, v1.0.47) ----------------
# Visual mapping of physical port 1–4 to detected NICs with live link state.
# Top: stylized NIC bracket with 4 RJ45 jack openings, status light, and
# colored LED dots (Y=176..258). Below: 4 port detail boxes with Port N /
# Status / Speed / Duplex / MAC / Errors (Y=266..376). Right sidebar:
# NIC Information (Y=176..286) and Status Legend (Y=294..376).

# Canvas — 990 wide × 82 tall, leaving room for the right sidebar (240 wide)
$pnlHwNicCanvas = New-Object System.Windows.Forms.Panel
$pnlHwNicCanvas.Size      = New-Object System.Drawing.Size(990, 82)
$pnlHwNicCanvas.Location  = New-Object System.Drawing.Point(28, 176)
$pnlHwNicCanvas.BackColor = $ColCard
$pnlHwNicCanvas.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 990, 82)), 8))
$center.Controls.Add($pnlHwNicCanvas)

# Canvas-internal layout constants. Compact form: PCB body fills the canvas,
# jacks centered horizontally, status light to the left of port 1.
$script:nicCardY      = 6
$script:nicCardH      = 56
$script:nicJackY      = 18
$script:nicJackH      = 32
$script:nicJackW      = 56
$script:nicJackGap    = 14
$script:nicJackRowW   = 4 * $script:nicJackW + 3 * $script:nicJackGap   # 266
$script:nicStatusOffX = 32
$script:nicJackStartX = [int](( ($pnlHwNicCanvas.Width) - $script:nicJackRowW + $script:nicStatusOffX) / 2)
$script:nicLightX     = $script:nicJackStartX - $script:nicStatusOffX

$pnlHwNicCanvas.Add_Paint({
    $g = $args[1].Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $cw = $pnlHwNicCanvas.Width
    # PCB body — soft green-tinted rectangle to evoke the PCB without using a photo
    $pcbColor = [System.Drawing.Color]::FromArgb(28, 56, 38)
    $pcbBrush = New-Object System.Drawing.SolidBrush($pcbColor)
    $pcbRect  = New-Object System.Drawing.Rectangle(20, $script:nicCardY, ($cw - 40), $script:nicCardH)
    $g.FillRectangle($pcbBrush, $pcbRect); $pcbBrush.Dispose()
    $pcbPen   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60, 120, 80), 1)
    $g.DrawRectangle($pcbPen, $pcbRect); $pcbPen.Dispose()
    # Bracket strip — metallic gray band along the bottom
    $brkBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140, 145, 152))
    $brkRect  = New-Object System.Drawing.Rectangle(20, ($script:nicCardY + $script:nicCardH), ($cw - 40), 14)
    $g.FillRectangle($brkBrush, $brkRect); $brkBrush.Dispose()
    # Status light — small green LED next to Port 1 (always green; indicates card power, not link)
    $litX = $script:nicLightX
    $litY = $script:nicJackY + ($script:nicJackH / 2) - 5
    $litBrush = New-Object System.Drawing.SolidBrush($ColGreen)
    $g.FillEllipse($litBrush, $litX, $litY, 10, 10); $litBrush.Dispose()
    $hintFont = New-Object System.Drawing.Font("Segoe UI Semibold", 7)
    $hintBrush = New-Object System.Drawing.SolidBrush($ColText)
    $g.DrawString("PWR", $hintFont, $hintBrush, ($litX - 6), ($litY + 13))
    $hintFont.Dispose(); $hintBrush.Dispose()
    # 4 RJ45 jack openings (Port 1 leftmost). Per-port LED is now ABOVE the jack
    # for visibility; the jack itself stays clean to read as a physical port.
    $jackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(15, 25, 35))
    $jackPen   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 90, 100), 1)
    $portLblFont = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
    $portLblBrush = New-Object System.Drawing.SolidBrush($ColText)
    $speedFont = New-Object System.Drawing.Font("Segoe UI", 7)
    for ($p = 0; $p -lt 4; $p++) {
        $jx = $script:nicJackStartX + $p * ($script:nicJackW + $script:nicJackGap)
        $jackRect = New-Object System.Drawing.Rectangle($jx, $script:nicJackY, $script:nicJackW, $script:nicJackH)
        $g.FillRectangle($jackBrush, $jackRect)
        $g.DrawRectangle($jackPen, $jackRect)
        # Port label centered under the jack — bright + semibold
        $portLabel = "Port $($p + 1)"
        $portLblSize = $g.MeasureString($portLabel, $portLblFont)
        $portLblX = $jx + (($script:nicJackW - $portLblSize.Width) / 2)
        $g.DrawString($portLabel, $portLblFont, $portLblBrush, $portLblX, ($script:nicJackY + $script:nicJackH + 16))
    }
    $jackBrush.Dispose(); $jackPen.Dispose(); $portLblFont.Dispose(); $portLblBrush.Dispose()
    # Per-port colored LED dots — moved ABOVE each jack and made larger.
    # The companion text underneath each LED gives a quick speed/state read
    # without requiring the user to read the port detail boxes.
    if ($script:hwPortLedColors -and $script:hwPortLedColors.Count -ge 4) {
        for ($p = 0; $p -lt 4; $p++) {
            $jx = $script:nicJackStartX + $p * ($script:nicJackW + $script:nicJackGap)
            $ledX = $jx + ($script:nicJackW / 2) - 6
            $ledY = $script:nicJackY - 13
            # Soft outer halo for the LED so it reads as illuminated
            $haloColor = [System.Drawing.Color]::FromArgb(60, $script:hwPortLedColors[$p].R, $script:hwPortLedColors[$p].G, $script:hwPortLedColors[$p].B)
            $haloBrush = New-Object System.Drawing.SolidBrush($haloColor)
            $g.FillEllipse($haloBrush, ($ledX - 3), ($ledY - 3), 18, 18); $haloBrush.Dispose()
            $ledBrush = New-Object System.Drawing.SolidBrush($script:hwPortLedColors[$p])
            $g.FillEllipse($ledBrush, $ledX, $ledY, 12, 12); $ledBrush.Dispose()
        }
    }
    # Per-port speed hint — drawn between the jack and the "Port N" label
    if ($script:hwPortSpeedLabels -and $script:hwPortSpeedLabels.Count -ge 4) {
        for ($p = 0; $p -lt 4; $p++) {
            $jx = $script:nicJackStartX + $p * ($script:nicJackW + $script:nicJackGap)
            $sLabel = $script:hwPortSpeedLabels[$p]
            if (-not $sLabel) { continue }
            $sColor = if ($script:hwPortLedColors -and $script:hwPortLedColors.Count -gt $p) { $script:hwPortLedColors[$p] } else { $ColMuted }
            $sBrush = New-Object System.Drawing.SolidBrush($sColor)
            $sSize  = $g.MeasureString($sLabel, $speedFont)
            $sX = $jx + (($script:nicJackW - $sSize.Width) / 2)
            $g.DrawString($sLabel, $speedFont, $sBrush, $sX, ($script:nicJackY + $script:nicJackH + 1))
            $sBrush.Dispose()
        }
    }
    $speedFont.Dispose()
})
$script:hwPortLedColors    = @($ColMuted, $ColMuted, $ColMuted, $ColMuted)
$script:hwPortSpeedLabels  = @("", "", "", "")

# 4 port detail boxes — Y=266, 240×110 each. Click jumps to Fault Isolator
# with the matching port pre-selected (preserved from prior P1..P4 cards).
$script:hwPortTiles = @()
$portBoxStartX = 28; $portBoxGap = 12; $portBoxW = 240; $portBoxH = 110
for ($p = 0; $p -lt 4; $p++) {
    $portNum = $p + 1
    $tileX   = $portBoxStartX + $p * ($portBoxW + $portBoxGap)
    $tile = New-Object System.Windows.Forms.Panel
    $tile.Size      = New-Object System.Drawing.Size($portBoxW, $portBoxH)
    $tile.Location  = New-Object System.Drawing.Point($tileX, 266)
    $tile.BackColor = $ColCard
    $tile.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $portBoxW, $portBoxH)), 6))
    $tile.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $center.Controls.Add($tile)

    $lblNum = New-Object System.Windows.Forms.Label
    $lblNum.Text      = "Port $portNum"
    $lblNum.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
    $lblNum.ForeColor = $ColText
    $lblNum.Location  = New-Object System.Drawing.Point(12, 8)
    $lblNum.Size      = New-Object System.Drawing.Size(80, 20)
    $tile.Controls.Add($lblNum)

    $lblStatusIcon = New-Object System.Windows.Forms.Label
    $lblStatusIcon.Text      = [char]0x26AB
    $lblStatusIcon.Font      = New-Object System.Drawing.Font("Segoe UI Symbol", 10)
    $lblStatusIcon.ForeColor = $ColMuted
    $lblStatusIcon.Location  = New-Object System.Drawing.Point(96, 8)
    $lblStatusIcon.Size      = New-Object System.Drawing.Size(18, 20)
    $tile.Controls.Add($lblStatusIcon)

    $lblStatusText = New-Object System.Windows.Forms.Label
    $lblStatusText.Text      = "--"
    $lblStatusText.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
    $lblStatusText.ForeColor = $ColMuted
    $lblStatusText.Location  = New-Object System.Drawing.Point(116, 9)
    $lblStatusText.Size      = New-Object System.Drawing.Size(120, 20)
    $tile.Controls.Add($lblStatusText)

    function _AddCamPortRow {
        param($parent, $y, $label, $ColMuted, $ColText)
        $lblL = New-Object System.Windows.Forms.Label
        $lblL.Text      = "$label"
        $lblL.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
        $lblL.ForeColor = $ColMuted
        $lblL.Location  = New-Object System.Drawing.Point(12, $y)
        $lblL.Size      = New-Object System.Drawing.Size(60, 16)
        $parent.Controls.Add($lblL)
        $lblV = New-Object System.Windows.Forms.Label
        $lblV.Text      = "--"
        $lblV.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
        $lblV.ForeColor = $ColText
        $lblV.Location  = New-Object System.Drawing.Point(72, $y)
        $lblV.Size      = New-Object System.Drawing.Size(150, 16)
        $parent.Controls.Add($lblV)
        return $lblV
    }
    # Row order: Device (what's plugged in) → Speed (link rate) → IP +
    # MAC of the REMOTE end (the camera/OCR, not this NIC port) → Errors.
    # Duplex was dropped — it's effectively always Full on modern cameras.
    # Spacing tightened from 18 → 15 px to fit 5 info rows in the 110-tall
    # tile. The MAC and IP shown here come from ARP (Get-NetNeighbor) — the
    # local NIC's own MAC stays visible in the right-side NIC Information
    # sidebar so we don't lose that.
    $lblDeviceV = _AddCamPortRow $tile 30 "Device:" $ColMuted $ColText
    $lblSpeedV  = _AddCamPortRow $tile 45 "Speed:"  $ColMuted $ColText
    $lblIpV     = _AddCamPortRow $tile 60 "IP:"     $ColMuted $ColText
    $lblIpV.Font  = New-Object System.Drawing.Font("Consolas", 8)
    $lblMacV    = _AddCamPortRow $tile 75 "MAC:"    $ColMuted $ColText
    $lblMacV.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblErrV    = _AddCamPortRow $tile 90 "Errors:" $ColMuted $ColText

    $script:hwPortTiles += @{
        PortNum   = $portNum
        Tile      = $tile
        StatusIcn = $lblStatusIcon
        StatusTxt = $lblStatusText
        DeviceV   = $lblDeviceV
        SpeedV    = $lblSpeedV
        IpV       = $lblIpV
        MacV      = $lblMacV
        ErrV      = $lblErrV
        NicName   = $null   # populated by Update-HwPortDiagram so the click handler can jump to Fault Isolator
    }

    # Click → Fault Isolator with the port's NIC pre-selected
    $capturedIdx = $p
    $portTileClickHandler = {
        $tInfo = $script:hwPortTiles[$capturedIdx]
        if (-not $tInfo.NicName) { return }
        $navTests.PerformClick()
        Reset-Guide
        $idx = -1
        for ($i = 0; $i -lt $cboGuidePortA.Items.Count; $i++) {
            if (($cboGuidePortA.Items[$i] -as [string]) -like "$($tInfo.NicName)*") { $idx = $i; break }
        }
        if ($idx -ge 0) { $cboGuidePortA.SelectedIndex = $idx }
    }.GetNewClosure()
    $tile.Add_Click($portTileClickHandler)
    foreach ($ctrl in @($tile.Controls)) { $ctrl.Add_Click($portTileClickHandler); $ctrl.Cursor = [System.Windows.Forms.Cursors]::Hand }
}

# Right sidebar: NIC Information (Y=176..286) + Status Legend (Y=294..380)
# v1.0.49: form widened from 1500 to 1600; the sidebar now sits at X=1124
# (was 1024) so there's a clear 100px gap between Port 4's detail box and
# the Status Legend instead of having them butt against each other.
$pnlHwNicInfo = New-Object System.Windows.Forms.Panel
$pnlHwNicInfo.Size      = New-Object System.Drawing.Size(228, 110)
$pnlHwNicInfo.Location  = New-Object System.Drawing.Point(1124, 176)
$pnlHwNicInfo.BackColor = $ColCard
$pnlHwNicInfo.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 228, 110)), 8))
$pnlHwNicInfo.Anchor    = $AnchorTR
$center.Controls.Add($pnlHwNicInfo)

$lblNicInfoHdr = New-Object System.Windows.Forms.Label
$lblNicInfoHdr.Text      = "NIC Information"
$lblNicInfoHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$lblNicInfoHdr.ForeColor = $ColText
$lblNicInfoHdr.BackColor = [System.Drawing.Color]::Transparent
$lblNicInfoHdr.Location  = New-Object System.Drawing.Point(10, 8)
$lblNicInfoHdr.AutoSize  = $true
$pnlHwNicInfo.Controls.Add($lblNicInfoHdr)

$script:hwNicInfoLines = @{}
$infoRows = @("Model","MAC Base","Driver","Total ports","PoE Mgmt")
$ny = 26
foreach ($row in $infoRows) {
    $lblL = New-Object System.Windows.Forms.Label
    $lblL.Text      = "$($row):"
    $lblL.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblL.ForeColor = $ColMuted
    $lblL.BackColor = [System.Drawing.Color]::Transparent
    $lblL.Location  = New-Object System.Drawing.Point(10, $ny)
    $lblL.Size      = New-Object System.Drawing.Size(72, 14)
    $pnlHwNicInfo.Controls.Add($lblL)
    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text      = "--"
    $lblV.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblV.ForeColor = $ColText
    $lblV.BackColor = [System.Drawing.Color]::Transparent
    $lblV.Location  = New-Object System.Drawing.Point(82, $ny)
    $lblV.Size      = New-Object System.Drawing.Size(140, 14)
    $lblV.AutoEllipsis = $true
    $pnlHwNicInfo.Controls.Add($lblV)
    $script:hwNicInfoLines[$row] = $lblV
    $ny += 16
}

# Tooltip on the PoE Mgmt value — explains the "0 W is normal" case for the
# unsupported card models (GIE64 / I350 / I354) so agents don't chase a
# non-issue.
$script:hwPoeNoteTip = New-Object System.Windows.Forms.ToolTip
$script:hwPoeNoteTip.AutoPopDelay = 12000
$script:hwPoeNoteTip.InitialDelay = 400

$pnlHwLegend = New-Object System.Windows.Forms.Panel
$pnlHwLegend.Size      = New-Object System.Drawing.Size(228, 86)
$pnlHwLegend.Location  = New-Object System.Drawing.Point(1124, 294)
$pnlHwLegend.BackColor = $ColCard
$pnlHwLegend.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 228, 86)), 8))
$pnlHwLegend.Anchor    = $AnchorTR
$center.Controls.Add($pnlHwLegend)

$lblLegendHdr = New-Object System.Windows.Forms.Label
$lblLegendHdr.Text      = "Status Legend"
$lblLegendHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$lblLegendHdr.ForeColor = $ColText
$lblLegendHdr.BackColor = [System.Drawing.Color]::Transparent
$lblLegendHdr.Location  = New-Object System.Drawing.Point(10, 8)
$lblLegendHdr.AutoSize  = $true
$pnlHwLegend.Controls.Add($lblLegendHdr)

$legendItems = @(
    @{ Color=$ColGreen;  Text="Linked - 1 Gbps healthy" },
    @{ Color=$ColYellow; Text="Degraded - sub-gigabit" },
    @{ Color=$ColMuted;  Text="No cable / disabled" },
    @{ Color=$ColRed;    Text="Error / fault" }
)
$ly = 26
foreach ($it in $legendItems) {
    $dot = New-Object System.Windows.Forms.Panel
    $dot.Size      = New-Object System.Drawing.Size(8, 8)
    $dot.Location  = New-Object System.Drawing.Point(12, ($ly + 3))
    $dot.BackColor = $it.Color
    $dot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
    $pnlHwLegend.Controls.Add($dot)
    $lblL = New-Object System.Windows.Forms.Label
    $lblL.Text      = $it.Text
    $lblL.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
    $lblL.ForeColor = $ColText
    $lblL.BackColor = [System.Drawing.Color]::Transparent
    $lblL.Location  = New-Object System.Drawing.Point(28, $ly)
    $lblL.Size      = New-Object System.Drawing.Size(196, 14)
    $pnlHwLegend.Controls.Add($lblL)
    $ly += 14
}

# ---- Status cards row (Y=384..474): SmartSpeed, Ping, ARP, CHU, PoE --------
$statusRowY = 384
$statusCardW = [int](($portRowW - 4*10) / 5)   # ≈ 236
$statusDefs = @(
    @{Key="SmartSpeed"; Title="SmartSpeed";    Sub="Intel events (48h)"; Icon=[char]0xE7BA}
    @{Key="PingCHU";    Title="Ping (CHU)";    Sub="ICMP reachability";  Icon=[char]0xE701}
    @{Key="ArpEntry";   Title="ARP Entry";     Sub="L2 neighbor table";  Icon=[char]0xE9D5}
    @{Key="ChuDetect";  Title="CHU Detection"; Sub="RTSP port 554";      Icon=[char]0xE722}
    @{Key="PoEBudget";  Title="PoE Budget";    Sub="ADLINK SmartPoE";    Icon=[char]0xE7E8}
)
$statusX = $portRowX0
foreach ($cd in $statusDefs) {
    $c = New-StatusCard -Title $cd.Title -X $statusX -Y $statusRowY -Icon $cd.Icon -Sub $cd.Sub -CardW $statusCardW -CardH 90
    $cards[$cd.Key] = $c
    $center.Controls.Add($c.Panel)
    $statusX += $statusCardW + 10
}

# ---- Two-column main area (Y=482..680) -------------------------------------
# LEFT (28..824 = 796 wide): Live Log card with Highlights/Detailed toggle + grid
# RIGHT (840..1252 = 412 wide): Guidance card with rtbSteps + Open Fault Isolator
$logCardX = 28; $logCardW = 796
$gdCardX  = 840; $gdCardW  = 412
$mainCardY = 482; $mainCardH = 198

# --- LEFT: Live Log card ---
$pnlLogCard = New-Object System.Windows.Forms.Panel
$pnlLogCard.Size      = New-Object System.Drawing.Size($logCardW, $mainCardH)
$pnlLogCard.Location  = New-Object System.Drawing.Point($logCardX, $mainCardY)
$pnlLogCard.BackColor = $ColCard
$pnlLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $logCardW, $mainCardH)), 8))
$center.Controls.Add($pnlLogCard)

$lblLogHdr = New-Object System.Windows.Forms.Label
$lblLogHdr.Text      = "Live Log"
$lblLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblLogHdr.ForeColor = $ColText
$lblLogHdr.BackColor = [System.Drawing.Color]::Transparent
$lblLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblLogHdr.AutoSize  = $true
$pnlLogCard.Controls.Add($lblLogHdr)

$btnLogHighlights = New-Object System.Windows.Forms.Button
$btnLogHighlights.Text      = "Highlights"
$btnLogHighlights.Size      = New-Object System.Drawing.Size(82, 22)
$btnLogHighlights.Location  = New-Object System.Drawing.Point(($logCardW - 188), 11)
$btnLogHighlights.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLogHighlights.FlatAppearance.BorderSize = 0
$btnLogHighlights.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$btnLogHighlights.BackColor = $ColAccent
$btnLogHighlights.ForeColor = [System.Drawing.Color]::White
$btnLogHighlights.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnLogHighlights.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,82,22)),4))
$pnlLogCard.Controls.Add($btnLogHighlights)

$btnLogDetailed = New-Object System.Windows.Forms.Button
$btnLogDetailed.Text      = "Detailed"
$btnLogDetailed.Size      = New-Object System.Drawing.Size(74, 22)
$btnLogDetailed.Location  = New-Object System.Drawing.Point(($logCardW - 100), 11)
$btnLogDetailed.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLogDetailed.FlatAppearance.BorderSize = 0
$btnLogDetailed.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$btnLogDetailed.BackColor = $ColNavHover
$btnLogDetailed.ForeColor = $ColMuted
$btnLogDetailed.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnLogDetailed.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,74,22)),4))
$pnlLogCard.Controls.Add($btnLogDetailed)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = ""
$lblStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblStatus.ForeColor = $ColMuted
$lblStatus.BackColor = [System.Drawing.Color]::Transparent
$lblStatus.Location  = New-Object System.Drawing.Point(16, 40)
$lblStatus.Size      = New-Object System.Drawing.Size(($logCardW - 32), 18)
$pnlLogCard.Controls.Add($lblStatus)

$dgvLog = New-LogGrid -X 8 -Y 62 -W ($logCardW - 16) -H ($mainCardH - 70) -LabelColW 180
$pnlLogCard.Controls.Add($dgvLog)

# --- RIGHT: Guidance card ---
$pnlGuideCard = New-Object System.Windows.Forms.Panel
$pnlGuideCard.Size      = New-Object System.Drawing.Size($gdCardW, $mainCardH)
$pnlGuideCard.Location  = New-Object System.Drawing.Point($gdCardX, $mainCardY)
$pnlGuideCard.BackColor = $ColCard
$pnlGuideCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $gdCardW, $mainCardH)), 8))
$pnlGuideCard.Anchor    = $AnchorTR
$center.Controls.Add($pnlGuideCard)

$lblGdHdr = New-Object System.Windows.Forms.Label
$lblGdHdr.Text      = "Next Steps & Guidance"
$lblGdHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblGdHdr.ForeColor = $ColText
$lblGdHdr.BackColor = [System.Drawing.Color]::Transparent
$lblGdHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblGdHdr.AutoSize  = $true
$pnlGuideCard.Controls.Add($lblGdHdr)

$lblLastRunVal = New-Object System.Windows.Forms.Label
$lblLastRunVal.Text      = "No runs yet"
$lblLastRunVal.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblLastRunVal.ForeColor = $ColMuted
$lblLastRunVal.BackColor = [System.Drawing.Color]::Transparent
$lblLastRunVal.Location  = New-Object System.Drawing.Point(16, 32)
$lblLastRunVal.Size      = New-Object System.Drawing.Size(($gdCardW - 32), 16)
$lblLastRunVal.AutoEllipsis = $true
$pnlGuideCard.Controls.Add($lblLastRunVal)

$rtbSteps = New-Object System.Windows.Forms.RichTextBox
$rtbSteps.Size        = New-Object System.Drawing.Size(($gdCardW - 32), ($mainCardH - 130))
$rtbSteps.Location    = New-Object System.Drawing.Point(16, 56)
$rtbSteps.BackColor   = $ColCard
$rtbSteps.ForeColor   = $ColText
$rtbSteps.Font        = New-Object System.Drawing.Font("Segoe UI", 9)
$rtbSteps.ReadOnly    = $true
$rtbSteps.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbSteps.ScrollBars  = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbSteps.Text        = "Run the diagnostic to see guidance here."
$pnlGuideCard.Controls.Add($rtbSteps)

$btnGoGuide = New-Object System.Windows.Forms.Button
$btnGoGuide.Text      = "Open Fault Isolator  " + [char]0x2192
$btnGoGuide.Size      = New-Object System.Drawing.Size(($gdCardW - 32), 32)
$btnGoGuide.Location  = New-Object System.Drawing.Point(16, ($mainCardH - 64))
$btnGoGuide.BackColor = $ColAccent
$btnGoGuide.ForeColor = [System.Drawing.Color]::White
$btnGoGuide.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnGoGuide.FlatAppearance.BorderSize = 0
$btnGoGuide.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$btnGoGuide.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnGoGuide.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ($gdCardW - 32), 32)), 6))
$pnlGuideCard.Controls.Add($btnGoGuide)

$btnAdapterSettings = New-Object System.Windows.Forms.Button
$btnAdapterSettings.Text      = "Open Adapter Settings"
$btnAdapterSettings.Size      = New-Object System.Drawing.Size(($gdCardW - 32), 28)
$btnAdapterSettings.Location  = New-Object System.Drawing.Point(16, ($mainCardH - 28))
$btnAdapterSettings.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAdapterSettings.FlatAppearance.BorderColor = $ColBorder
$btnAdapterSettings.FlatAppearance.BorderSize  = 1
$btnAdapterSettings.BackColor = $ColBg
$btnAdapterSettings.ForeColor = $ColText
$btnAdapterSettings.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$btnAdapterSettings.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnAdapterSettings.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ($gdCardW - 32), 28)), 5))
# Move Adapter Settings just below the rtbSteps area; Open Fault Isolator stays primary above it.
$btnAdapterSettings.Location  = New-Object System.Drawing.Point(16, ($mainCardH - 30))
$btnGoGuide.Location          = New-Object System.Drawing.Point(16, ($mainCardH - 66))
$rtbSteps.Size                = New-Object System.Drawing.Size(($gdCardW - 32), ($mainCardH - 132))
$pnlGuideCard.Controls.Add($btnAdapterSettings)

# Hidden Clear link compat — replaced by per-row clear behavior on rerun.
$lnkClear = New-Object System.Windows.Forms.LinkLabel
$lnkClear.Visible = $false
$lnkClear.Size    = New-Object System.Drawing.Size(0, 0)
$center.Controls.Add($lnkClear)

# ---- Bottom action bar (Y=698) — Export | Run / Cancel --------------------
$camActions = New-ActionBar -Parent $center -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
$btnRun     = $camActions.PrimaryBtn
$btnExport  = $camActions.ExportBtn

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text      = "Cancel"
$btnCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnCancel.Location  = New-Object System.Drawing.Point(($camActions.Bar.Width - 320), 10)
$btnCancel.BackColor = $ColRed
$btnCancel.ForeColor = [System.Drawing.Color]::White
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.FlatAppearance.BorderSize = 0
$btnCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnCancel.Visible   = $false
$btnCancel.Anchor    = $AnchorTR
$btnCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$camActions.Bar.Controls.Add($btnCancel)

# Secondary actions (Copy Summary, Copy Log, Save Log) — small text buttons in
# the action bar to keep them discoverable without bloating the layout.
$btnCopySummary = New-Object System.Windows.Forms.Button
$btnCopySummary.Text      = "Copy Summary"
$btnCopySummary.Size      = New-Object System.Drawing.Size(120, 36)
$btnCopySummary.Location  = New-Object System.Drawing.Point(170, 10)
$btnCopySummary.BackColor = $ColCard
$btnCopySummary.ForeColor = $ColText
$btnCopySummary.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopySummary.FlatAppearance.BorderColor = $ColBorder
$btnCopySummary.FlatAppearance.BorderSize  = 1
$btnCopySummary.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnCopySummary.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnCopySummary.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 120, 36)), 6))
$camActions.Bar.Controls.Add($btnCopySummary)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text      = "Copy Log"
$btnCopy.Size      = New-Object System.Drawing.Size(90, 36)
$btnCopy.Location  = New-Object System.Drawing.Point(298, 10)
$btnCopy.BackColor = $ColCard
$btnCopy.ForeColor = $ColText
$btnCopy.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCopy.FlatAppearance.BorderColor = $ColBorder
$btnCopy.FlatAppearance.BorderSize  = 1
$btnCopy.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnCopy.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnCopy.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 90, 36)), 6))
$camActions.Bar.Controls.Add($btnCopy)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text      = "Save Log"
$btnSave.Size      = New-Object System.Drawing.Size(90, 36)
$btnSave.Location  = New-Object System.Drawing.Point(396, 10)
$btnSave.BackColor = $ColCard
$btnSave.ForeColor = $ColText
$btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSave.FlatAppearance.BorderColor = $ColBorder
$btnSave.FlatAppearance.BorderSize  = 1
$btnSave.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnSave.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSave.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 90, 36)), 6))
$camActions.Bar.Controls.Add($btnSave)

# ---- $right / $rightBorder compat stubs ----------------------------------
# Show-Panel toggles these via its $ShowRight parameter; keep zero-sized hidden
# stubs so the legacy "Show-Panel $center $true" call doesn't NPE. Camera
# Connectivity now contains its guidance card inside $center, so these are
# never actually visible.
$rightBorder = New-Object System.Windows.Forms.Panel
$rightBorder.Size = New-Object System.Drawing.Size(0, 0); $rightBorder.Visible = $false
$form.Controls.Add($rightBorder)
$right = New-Object System.Windows.Forms.Panel
$right.Size = New-Object System.Drawing.Size(0, 0); $right.Visible = $false
$form.Controls.Add($right)

# ---------- NIC Port Diagram refresh (relocated from PoeNicHardware, v1.0.47) -
# Pulls live link state from Get-NetAdapter and populates: the colored LED
# dots in each jack (canvas), the 4 port detail boxes, and the NIC Information
# sidebar. Tier color logic mirrors the original Hardware-tab implementation.

# Detect what's plugged into a single port via its ARP neighbor table.
# Mirrors the discovery logic in the diagnostic runspace ($CamScript) but
# runs synchronously off the UI thread for live monitoring (~50ms / port).
#
# Returns a hashtable:
#   @{ Label = "Main Camera" | "OCR (100M)" | "OCR (1G)" | "No device" | "Unknown"
#      Mac   = "AA-BB-CC-..." (remote device's MAC, from ARP)
#      Ip    = "169.254.x.x"  (remote device's IP, from ARP) }
#
# When a port has more than one ARP neighbor (e.g. stale entries from a
# previous swap), the most-recently-active one wins — Reachable > Stale,
# tiebreak by lowest IP. The returned MAC is what's actually responding
# right now, which fixes the false-positive "OCR" labelling we get when
# only the OUI prefix is checked.
function Get-PortDevice {
    param([System.Object]$Adapter, [string]$LinkSpeed)
    $result = @{ Label = "No device"; Mac = ""; Ip = "" }
    if (-not $Adapter -or $Adapter.Status -ne "Up") { return $result }
    try {
        $neighbors = @(Get-NetNeighbor -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress  -like "169.254.*" -and
                $_.State      -ne  "Unreachable" -and
                $_.LinkLayerAddress -and
                # Skip multicast/broadcast (LSB of first octet set)
                ([Convert]::ToInt32(($_.LinkLayerAddress -split '-')[0], 16) -band 1) -eq 0
            })
        if ($neighbors.Count -eq 0) { return $result }

        # Pick the "most active" neighbor: Reachable wins over Stale wins
        # over anything else. Within the same state, lowest IP wins so
        # the choice is deterministic across refreshes.
        $statePriority = @{ Reachable = 3; Permanent = 2; Stale = 1 }
        $primary = $neighbors |
            Sort-Object @{Expression = { if ($statePriority.ContainsKey([string]$_.State)) { $statePriority[[string]$_.State] } else { 0 } }; Descending = $true},
                       IPAddress |
            Select-Object -First 1

        $result.Mac = "$($primary.LinkLayerAddress)"
        $result.Ip  = "$($primary.IPAddress)"

        # 1) Authoritative role from Pixellot's own config (cameras.cfg /
        #    pip.cfg). When present this is the same data the Pixellot HW
        #    Info screen shows — no guessing required.
        if ($script:PixCameraRoles -and $script:PixCameraRoles.ContainsKey($result.Ip)) {
            $result.Label = $script:PixCameraRoles[$result.Ip]
            return $result
        }
        # 2) Speed-based fallback for Pixellot OUI devices not in the
        #    config (different install path, swapped camera the agent
        #    hasn't re-registered yet, etc.). Mirrors the diagnostic's
        #    own logic: OCR cameras are 100 Mbps-only, main cameras are
        #    always gigabit. We don't try to subtype with the 4th MAC
        #    octet — that produced false positives in v1.0.50 because
        #    different camera revisions share overlapping prefixes.
        if ($primary.LinkLayerAddress -like "$OcrMacOui-*") {
            $is100M = ($LinkSpeed -match '^\s*100\s*Mbps')
            $is1G   = ($LinkSpeed -match '\b\d+\s*Gbps\b' -or $LinkSpeed -match '^\s*1000\s*Mbps')
            if     ($is100M) { $result.Label = "OCR Camera" }
            elseif ($is1G)   { $result.Label = "Main Camera (probable)" }
            else             { $result.Label = "Pixellot Camera" }
        } else {
            $result.Label = "Unknown device"
        }
        return $result
    } catch {
        $result.Label = "Unknown"
        return $result
    }
}

function Update-HwPortDiagram {
    $sortedNics = @()
    try {
        $allNics = @(Get-NetAdapter -ErrorAction SilentlyContinue)
        $matched = @()
        foreach ($nic in $allNics) {
            if (-not $nic.InterfaceDescription -or -not $nic.MacAddress) { continue }
            foreach ($pat in $NicDriverPatterns) {
                if ($nic.InterfaceDescription -like $pat) { $matched += $nic; break }
            }
        }
        $sortedNics = @($matched | Sort-Object MacAddress)
    } catch { }

    if ($sortedNics.Count -eq 0) {
        try {
            $sortedNics = @(
                Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                    Where-Object { $_.MacAddress } |
                    Sort-Object MacAddress |
                    Select-Object -First 4
            )
        } catch { }
    }

    $ledColors    = @($ColMuted, $ColMuted, $ColMuted, $ColMuted)
    $speedLabels  = @("", "", "", "")
    for ($tileIdx = 0; $tileIdx -lt 4; $tileIdx++) {
        $tile = $script:hwPortTiles[$tileIdx]
        $portNum  = $tile.PortNum
        $sortIdx  = $portNum - 1
        if ($sortIdx -lt $sortedNics.Count) {
            $nic = $sortedNics[$sortIdx]
            $mac = $nic.MacAddress
            $speed = $nic.LinkSpeed
            $isUp  = ($nic.Status -eq "Up")
            $speedLabel = if ($speed -and $speed -match '(\d+)\s*Gbps')      { "$($Matches[1]) Gbps" } `
                          elseif ($speed -and $speed -match '(\d+)\s*Mbps') { "$($Matches[1]) Mbps" } `
                          elseif ($isUp)                                     { "Up" } `
                          else                                                { "--" }
            # >= 1 Gbps healthy, sub-gigabit linked = warn, else off
            $gbpsMatch = [regex]::Match($speed, '(\d+(?:\.\d+)?)\s*Gbps')
            $tier = if (-not $isUp) { "off" } `
                    elseif ($gbpsMatch.Success -and ([double]$gbpsMatch.Groups[1].Value) -ge 1) { "ok" } `
                    elseif ($speed -match '(100|10)\s*Mbps') { "warn" } `
                    else { "info" }
            $accentColor = switch ($tier) {
                "ok"   { $ColGreen }
                "warn" { $ColYellow }
                "off"  { $ColMuted }
                default{ $ColAccent }
            }
            $statusText = switch ($tier) {
                "ok"   { "Linked" }
                "warn" { "Degraded" }
                "off"  { "No Link" }
                default{ "Linked" }
            }
            $errCount = "--"
            try {
                $stats = Get-NetAdapterStatistics -Name $nic.Name -ErrorAction SilentlyContinue
                if ($stats) {
                    $err = [long]([long]$stats.OutboundPacketsWithErrors + [long]$stats.ReceivedPacketsWithErrors)
                    $errCount = "$err"
                }
            } catch { }

            # Live remote-endpoint detection. Returns @{ Label; Mac; Ip }
            # — Mac and Ip describe the device on the OTHER end of the
            # cable (camera or OCR), discovered via ARP. The local NIC's
            # MAC ($mac, captured above) is no longer shown in the port
            # box; it lives in the NIC Information sidebar instead.
            $devInfo     = Get-PortDevice -Adapter $nic -LinkSpeed $speed
            $deviceLabel = $devInfo.Label
            $remoteMac   = if ($devInfo.Mac) { $devInfo.Mac } else { "--" }
            $remoteIp    = if ($devInfo.Ip)  { $devInfo.Ip }  else { "--" }
            $deviceColor = switch -Wildcard ($deviceLabel) {
                "Main Camera"  { $ColGreen }
                "OCR (1G)"     { $ColAccent }
                "OCR (100M)"   { $ColAccent }
                "No device"    { $ColMuted }
                default        { $ColYellow }
            }

            $tile.StatusIcn.Text      = if ($tier -eq "off") { [char]0x26AB } elseif ($tier -eq "warn") { [char]0x26A0 } else { [char]0x25CF }
            $tile.StatusIcn.ForeColor = $accentColor
            $tile.StatusTxt.Text      = $statusText
            $tile.StatusTxt.ForeColor = $accentColor
            $tile.DeviceV.Text        = $deviceLabel
            $tile.DeviceV.ForeColor   = $deviceColor
            $tile.SpeedV.Text         = $speedLabel
            $tile.SpeedV.ForeColor    = if ($isUp) { $accentColor } else { $ColMuted }
            $tile.IpV.Text            = $remoteIp
            $tile.IpV.ForeColor       = if ($remoteIp -ne "--") { $ColText } else { $ColMuted }
            $tile.MacV.Text           = $remoteMac
            $tile.MacV.ForeColor      = if ($remoteMac -ne "--") { $ColText } else { $ColMuted }
            $tile.ErrV.Text           = $errCount
            $tile.ErrV.ForeColor      = if ($errCount -ne "--" -and [int]$errCount -gt 0) { $ColYellow } else { $ColText }
            $tile.NicName             = $nic.Name
            $ledColors[$portNum - 1]  = $accentColor
            $speedLabels[$portNum - 1] = $speedLabel
        } else {
            $tile.StatusIcn.Text      = [char]0x26AB
            $tile.StatusIcn.ForeColor = $ColMuted
            $tile.StatusTxt.Text      = "Not detected"
            $tile.StatusTxt.ForeColor = $ColMuted
            $tile.DeviceV.Text        = "--"
            $tile.SpeedV.Text         = "--"
            $tile.IpV.Text            = "--"
            $tile.MacV.Text           = "--"
            $tile.ErrV.Text           = "--"
            $tile.NicName             = $null
            $speedLabels[$portNum - 1] = ""
        }
    }

    $script:hwPortLedColors    = $ledColors
    $script:hwPortSpeedLabels  = $speedLabels
    if ($pnlHwNicCanvas) { $pnlHwNicCanvas.Invalidate() }

    if ($script:hwNicInfoLines) {
        $modelInfo = $null
        try { $modelInfo = Get-AdlinkCardInfo $sortedNics } catch { }
        $modelStr = if ($modelInfo -and $modelInfo.Label) { $modelInfo.Label } `
                    elseif ($sortedNics.Count -gt 0)       { $sortedNics[0].InterfaceDescription } `
                    else                                    { "Not detected" }
        $macBase = if ($sortedNics.Count -gt 0) { $sortedNics[0].MacAddress } else { "--" }
        $driverState = if ($sortedNics.Count -gt 0 -and $sortedNics[0].Status) { "Loaded" } else { "Not loaded" }
        $totalPorts  = "$($sortedNics.Count) detected"

        # PoE management capability — derived from the card model. When this
        # card doesn't expose SmartPoE telemetry we surface that explicitly so
        # a "0 W" budget reading isn't mistaken for a hardware fault.
        $poeMgmtSupported = $false
        if ($modelInfo -and $modelInfo.ContainsKey('PoeMgmtSupported')) { $poeMgmtSupported = [bool]$modelInfo.PoeMgmtSupported }
        $poeMgmtText  = if ($sortedNics.Count -eq 0) { "--" } `
                        elseif ($poeMgmtSupported)   { "Supported" } `
                        else                          { "Not supported" }
        $poeMgmtColor = if ($sortedNics.Count -eq 0) { $ColMuted } `
                        elseif ($poeMgmtSupported)   { $ColGreen } `
                        else                          { $ColYellow }
        $poeMgmtTip   = if (-not $poeMgmtSupported -and $sortedNics.Count -gt 0) {
            "This NIC model doesn't expose ADLINK SmartPoE telemetry, so the PoE Budget card will read 0 W or N/A. That's normal for this card and is not a fault — power is still delivered to the cameras, it just can't be monitored from software."
        } else { "" }

        if ($script:hwNicInfoLines["Model"])       { $script:hwNicInfoLines["Model"].Text       = $modelStr }
        if ($script:hwNicInfoLines["MAC Base"])    { $script:hwNicInfoLines["MAC Base"].Text    = $macBase }
        if ($script:hwNicInfoLines["Driver"])      { $script:hwNicInfoLines["Driver"].Text      = $driverState }
        if ($script:hwNicInfoLines["Driver"])      { $script:hwNicInfoLines["Driver"].ForeColor = if ($driverState -eq "Loaded") { $ColGreen } else { $ColRed } }
        if ($script:hwNicInfoLines["Total ports"]) { $script:hwNicInfoLines["Total ports"].Text = $totalPorts }
        if ($script:hwNicInfoLines["PoE Mgmt"]) {
            $script:hwNicInfoLines["PoE Mgmt"].Text      = $poeMgmtText
            $script:hwNicInfoLines["PoE Mgmt"].ForeColor = $poeMgmtColor
            if ($script:hwPoeNoteTip) {
                try { $script:hwPoeNoteTip.SetToolTip($script:hwNicInfoLines["PoE Mgmt"], $poeMgmtTip) } catch { }
            }
        }
    }
}

# Map a diagnostic-result string ("PASS", "FAIL", "DEGRADED", etc.) into a
# (color, status text) pair we can paint onto a port detail box. Called from
# the timer when $sync.Cards[<NicName>] changes during a run.
function Update-CamPortBoxFromDiag {
    param([hashtable]$Tile, [string]$Result, [string]$Status)
    if (-not $Tile -or -not $Result -or $Result -eq "--") { return }
    $color = switch ($Status) {
        "ok"   { $ColGreen }
        "warn" { $ColYellow }
        "fail" { $ColRed }
        default{ $ColMuted }
    }
    $Tile.StatusTxt.Text      = $Result
    $Tile.StatusTxt.ForeColor = $color
    $Tile.StatusIcn.ForeColor = $color
    $Tile.StatusIcn.Text      = if ($Status -eq "fail") { [char]0x26A0 } elseif ($Status -eq "warn") { [char]0x26A0 } elseif ($Status -eq "ok") { [char]0x25CF } else { [char]0x26AB }
}

# Rebuild the Test Scope dropdown items so each one shows the live device
# detected on that port. Preserves the user's current selection by index
# (index 0 is always "All Ports"). Called on panel visibility change so a
# tech who plugs in a new camera and switches tabs sees the update.
function Update-NicDropdown {
    if (-not $cboNic) { return }
    try {
        $prevIdx = $cboNic.SelectedIndex
        $cboNic.BeginUpdate()
        $cboNic.Items.Clear()
        $cboNic.Items.Add("All Ports") | Out-Null
        $sortedDetected = @($script:detectedNics | Sort-Object MacAddress)
        $portIdx = 1
        foreach ($n in $sortedDetected) {
            $deviceLabel = "No device"
            try {
                $devInfo = Get-PortDevice -Adapter $n -LinkSpeed $n.LinkSpeed
                if ($devInfo -and $devInfo.Label) { $deviceLabel = $devInfo.Label }
            } catch { }
            $cboNic.Items.Add("Port $portIdx — $($n.Name) — $deviceLabel") | Out-Null
            $portIdx++
        }
        if ($prevIdx -ge 0 -and $prevIdx -lt $cboNic.Items.Count) {
            $cboNic.SelectedIndex = $prevIdx
        } elseif ($cboNic.Items.Count -gt 0) {
            $cboNic.SelectedIndex = 0
        }
        $cboNic.EndUpdate()
    } catch { }
}

# Refresh the diagram on every panel show (link state may have changed since
# last visit) and immediately at module load so the diagram isn't blank before
# the user runs anything.
$center.Add_VisibleChanged({
    if ($center.Visible) {
        # Refresh the IP→role table from cameras.cfg/pip.cfg before the
        # diagram and dropdown re-paint. Picks up role changes (e.g. tech
        # swapped a camera and the agent rewrote the config) without a
        # tool restart.
        try { $script:PixCameraRoles = Get-PixellotCameraRoles } catch { }
        try { Update-HwPortDiagram } catch { }
        try { Update-NicDropdown }   catch { }
        if ($script:hwLiveTimer) { $script:hwLiveTimer.Start() }
    } else {
        if ($script:hwLiveTimer) { $script:hwLiveTimer.Stop() }
    }
})
try { Update-HwPortDiagram } catch { }

# ---------- Live port-status polling -----------------------------------------
# Get-NetAdapter is fast (~30-60ms) so we can refresh the NIC diagram and the
# port detail boxes every few seconds while the Camera Connectivity panel is
# visible. The user no longer has to re-run the diagnostic just to see whether
# a cable was plugged in or a port came back up. Skipped while a diagnostic
# run is active so we don't fight with the runspace's own card writes.
$script:hwLiveTimer = New-Object System.Windows.Forms.Timer
$script:hwLiveTimer.Interval = 3000
$script:hwLiveTimer.Add_Tick({
    if ($sync.Running) { return }
    try { Update-HwPortDiagram } catch { }
})
# Start immediately if the Camera panel is the initial view (rare but
# possible when launched with -StartTab Camera). Otherwise the visibility
# handler above will start/stop it.
if ($center -and $center.Visible) { $script:hwLiveTimer.Start() }
$form.Add_FormClosing({ if ($script:hwLiveTimer) { $script:hwLiveTimer.Stop() } })

# ---------- Timer (polls $sync every 300ms, updates UI) ---------------------
$script:runspace    = $null
$script:diagPs      = $null
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
            # Per-NIC diagnostic results: mirror the result onto the matching
            # port detail box's Status text so the diagram surfaces both live
            # link state AND diagnostic outcome (replaces the v1.0.46 P1..P4
            # status cards).
            if ($script:hwPortTiles) {
                foreach ($pt in $script:hwPortTiles) {
                    if ($pt.NicName -and $pt.NicName -eq $key) {
                        Update-CamPortBoxFromDiag $pt $sc.Value $sc.Status
                        break
                    }
                }
            }
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
        # Update Camera section header pill (v1.0.46 redesign)
        if ($camHeader -and $camHeader.PillTitle.Text -ne "Running") {
            Set-SectionPill $camHeader "neutral" "Running"
        }
    }

    if ($sync.UpdateAvailable -and -not $lblUpdate.Visible) {
        $lblUpdate.Text = "Update available: v$($sync.UpdateAvailable)"
        $lblUpdate.Visible = $true; $btnUpdate.Visible = $true
    }

    if ($sync.Complete -and -not $sync.Running) {
        $timer.Stop()
        $btnCancel.Visible = $false
        # R2: surface any runspace errors from the camera diagnostic run.
        $camErrs = Get-DiagRunspaceErrors $script:camDiagState
        foreach ($em in $camErrs) { Add-LogRow $dgvLog "Runspace error" $em "Fail" }
        $btnRun.Enabled = $true
        $btnRun.Text = if ($cboNic.SelectedIndex -le 0) {
            [char]0x25B6 + "  Run Test"
        } else {
            $n = Get-NicNameFromCbo ($cboNic.SelectedItem -as [string])
            [char]0x25B6 + "  Test $n Only"
        }
        $btnRetest.Enabled = $true

        if ($sync.AllClear) {
            $pnlBadge.BackColor = $ColBadgeOkBg
            $lblBadge.ForeColor = $ColGreen; $lblBadge.Text = "All Clear"
            $pnlBadgeDot.BackColor = $ColGreen
            $pnlSbarDot.BackColor = $ColGreen; $lblSbarStatus.Text = "Status: All Clear"
            $pnlSideDot.BackColor = $ColGreen; $lblSideStatus.Text = "All Clear"
            if ($camHeader) { Set-SectionPill $camHeader "ok" "All Clear" }
        } else {
            $pnlBadge.BackColor = $ColBadgeErrBg
            $lblBadge.ForeColor = $ColRed; $lblBadge.Text = "Issues Found"
            $pnlBadgeDot.BackColor = $ColRed
            $pnlSbarDot.BackColor = $ColRed; $lblSbarStatus.Text = "Status: Issues Found"
            $pnlSideDot.BackColor = $ColRed; $lblSideStatus.Text = "Issues Found"
            if ($camHeader) { Set-SectionPill $camHeader "fail" "Issues Found" }
        }
        $lblSbarLastRun.Text = "Last Run: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

        Show-OverviewSteps

        $dt = Get-Date -Format "yyyy-MM-dd HH:mm"
        $trend = Get-PortTrendSummary
        $trendSuffix = if ($trend) { "   .   $trend" } else { "" }
        $lblLastRunVal.Text = "$($sync.LastRunLine)   $dt$trendSuffix"
        $btnGoGuide.Visible = $true
        Update-GuidePortDropdown
        # Refresh live link state in the port diagram (in case renegotiation
        # bumped a port up/down during the test).
        try { Update-HwPortDiagram } catch { }
    }
})

# ---------- Button Handlers -------------------------------------------------
function Start-CameraConnDiagnostic {
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
    if ($camHeader) { Set-SectionPill $camHeader "neutral" "Running" }
    $lblLastRunVal.Text = "Running diagnostic..."
    $btnRun.Enabled = $false; $btnRun.Text = "  Running..."
    $btnRetest.Enabled = $false
    $script:spinIdx = 0; $lblStatus.ForeColor = $ColAccent; $lblStatus.Text = " |  Starting..."

    # R2/R13: standardised runspace hosting with TLS-1.2 + IAsyncResult capture.
    $filterNicVal = if ($cboNic.SelectedIndex -gt 0) { Get-NicNameFromCbo ($cboNic.SelectedItem -as [string]) } else { "" }
    $script:camDiagState = Start-DiagRunspace `
        -Script    $DiagScript `
        -Parameters @{
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
            PixCameraRoles     = $script:PixCameraRoles
            FilterNic          = $filterNicVal
            PoeDllPath         = if ($PoeDllPath) { $PoeDllPath } else { "" }
            PoeMgmtSupported   = if ($script:nicCardInfo) { [bool]$script:nicCardInfo.PoeMgmtSupported } else { $true }
        } `
        -Previous $script:camDiagState
    $script:runspace = $script:camDiagState.Runspace
    $script:diagPs   = $script:camDiagState.Ps
    $timer.Start()
}

$btnRun.Add_Click({ Start-CameraConnDiagnostic })

$btnRetest.Add_Click({ $btnRun.PerformClick() })

$btnCancel.Add_Click({
    $sync.Cancelled = $true
    $btnCancel.Visible = $false
})

$btnAdapterSettings.Add_Click({ Start-Process "ncpa.cpl" })

$btnUpdate.Add_Click({
    $btnUpdate.Text = "  Launching..."; $btnUpdate.Enabled = $false
    try {
        if (-not $global:ScriptUrl) {
            throw "Update URL not configured (ScriptUrl is empty)."
        }
        Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$global:ScriptUrl' | iex`""
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
            $btnRun.Text = [char]0x25B6 + "  Run Test"
            $lblRunSteps.Text = "Runs: Port Speed  *  Ping  *  ARP  *  CHU Detection"
        } else {
            $nicName = Get-NicNameFromCbo ($cboNic.SelectedItem -as [string])
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

