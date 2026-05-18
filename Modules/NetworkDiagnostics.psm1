# =============================================================================
#  NetworkDiagnostics.psm1  -  Network connectivity panel
# =============================================================================

# ---------- Network connectivity test config ----------------------------------
$NetTimeoutMs = 2000

$PortTests = @(
    [PSCustomObject]@{ Protocol="UDP"; Port=53;   ProbeHost="8.8.8.8";               Reliable=$true;  Purpose="DNS";                                      Note="Real DNS query for pixellot.tv. PASS confirms UDP DNS is working." },
    [PSCustomObject]@{ Protocol="TCP"; Port=53;   ProbeHost="8.8.8.8";               Reliable=$true;  Purpose="DNS";                                      Note="" },
    [PSCustomObject]@{ Protocol="UDP"; Port=123;  ProbeHost="0.us.pool.ntp.org";      Reliable=$true;  Purpose="Clock synchronization (NTP)";              Note="Real NTP request. PASS confirms clock sync is working." },
    [PSCustomObject]@{ Protocol="TCP"; Port=443;  ProbeHost="pixellot.tv";            Reliable=$true;  Purpose="System ops, remote mgmt, video stream";    Note="" },
    # D2 fix: UDP echo to prod-echo.pixellot.tv requires the *server* to echo
    # the exact payload back. Unconfirmed server-side; if the host is rate-
    # limited or behind an ACL, every healthy VPU shows FAIL. Demoted to
    # Reliable=$false until echo behavior is verified server-side.
    [PSCustomObject]@{ Protocol="UDP"; Port=443;  ProbeHost="prod-echo.pixellot.tv";  Reliable=$false; Purpose="Video streaming - Zixi fallback on 443";   Note="UDP echo not yet verified server-side; INFO only. Firewall should allow outbound UDP 443 to Pixellot." },
    [PSCustomObject]@{ Protocol="TCP"; Port=1402; ProbeHost="scorebot.sportzcast.net"; Reliable=$true;  Purpose="SportzCast data transmission (1400-1405)";  Note="Firewall must allow outbound TCP 1400-1405 to SportzCast servers." },
    [PSCustomObject]@{ Protocol="TCP"; Port=1935; ProbeHost="scorebot.sportzcast.net"; Reliable=$true;  Purpose="SportzCast remote management";              Note="Firewall must allow outbound TCP 1935 to SportzCast servers." },
    [PSCustomObject]@{ Protocol="UDP"; Port=2088; ProbeHost="prod-echo.pixellot.tv";  Reliable=$false; Purpose="Video streaming - Zixi primary";           Note="UDP echo not yet verified server-side; INFO only. Firewall should allow outbound UDP 2088 to Pixellot." },
    [PSCustomObject]@{ Protocol="TCP"; Port=5672; ProbeHost="app.singular.live";      Reliable=$true;  Purpose="Graphics and watermark generation";        Note="Firewall must allow outbound TCP 5672 to Singular. Blocking this port prevents scoreboards and watermarks from appearing on stream." },
    [PSCustomObject]@{ Protocol="UDP"; Port=5672; ProbeHost="app.singular.live";      Reliable=$false; Purpose="Graphics and watermark generation";        Note="UDP returns no response on working VPUs. See domain test." }
)

$DomainTests = @(
    [PSCustomObject]@{ Domain="nfhsnetwork.com";                Wildcard=$true;  Purpose="Scheduling, events, watermark images";                Note="" },
    [PSCustomObject]@{ Domain="pixellot.stream";                Wildcard=$true;  Purpose="Broadcast stream to Pixellot servers (Zixi)";         Note="Stream-only destination - DNS not expected to resolve." },
    [PSCustomObject]@{ Domain="pixellot.tv";                    Wildcard=$true;  Purpose="Pixellot system management and software downloads";   Note="" },
    [PSCustomObject]@{ Domain="software.pixellot.tv";           Wildcard=$true;  Purpose="Software package downloads and updates";              Note="" },
    [PSCustomObject]@{ Domain="sportzcast.net";                 Wildcard=$true;  Purpose="SportzCast remote management and updates";            Note="" },
    [PSCustomObject]@{ Domain="app.singular.live";              Wildcard=$true;  Purpose="Broadcast scoreboard graphics (port 5672 indicator)"; Note="" },
    [PSCustomObject]@{ Domain="balena-cloud.com";               Wildcard=$true;  Purpose="Linux OS management";                                 Note="Required for Linux-based Pixellots." },
    [PSCustomObject]@{ Domain="logmein.com";                    Wildcard=$true;  Purpose="Windows remote control";                              Note="Required for Windows-based Pixellots." },
    [PSCustomObject]@{ Domain="s3.amazonaws.com";               Wildcard=$false; Purpose="Canopy remote monitoring (leaf-swu)";                 Note="" },
    [PSCustomObject]@{ Domain="leaf-uploads.s3.amazonaws.com";  Wildcard=$false; Purpose="Canopy uploads";                                     Note="" },
    [PSCustomObject]@{ Domain="leaf-downloads.s3.amazonaws.com"; Wildcard=$false; Purpose="Canopy downloads";                                  Note="" },
    [PSCustomObject]@{ Domain="gocanopy.io";                     Wildcard=$true;  Purpose="Canopy remote system management and monitoring";     Note="" }
)

# ---------- Network diagnostic engine (runs in its own background runspace) --
$NetScript = {
    $sync.NetRunning   = $true
    $sync.NetComplete  = $false
    $sync.NetCancelled = $false
    $sync.NetAllClear  = $false
    $sync.NetBasicOk   = $false
    $sync.NetPortPass  = 0; $sync.NetPortFail = 0; $sync.NetPortInfo = 0
    $sync.NetDomainPass = 0; $sync.NetDomainFail = 0; $sync.NetDomainInfo = 0
    $sync.NetAdapters.Clear()
    $item = $null
    while ($sync.NetQueue.TryDequeue([ref]$item)) { }

    function Net-Log {
        param([string]$Label, [string]$Result, [string]$Level = "Info")
        $sync.NetQueue.Enqueue(@{ Label = $Label; Result = $Result; L = $Level })
    }
    function Net-Section {
        param([string]$Title)
        $sync.NetQueue.Enqueue(@{ Label = ""; Result = $Title; L = "Section" })
    }
    function Set-NetCard {
        param([string]$Key, [string]$Value, [string]$Status)
        $sync.Cards[$Key]   = @{ Value = $Value; Status = $Status }
        $sync["_nc_$Key"]   = $Value    # direct write to synchronized hashtable — guaranteed cross-thread visibility
        $sync["_ncs_$Key"]  = $Status
    }
    function Test-TcpConnect {
        param([string]$HostName, [int]$Port, [int]$TimeoutMs)
        $tcp = $null
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $c   = $tcp.BeginConnect($HostName, $Port, $null, $null)
            $ok  = $c.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok) { try { $tcp.EndConnect($c) } catch { $ok = $false } }
            return $ok
        } catch { return $false }
        finally { if ($tcp) { try { $tcp.Close() } catch { } } }
    }
    function Test-UdpDns {
        param([string]$Server, [int]$TimeoutMs)
        $udp = $null
        try {
            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Client.ReceiveTimeout = $TimeoutMs
            # Real DNS A-record query for pixellot.tv
            $q = [byte[]]@(0xAB,0x01,0x01,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x00,
                           0x08,[byte][char]'p',[byte][char]'i',[byte][char]'x',[byte][char]'e',
                           [byte][char]'l',[byte][char]'l',[byte][char]'o',[byte][char]'t',
                           0x02,[byte][char]'t',[byte][char]'v',
                           0x00,0x00,0x01,0x00,0x01)
            $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($Server), 53)
            $udp.Send($q, $q.Length, $ep) | Out-Null
            $r  = $udp.Receive([ref]$ep)
            return ($r -and $r.Length -gt 6 -and ($r[3] -band 0x0F) -eq 0)
        } catch { return $false }
        finally { if ($udp) { try { $udp.Close() } catch { } } }
    }
    function Test-UdpNtp {
        param([string]$Server, [int]$TimeoutMs)
        $udp = $null
        try {
            $ar = [System.Net.Dns]::BeginGetHostAddresses($Server, $null, $null)
            if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
            $addrs = [System.Net.Dns]::EndGetHostAddresses($ar)
            if (-not $addrs -or $addrs.Length -eq 0) { return $false }
            $pkt = New-Object byte[] 48; $pkt[0] = 0x1B
            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Client.ReceiveTimeout = $TimeoutMs
            $ep = New-Object System.Net.IPEndPoint($addrs[0], 123)
            $udp.Send($pkt, 48, $ep) | Out-Null
            $r = $udp.Receive([ref]$ep)
            return ($r -and $r.Length -ge 48)
        } catch { return $false }
        finally { if ($udp) { try { $udp.Close() } catch { } } }
    }
    function Test-UdpEcho {
        param([string]$Server, [int]$Port, [int]$TimeoutMs)
        $udp = $null
        try {
            $ar = [System.Net.Dns]::BeginGetHostAddresses($Server, $null, $null)
            if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }
            $addrs = [System.Net.Dns]::EndGetHostAddresses($ar)
            if (-not $addrs -or $addrs.Length -eq 0) { return $false }
            $payload = [System.Text.Encoding]::ASCII.GetBytes("testing UDP on port $Port")
            $udp = New-Object System.Net.Sockets.UdpClient
            $udp.Client.ReceiveTimeout = $TimeoutMs
            $ep = New-Object System.Net.IPEndPoint($addrs[0], $Port)
            $udp.Send($payload, $payload.Length, $ep) | Out-Null
            $r = $udp.Receive([ref]$ep)
            return ([System.Text.Encoding]::ASCII.GetString($r) -eq "testing UDP on port $Port")
        } catch { return $false }
        finally { if ($udp) { try { $udp.Close() } catch { } } }
    }
    function Resolve-DomainAsync {
        param([string]$Domain, [int]$TimeoutMs)
        try {
            $ar = [System.Net.Dns]::BeginGetHostAddresses($Domain, $null, $null)
            if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $null }
            return [System.Net.Dns]::EndGetHostAddresses($ar)
        } catch { return $null }
    }

    # -- Internet check --------------------------------------------------------
    $sync.NetStep = "Checking internet connectivity..."
    Net-Section "Connectivity"
    # D7 fix: ping each target twice before declaring unreachable. Momentary
    # packet loss on a congested venue uplink used to false-fail this check.
    # NOTE: $host is a PS reserved variable (the session host) — use a renamed
    # loop variable (same lesson as v1.0.44 fix).
    $pingOk = $false
    foreach ($pingTarget in @("8.8.8.8", "1.1.1.1")) {
        if ($pingOk -or $sync.NetCancelled) { break }
        for ($pingAttempt = 0; $pingAttempt -lt 2; $pingAttempt++) {
            try {
                $r = (New-Object System.Net.NetworkInformation.Ping).Send($pingTarget, $NetTimeoutMs)
                if ($r.Status -eq "Success") { $pingOk = $true; break }
            } catch { }
            if ($pingAttempt -eq 0) { Start-Sleep -Milliseconds 500 }
        }
    }
    if ($pingOk) {
        Net-Log "Internet" "Reachable" "Pass"
        $sync.NetBasicOk = $true
        Set-NetCard "NetInternet" "Online" "ok"
        $sync["_nc_NetInternet"] = "Online"; $sync["_ncs_NetInternet"] = "ok"
    } else {
        Net-Log "Internet" "No response - check uplink adapter" "Fail"
        Set-NetCard "NetInternet" "Offline" "fail"
        $sync["_nc_NetInternet"] = "Offline"; $sync["_ncs_NetInternet"] = "fail"
    }

    if ($sync.NetCancelled) { $sync.NetRunning = $false; $sync.NetComplete = $true; return }

    # -- Adapter info ----------------------------------------------------------
    $sync.NetStep = "Reading network adapters..."
    Net-Section "Adapters"
    try {
        $ups = @(Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object Name)
        foreach ($a in $ups) {
            $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
            $gw = (Get-NetRoute    -InterfaceIndex $a.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
            $entry = [PSCustomObject]@{
                Name    = $a.Name; Desc = $a.InterfaceDescription
                IP      = if ($ip) { $ip } else { "No IP" }
                Gateway = if ($gw) { $gw } else { "-" }
                Speed   = $a.LinkSpeed
            }
            $sync.NetAdapters.Add($entry) | Out-Null
            Net-Log $a.Name "$($entry.IP)  gw $($entry.Gateway)  $($a.LinkSpeed)" "Info"
        }
        if ($ups.Count -eq 0) { Net-Log "Adapters" "No active adapters" "Warn" }
    } catch { Net-Log "Adapters" "Error reading adapters" "Warn" }

    if ($sync.NetCancelled) { $sync.NetRunning = $false; $sync.NetComplete = $true; return }

    # -- Port tests ------------------------------------------------------------
    $sync.NetStep = "Testing required ports..."
    Net-Section "Port Tests"
    $portPass = 0; $portFail = 0; $portInfo = 0
    foreach ($pt in $PortTests) {
        if ($sync.NetCancelled) { break }
        $sync.NetStep = "Testing $($pt.Protocol) $($pt.Port) -> $($pt.ProbeHost)..."
        $label = "$($pt.Protocol) $($pt.Port)"
        if (-not $pt.Reliable) {
            Net-Log $label "INFO - $($pt.Purpose)" "Gray"
            if ($pt.Note) { Net-Log "  " $pt.Note "Gray" }
            $portInfo++; continue
        }
        $ok = $false
        if      ($pt.Protocol -eq "TCP")                            { $ok = Test-TcpConnect  -HostName $pt.ProbeHost -Port $pt.Port -TimeoutMs $NetTimeoutMs }
        elseif  ($pt.Protocol -eq "UDP" -and $pt.Port -eq 53)      { $ok = Test-UdpDns  -Server $pt.ProbeHost -TimeoutMs $NetTimeoutMs }
        elseif  ($pt.Protocol -eq "UDP" -and $pt.Port -eq 123)     { $ok = Test-UdpNtp  -Server $pt.ProbeHost -TimeoutMs $NetTimeoutMs }
        elseif  ($pt.Protocol -eq "UDP")                            { $ok = Test-UdpEcho -Server $pt.ProbeHost -Port $pt.Port -TimeoutMs $NetTimeoutMs }
        if ($ok) {
            Net-Log $label "PASS  $($pt.Purpose)" "Pass"; $portPass++
        } else {
            Net-Log $label "FAIL  $($pt.Purpose)" "Fail"
            if ($pt.Note) { Net-Log "  " $pt.Note "Gray" }
            $portFail++
        }
    }
    $sync.NetPortPass = $portPass; $sync.NetPortFail = $portFail; $sync.NetPortInfo = $portInfo
    Set-NetCard "NetPorts" (if ($portFail -eq 0) { "$portPass passed" } else { "$portFail failed" }) (if ($portFail -eq 0) { "ok" } else { "fail" })
    $sync["_nc_NetPorts"]  = if ($portFail -eq 0) { "$portPass passed" } else { "$portFail failed" }
    $sync["_ncs_NetPorts"] = if ($portFail -eq 0) { "ok" } else { "fail" }

    if ($sync.NetCancelled) { $sync.NetRunning = $false; $sync.NetComplete = $true; return }

    # -- Domain tests ----------------------------------------------------------
    $sync.NetStep = "Resolving domains..."
    Net-Section "Domain Tests"
    $domPass = 0; $domFail = 0; $domInfo = 0
    foreach ($dt in $DomainTests) {
        if ($sync.NetCancelled) { break }
        $sync.NetStep = "Resolving $($dt.Domain)..."
        if ($dt.Note -like "*DNS not expected*") {
            Net-Log $dt.Domain "INFO - stream-only destination (DNS resolution not expected)" "Gray"
            $domInfo++; continue
        }
        $addrs = Resolve-DomainAsync -Domain $dt.Domain -TimeoutMs $NetTimeoutMs
        if ($addrs -and $addrs.Length -gt 0) {
            $ips = ($addrs | Select-Object -First 2 | ForEach-Object { $_.ToString() }) -join ", "
            Net-Log $dt.Domain "PASS  $($dt.Purpose)  ($ips)" "Pass"; $domPass++
        } else {
            Net-Log $dt.Domain "FAIL  $($dt.Purpose)" "Fail"
            if ($dt.Note) { Net-Log "  " $dt.Note "Gray" }
            $domFail++
        }
    }
    $sync.NetDomainPass = $domPass; $sync.NetDomainFail = $domFail; $sync.NetDomainInfo = $domInfo
    Set-NetCard "NetDomains" (if ($domFail -eq 0) { "$domPass resolved" } else { "$domFail failed" }) (if ($domFail -eq 0) { "ok" } else { "fail" })
    $sync["_nc_NetDomains"]  = if ($domFail -eq 0) { "$domPass resolved" } else { "$domFail failed" }
    $sync["_ncs_NetDomains"] = if ($domFail -eq 0) { "ok" } else { "fail" }

    $sync.NetAllClear = ($portFail -eq 0) -and ($domFail -eq 0)
    $sync.NetStep     = if ($sync.NetAllClear) { "All network tests passed." } else { "Network tests complete. Review results." }
    $sync.NetRunning  = $false
    $sync.NetComplete = $true
}

# Network timer - polls $sync.NetQueue every 300ms, updates Network panel UI
$netTimer = New-Object System.Windows.Forms.Timer
$netTimer.Interval = 300
$netTimer.Add_Tick({
    $netItem = $null
    while ($sync.NetQueue.TryDequeue([ref]$netItem)) {
        # Render to rtbNetLog
        if ($netItem.L -eq "Section") {
            $rtbNetLog.SelectionStart = $rtbNetLog.TextLength; $rtbNetLog.SelectionLength = 0
            $rtbNetLog.SelectionFont  = New-Object System.Drawing.Font("Segoe UI Semibold", 9, [System.Drawing.FontStyle]::Bold)
            $rtbNetLog.SelectionColor = $ColText
            $rtbNetLog.AppendText("`n`n  $($netItem.Result.ToUpper())`n")
        } else {
            $rtbNetLog.SelectionStart = $rtbNetLog.TextLength; $rtbNetLog.SelectionLength = 0
            $rtbNetLog.SelectionColor = $ColLogLabel
            $rtbNetLog.SelectionFont  = New-Object System.Drawing.Font("Consolas", 8)
            $rtbNetLog.AppendText(("{0,-22}" -f $netItem.Label))
            $col = switch ($netItem.L) {
                "Pass" { $ColLogPass }
                "Fail" { $ColLogFail }
                "Warn" { $ColLogWarn }
                "Gray" { $ColMuted   }
                default{ $ColLogText }
            }
            $rtbNetLog.SelectionStart = $rtbNetLog.TextLength; $rtbNetLog.SelectionLength = 0
            $rtbNetLog.SelectionColor = $col
            $rtbNetLog.SelectionFont  = New-Object System.Drawing.Font("Consolas", 8)
            $rtbNetLog.AppendText("$($netItem.Result)`n")
        }
        $rtbNetLog.ScrollToCaret()
    }

    foreach ($netKey in $netCards.Keys) {
        $val = $sync["_nc_$netKey"]
        $sts = $sync["_ncs_$netKey"]
        if ($val -and $val -ne $netCards[$netKey].ValueLabel.Text) {
            Update-CardStatus -Card $netCards[$netKey] -Value $val -Status $sts
        }
    }

    if ($sync.NetRunning) {
        $script:netSpinIdx = ($script:netSpinIdx + 1) % 4
        $spinChar = @('|','/','-','\')[$script:netSpinIdx]
        $lblNetStatus.ForeColor = $ColAccent
        $lblNetStatus.Text = " $spinChar  $($sync.NetStep)"
    }

    if ($sync.NetComplete -and -not $sync.NetRunning) {
        # Backfill $sync.Cards from _nc_/_ncs_ keys for FullDiagnostic compatibility (#60)
        foreach ($netKey in @("NetInternet","NetPorts","NetDomains")) {
            $val = $sync["_nc_$netKey"]
            $sts = $sync["_ncs_$netKey"]
            if ($val) { $sync.Cards[$netKey] = @{ Value = $val; Status = $sts } }
        }
        $netTimer.Stop()
        $btnNetCancel.Visible = $false
        $btnNetRun.Enabled = $true; $btnNetRun.Text = [char]0x25B6 + "  Run Test"
        $lblNetStatus.ForeColor = $ColMuted
        $lblNetStatus.Text = "Last run: $(Get-Date -Format 'h:mm tt')"

        # Update section header pill based on worst card status (v1.0.42 redesign)
        $worst = "ok"
        $pri = @{ fail=3; warn=2; ok=1; neutral=0 }
        foreach ($k in @("NetInternet","NetPorts","NetDomains")) {
            $s = $sync["_ncs_$k"]
            if ($s -and $pri[$s] -gt $pri[$worst]) { $worst = $s }
        }
        Set-SectionPill $netHeader $worst

        # Refresh the Summary panel — green/yellow/red bullets summarising results
        $sumItems = @()
        $intStatus = $sync["_ncs_NetInternet"]
        if ($intStatus -eq "ok")   { $sumItems += @{ Status="ok";   Text="Internet connectivity is available" } }
        elseif ($intStatus)        { $sumItems += @{ Status="fail"; Text="Internet is unreachable — check uplink adapter" } }
        $portFailN = [int]$sync.NetPortFail
        $portPassN = [int]$sync.NetPortPass
        if ($portFailN -gt 0)      { $sumItems += @{ Status="fail"; Text="$portFailN of $($portFailN + $portPassN) required ports failed — check firewall / router" } }
        elseif ($portPassN -gt 0)  { $sumItems += @{ Status="ok";   Text="$portPassN of $portPassN required ports reachable" } }
        $domFailN = [int]$sync.NetDomainFail
        $domPassN = [int]$sync.NetDomainPass
        if ($domFailN -gt 0)       { $sumItems += @{ Status="fail"; Text="$domFailN of $($domFailN + $domPassN) domains failed DNS — check DNS server settings" } }
        elseif ($domPassN -gt 0)   { $sumItems += @{ Status="ok";   Text="DNS resolution working for $domPassN of $domPassN domains" } }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="Run Test to populate the summary" }) }
        Set-SummaryItems $netSummary $sumItems

        # Action banner — kept for the most actionable failures, hidden when all green
        $lines = @()
        if ($portFailN -gt 0) { $lines += "Port failures — check the firewall, router, and content-filter / VLAN policy." }
        if ($domFailN  -gt 0) { $lines += "DNS failures — check DNS server settings on this adapter." }
        if ($lines.Count -gt 0) {
            $lblNetActionText.Text = $lines -join "   |   "
            $pnlNetAction.Visible  = $true
        } else {
            $pnlNetAction.Visible  = $false
        }
    }
})


# ---- Network Panel (v1.0.42 redesign — mockup-style two-column layout) ----
$pnlNetwork = New-Object System.Windows.Forms.Panel
$pnlNetwork.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlNetwork.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlNetwork.BackColor = $ColBg; $pnlNetwork.Visible = $false
$pnlNetwork.Anchor = $AnchorTLRB
$form.Controls.Add($pnlNetwork)

# Section header — title / subtitle / Overall Status pill (top-right)
$netHeader = New-SectionHeader -Parent $pnlNetwork `
    -Title    "Network Configuration" `
    -Subtitle "View and test network settings and connectivity"

# ---- Left column: Network Adapters / IP Configuration / Firewall Status ----
function New-NetCard {
    param([System.Windows.Forms.Panel]$Parent, [string]$Title, [int]$X, [int]$Y, [int]$W, [int]$H)
    $card = New-Object System.Windows.Forms.Panel
    $card.Size      = New-Object System.Drawing.Size($W, $H)
    $card.Location  = New-Object System.Drawing.Point($X, $Y)
    $card.BackColor = $ColCard
    $card.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $W, $H)), 8))
    $Parent.Controls.Add($card)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = $Title
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $lblTitle.ForeColor = $ColText
    $lblTitle.Location  = New-Object System.Drawing.Point(16, 12)
    $lblTitle.Size      = New-Object System.Drawing.Size(($W - 32), 20)
    $card.Controls.Add($lblTitle)

    $body = New-Object System.Windows.Forms.Panel
    $body.Location  = New-Object System.Drawing.Point(8, 38)
    $body.Size      = New-Object System.Drawing.Size(($W - 16), ($H - 46))
    $body.BackColor = $ColCard
    $card.Controls.Add($body)
    return @{ Card = $card; Body = $body; Title = $lblTitle }
}

$netLeftX = 28; $netLeftW = 600
$netRightX = 644; $netRightW = 600

$netCardAdapters = New-NetCard $pnlNetwork "Network Adapters"            $netLeftX 110 $netLeftW 200
$netCardIP       = New-NetCard $pnlNetwork "IP Configuration"            $netLeftX 322 $netLeftW 280

# ---- Right column: Connectivity Tests + Summary --------------------------
$netCardTests   = New-NetCard $pnlNetwork "Connectivity Tests"           $netRightX 110 $netRightW 408
$netSummary     = New-SummaryPanel -Parent $pnlNetwork -X $netRightX -Y 530 -W $netRightW -H 114 -Title "Summary"

# Test results live inside the Connectivity Tests card body via a RichTextBox
# (kept from the previous design for simplicity; styled to match the cards).
$rtbNetLog = New-Object System.Windows.Forms.RichTextBox
$rtbNetLog.Location    = New-Object System.Drawing.Point(0, 0)
$rtbNetLog.Size        = New-Object System.Drawing.Size($netCardTests.Body.Width, $netCardTests.Body.Height)
$rtbNetLog.BackColor   = $ColCard
$rtbNetLog.ForeColor   = $ColText
$rtbNetLog.Font        = New-Object System.Drawing.Font("Consolas", 8.5)
$rtbNetLog.ReadOnly    = $true
$rtbNetLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbNetLog.ScrollBars  = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbNetLog.Dock        = [System.Windows.Forms.DockStyle]::Fill
$rtbNetLog.Text        = "Click Run Test to test ports and domains."
$netCardTests.Body.Controls.Add($rtbNetLog)

# Card-content helper: simple key/value row writer.
function Add-NetKV {
    param([System.Windows.Forms.Panel]$Body, [int]$Y, [string]$Key, [string]$Value, [System.Drawing.Color]$ValueColor = $ColText, [int]$KeyColW = 160)
    $lblK = New-Object System.Windows.Forms.Label
    $lblK.Text      = $Key
    $lblK.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $lblK.ForeColor = $ColMuted
    $lblK.Location  = New-Object System.Drawing.Point(8, $Y)
    $lblK.Size      = New-Object System.Drawing.Size($KeyColW, 18)
    $Body.Controls.Add($lblK)

    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text      = $Value
    $lblV.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $lblV.ForeColor = $ValueColor
    $lblV.Location  = New-Object System.Drawing.Point((8 + $KeyColW), $Y)
    $lblV.Size      = New-Object System.Drawing.Size(($Body.Width - $KeyColW - 16), 18)
    $Body.Controls.Add($lblV)
    return $lblV
}

# Convert a CIDR prefix length (e.g. 24) into a dotted subnet mask (255.255.255.0).
# Avoids the limited switch-by-prefix that only covered /8, /16, /24.
function ConvertTo-DottedMask {
    param([int]$Prefix)
    if ($Prefix -lt 0 -or $Prefix -gt 32) { return "/$Prefix" }
    if ($Prefix -eq 0)  { return "0.0.0.0" }
    if ($Prefix -eq 32) { return "255.255.255.255" }
    $mask = ([uint32]::MaxValue) -shl (32 - $Prefix) -band [uint32]::MaxValue
    return ("{0}.{1}.{2}.{3}" -f `
        (($mask -shr 24) -band 0xFF),
        (($mask -shr 16) -band 0xFF),
        (($mask -shr  8) -band 0xFF),
        ( $mask          -band 0xFF))
}

# Identify what an adapter is used for. Combines IP-based detection
# (169.254.x.x → camera link-local) with description matching for the
# common Pixellot 4-port NIC chipsets, and falls back to "Internet" when
# the adapter holds the default gateway.
function Get-AdapterPurpose {
    param($Adapter, [string]$Ip, $InternetAdapterIndex)
    $desc = "$($Adapter.InterfaceDescription)"
    $isCameraNic = $desc -match "I210|I350|82574L|I211|GIE7"
    if ($Ip -like "169.254.*") {
        if ($isCameraNic) { return "Camera (link-local)" }
        return "Link-local (no DHCP)"
    }
    if ($InternetAdapterIndex -and $Adapter.ifIndex -eq $InternetAdapterIndex) {
        return "Internet"
    }
    if ($isCameraNic) { return "Camera NIC port" }
    return "Auxiliary"
}

# Render a 4-column row inside the adapters card. Re-used for both the
# header row and the per-adapter rows so column geometry stays in sync.
function Add-AdapterRow {
    param(
        [System.Windows.Forms.Panel]$Body, [int]$Y,
        [string]$Name, [string]$Ip, [string]$Speed, [string]$Purpose,
        [System.Drawing.Color]$Color = $ColText, [bool]$Header = $false
    )
    $bodyW = $Body.Width
    # Column widths inside a 584-px body: 150 / 130 / 80 / remainder
    $cols = @(
        @{ X=8;   W=150; Text=$Name },
        @{ X=160; W=130; Text=$Ip },
        @{ X=292; W=80;  Text=$Speed },
        @{ X=378; W=($bodyW - 386); Text=$Purpose }
    )
    foreach ($c in $cols) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text      = $c.Text
        $lbl.Font      = if ($Header) { New-Object System.Drawing.Font("Segoe UI Semibold", 8) } `
                         else         { New-Object System.Drawing.Font("Segoe UI", 8.5) }
        $lbl.ForeColor = if ($Header) { $ColMuted } else { $Color }
        $lbl.Location  = New-Object System.Drawing.Point($c.X, $Y)
        $lbl.Size      = New-Object System.Drawing.Size($c.W, 18)
        $lbl.AutoEllipsis = $true
        $Body.Controls.Add($lbl)
    }
}

# Populate the side cards from Win32_NetworkAdapterConfiguration / Get-NetIPConfiguration
# when the panel becomes visible. This is fast (sub-100ms) and avoids stale
# data when a tech changes adapter settings between visits to the panel.
function Update-NetSideCards {
    # ---- Network Adapters ---------------------------------------------------
    $abody = $netCardAdapters.Body
    $abody.Controls.Clear()
    try {
        $ups = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" } | Sort-Object Name | Select-Object -First 6)
        # Identify the Internet-bound adapter (the one with a default gateway).
        $internetIfIndex = $null
        try {
            $primaryNet = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                          Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
                          Select-Object -First 1
            if ($primaryNet) { $internetIfIndex = $primaryNet.InterfaceIndex }
        } catch { }

        $rowY = 0
        if ($ups.Count -eq 0) {
            Add-NetKV $abody $rowY "Status:" "No active adapters detected" $ColYellow | Out-Null
        } else {
            Add-AdapterRow $abody $rowY "Adapter" "IP" "Speed" "Purpose" $ColMuted $true
            $rowY += 22
            foreach ($a in $ups) {
                $ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
                $ipStr     = if ($ip) { $ip } else { "—" }
                $speedStr  = "$($a.LinkSpeed)"
                $purpose   = Get-AdapterPurpose -Adapter $a -Ip $ipStr -InternetAdapterIndex $internetIfIndex
                $color     = switch -Wildcard ($purpose) {
                                "Internet"             { $ColGreen }
                                "Camera*"              { $ColAccent }
                                "Link-local*"          { $ColYellow }
                                default                { $ColMuted }
                             }
                Add-AdapterRow $abody $rowY "$($a.Name)" $ipStr $speedStr $purpose $color $false
                $rowY += 22
            }
        }
    } catch { Add-NetKV $abody 0 "Status:" "Adapter query failed" $ColYellow | Out-Null }

    # ---- IP Configuration ---------------------------------------------------
    # Show the primary (Internet-bound) interface plus Time / NTP detail.
    $ibody = $netCardIP.Body
    $ibody.Controls.Clear()
    try {
        $primary = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                   Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq "Up" } |
                   Select-Object -First 1
        if ($primary) {
            $rowY = 0
            $ipv4 = ($primary.IPv4Address | Select-Object -First 1).IPAddress
            $mask = ($primary.IPv4Address | Select-Object -First 1).PrefixLength
            $maskStr = ConvertTo-DottedMask $mask
            $gw   = ($primary.IPv4DefaultGateway | Select-Object -First 1).NextHop
            $dns  = ($primary.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | Select-Object -First 1).ServerAddresses
            $dnsStr = if ($dns) { ($dns -join ", ") } else { "—" }
            Add-NetKV $ibody $rowY "IP Address:"      "$ipv4"        $ColText | Out-Null; $rowY += 22
            Add-NetKV $ibody $rowY "Subnet Mask:"     "$maskStr"     $ColText | Out-Null; $rowY += 22
            Add-NetKV $ibody $rowY "Default Gateway:" "$gw"          $ColText | Out-Null; $rowY += 22
            Add-NetKV $ibody $rowY "DNS Servers:"     "$dnsStr"      $ColText | Out-Null; $rowY += 22
            $cfg = Get-NetIPInterface -InterfaceIndex $primary.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $dhcp = if ($cfg.Dhcp -eq "Enabled") { "Enabled" } else { "Disabled" }
            $dhcpColor = if ($dhcp -eq "Enabled") { $ColGreen } else { $ColMuted }
            Add-NetKV $ibody $rowY "DHCP:" $dhcp $dhcpColor | Out-Null; $rowY += 22

            # NTP server — both the configured peer list and the currently-synced source.
            # `w32tm /query /source` returns the live source (e.g. "time.windows.com" or
            # "Local CMOS Clock" when not synced); the registry holds the configured peers.
            $ntpConfigured = ""
            try {
                $reg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ErrorAction SilentlyContinue
                if ($reg -and $reg.NtpServer) { $ntpConfigured = (($reg.NtpServer -split ',')[0]).Trim() }
            } catch { }
            $ntpLive = ""
            try {
                $src = (& w32tm /query /source 2>$null) -join " "
                if ($src) { $ntpLive = $src.Trim() }
            } catch { }
            $ntpServerStr = if ($ntpConfigured) { $ntpConfigured } else { "—" }
            $ntpLiveStr   = if ($ntpLive)       { $ntpLive }       else { "Not queried" }
            # R15 fix: don't pattern-match on the English literal "Local CMOS" —
            # on non-EN-US Windows this returns a localised string and the check
            # falsely greens a desynced clock. Heuristic: if the live source is
            # not blank, doesn't contain a dot (servers always do — "time.windows.com",
            # "0.pool.ntp.org" — but "Local CMOS Clock"/"Hardware Clock" don't),
            # and isn't an IP, treat as un-synced. Also flag the well-known
            # un-synced strings (English + localised stubs) defensively.
            $unSyncedHints = @('Local CMOS','CMOS Clock','Free-running','Local','Lokale','Locale','本地','ローカル')
            $localOnly = ($ntpLive -match "^$") -or
                         (-not ($ntpLive -match '\.')) -or
                         ($unSyncedHints | Where-Object { $ntpLive -like "*$_*" }).Count -gt 0
            $liveColor    = if ($localOnly) { $ColYellow } else { $ColGreen }
            Add-NetKV $ibody $rowY "NTP Server:" $ntpServerStr $ColText | Out-Null; $rowY += 22
            Add-NetKV $ibody $rowY "NTP Source:" $ntpLiveStr   $liveColor | Out-Null
        } else {
            Add-NetKV $ibody 0 "Status:" "No active interface with default gateway" $ColYellow | Out-Null
        }
    } catch { Add-NetKV $ibody 0 "Status:" "IP configuration query failed" $ColYellow | Out-Null }
}

# Refresh side cards on visibility change (fast — no runspace needed)
$pnlNetwork.Add_VisibleChanged({
    if ($pnlNetwork.Visible) { try { Update-NetSideCards } catch { } }
})
try { Update-NetSideCards } catch { }

# ---- Action banner (failure guidance) — sits above the action bar -----
$pnlNetAction = New-Object System.Windows.Forms.Panel
$pnlNetAction.Size      = New-Object System.Drawing.Size(($pnlNetwork.Width - 56), 48)
$pnlNetAction.Location  = New-Object System.Drawing.Point(28, 660)
$pnlNetAction.BackColor = [System.Drawing.Color]::FromArgb(75, 20, 20)
$pnlNetAction.Anchor    = $AnchorBLR
$pnlNetAction.Visible   = $false
$pnlNetAction.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ($pnlNetwork.Width - 56), 48)), 6))
$pnlNetwork.Controls.Add($pnlNetAction)

$pnlNetActionBar = New-Object System.Windows.Forms.Panel
$pnlNetActionBar.Size      = New-Object System.Drawing.Size(4, 48)
$pnlNetActionBar.Location  = New-Object System.Drawing.Point(0, 0)
$pnlNetActionBar.BackColor = [System.Drawing.Color]::FromArgb(210, 55, 55)
$pnlNetAction.Controls.Add($pnlNetActionBar)

$lblNetActionIcon = New-Object System.Windows.Forms.Label
$lblNetActionIcon.Text      = [char]0x26A0
$lblNetActionIcon.Font      = New-Object System.Drawing.Font("Segoe UI Symbol", 13)
$lblNetActionIcon.ForeColor = [System.Drawing.Color]::FromArgb(210, 100, 100)
$lblNetActionIcon.Location  = New-Object System.Drawing.Point(14, 12)
$lblNetActionIcon.AutoSize  = $true
$pnlNetAction.Controls.Add($lblNetActionIcon)

$lblNetActionText = New-Object System.Windows.Forms.Label
$lblNetActionText.Text      = ""
$lblNetActionText.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblNetActionText.ForeColor = [System.Drawing.Color]::FromArgb(240, 190, 190)
$lblNetActionText.Location  = New-Object System.Drawing.Point(40, 8)
$lblNetActionText.Size      = New-Object System.Drawing.Size(($pnlNetAction.Width - 50), 32)
$pnlNetAction.Controls.Add($lblNetActionText)

# ---- Bottom action bar — Export + Run -------------------------------------
$netActions = New-ActionBar -Parent $pnlNetwork -Y 720 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")

$btnNetRun     = $netActions.PrimaryBtn
$btnNetExport  = $netActions.ExportBtn

# Cancel button — hidden by default, shown during a run (replaces Run button label-swap)
$btnNetCancel = New-Object System.Windows.Forms.Button
$btnNetCancel.Text      = "Cancel"
$btnNetCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnNetCancel.Location  = New-Object System.Drawing.Point(($netActions.Bar.Width - 320), 10)
$btnNetCancel.BackColor = $ColRed
$btnNetCancel.ForeColor = [System.Drawing.Color]::White
$btnNetCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnNetCancel.FlatAppearance.BorderSize = 0
$btnNetCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnNetCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnNetCancel.Visible   = $false
$btnNetCancel.Anchor    = $AnchorTR
$btnNetCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$netActions.Bar.Controls.Add($btnNetCancel)

# Open Network Settings — pulled into the action bar as a tertiary action
$btnNetSettings = New-Object System.Windows.Forms.Button
$btnNetSettings.Text      = "Open Network Settings"
$btnNetSettings.Size      = New-Object System.Drawing.Size(180, 36)
$btnNetSettings.Location  = New-Object System.Drawing.Point(168, 10)
$btnNetSettings.BackColor = $ColCard
$btnNetSettings.ForeColor = $ColText
$btnNetSettings.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnNetSettings.FlatAppearance.BorderColor = $ColBorder
$btnNetSettings.FlatAppearance.BorderSize  = 1
$btnNetSettings.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnNetSettings.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnNetSettings.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 36)), 6))
$btnNetSettings.Add_Click({ try { Start-Process ncpa.cpl } catch { } })
$netActions.Bar.Controls.Add($btnNetSettings)

# Status / ETA — small inline strip just above the action bar
$lblNetStatus = New-Object System.Windows.Forms.Label
$lblNetStatus.Text      = ""
$lblNetStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblNetStatus.ForeColor = $ColMuted
$lblNetStatus.Location  = New-Object System.Drawing.Point(28, 696)
$lblNetStatus.Size      = New-Object System.Drawing.Size(($pnlNetwork.Width - 56), 18)
$lblNetStatus.Anchor    = $AnchorBLR
$pnlNetwork.Controls.Add($lblNetStatus)

$lblNetEta = New-Object System.Windows.Forms.Label
$lblNetEta.Text      = ""   # Hidden by default; the action bar's primary button is the visual cue.
$lblNetEta.Visible   = $false
$pnlNetwork.Controls.Add($lblNetEta)

# Cards used by the timer-tick code below — kept under the original keys so the
# existing engine continues to populate $sync.Cards["NetInternet" / "NetPorts" / "NetDomains"].
# The new layout doesn't show them as standalone cards (status now lives in the
# section header pill + Summary), but Set-NetCard still needs targets in $netCards
# to avoid null derefs in the timer.
$netCards = @{}
$netCardKeys = @("NetInternet", "NetPorts", "NetDomains")
foreach ($k in $netCardKeys) {
    # Stubs need every field Update-CardStatus touches — ValueLabel, DotPanel, Panel.
    # DotPanel has its BackColor set, so it has to be a real Panel.
    $stubLbl = New-Object System.Windows.Forms.Label; $stubLbl.Visible = $false
    $stubDot = New-Object System.Windows.Forms.Panel; $stubDot.Visible = $false
    $netCards[$k] = @{ Panel = $stubLbl; ValueLabel = $stubLbl; DotPanel = $stubDot }
}

$script:netRunspace = $null
$script:netPs       = $null
$script:netSpinIdx  = 0


function Start-NetDiagnostic {
    if ($sync.NetRunning) { return }
    $sync.NetCancelled = $false
    foreach ($k in @("NetInternet","NetPorts","NetDomains")) {
        $sync.Cards[$k]  = @{ Value="--"; Status="neutral" }
        $sync["_nc_$k"]  = "--"
        $sync["_ncs_$k"] = "neutral"
    }
    # v1.0.42 redesign: cards are stubs; no UI update needed here. Reset section
    # header pill to neutral so the user sees the run-in-progress state.
    Set-SectionPill $netHeader "neutral" "Running..."
    Set-SummaryItems $netSummary @(@{ Status="neutral"; Text="Running connectivity tests..." })
    $pnlNetAction.Visible = $false
    $rtbNetLog.Clear()
    $btnNetRun.Enabled = $false; $btnNetRun.Text = "  Running..."
    $btnNetCancel.Visible = $true
    $lblNetStatus.ForeColor = $ColAccent; $lblNetStatus.Text = " |  Starting..."
    $script:netSpinIdx = 0

    if ($script:netRunspace) { try { $script:netRunspace.Close() } catch { } }
    if ($script:netPs) { try { $script:netPs.Dispose() } catch { }; $script:netPs = $null }
    $script:netRunspace = [runspacefactory]::CreateRunspace()
    $script:netRunspace.ApartmentState = "STA"
    $script:netRunspace.ThreadOptions  = "ReuseThread"
    $script:netRunspace.Open()
    $script:netRunspace.SessionStateProxy.SetVariable("sync",         $sync)
    $script:netRunspace.SessionStateProxy.SetVariable("PortTests",    $PortTests)
    $script:netRunspace.SessionStateProxy.SetVariable("DomainTests",  $DomainTests)
    $script:netRunspace.SessionStateProxy.SetVariable("NetTimeoutMs", $NetTimeoutMs)
    $script:netPs = [powershell]::Create()
    $script:netPs.Runspace = $script:netRunspace
    $script:netPs.AddScript($NetScript) | Out-Null
    $script:netPs.BeginInvoke() | Out-Null
    $netTimer.Start()
}

$btnNetRun.Add_Click({ Start-NetDiagnostic })

$btnNetCancel.Add_Click({
    $sync.NetCancelled = $true
    $btnNetCancel.Visible = $false
})

