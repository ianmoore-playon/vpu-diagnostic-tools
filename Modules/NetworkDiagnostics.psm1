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
    [PSCustomObject]@{ Protocol="UDP"; Port=443;  ProbeHost="prod-echo.pixellot.tv";  Reliable=$true;  Purpose="Video streaming - Zixi fallback on 443";   Note="Firewall must allow outbound UDP 443 to Pixellot servers." },
    [PSCustomObject]@{ Protocol="TCP"; Port=1402; ProbeHost="scorebot.sportzcast.net"; Reliable=$true;  Purpose="SportzCast data transmission (1400-1405)";  Note="Firewall must allow outbound TCP 1400-1405 to SportzCast servers." },
    [PSCustomObject]@{ Protocol="TCP"; Port=1935; ProbeHost="scorebot.sportzcast.net"; Reliable=$true;  Purpose="SportzCast remote management";              Note="Firewall must allow outbound TCP 1935 to SportzCast servers." },
    [PSCustomObject]@{ Protocol="UDP"; Port=2088; ProbeHost="prod-echo.pixellot.tv";  Reliable=$true;  Purpose="Video streaming - Zixi primary";           Note="Firewall must allow outbound UDP 2088 to Pixellot servers." },
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
    $pingOk = $false
    try { $r = (New-Object System.Net.NetworkInformation.Ping).Send("8.8.8.8", $NetTimeoutMs); $pingOk = ($r.Status -eq "Success") } catch { }
    if (-not $pingOk) {
        try { $r = (New-Object System.Net.NetworkInformation.Ping).Send("1.1.1.1", $NetTimeoutMs); $pingOk = ($r.Status -eq "Success") } catch { }
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
        $sync.NetStep = "Testing $($pt.Protocol) $($pt.Port) ? $($pt.ProbeHost)..."
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
        # Final sync reads directly from the synchronized hashtable — guaranteed visibility.
        # We ALSO backfill $sync.Cards from the _nc_/_ncs_ keys so FullDiagnostic's
        # Get-WorstCardStatus (which reads $sync.Cards[$key].Status) sees the correct
        # state. Writes inside the background runspace's Set-NetCard function don't
        # reliably propagate to the inner unsynchronized Cards hashtable — same
        # function-scope quirk we hit in v1.0.26 (#60).
        foreach ($netKey in $netCards.Keys) {
            $val = $sync["_nc_$netKey"]
            $sts = $sync["_ncs_$netKey"]
            if ($val) {
                Update-CardStatus -Card $netCards[$netKey] -Value $val -Status $sts
                $sync.Cards[$netKey] = @{ Value = $val; Status = $sts }
            }
        }
        $netTimer.Stop()
        $btnNetCancel.Visible = $false
        $btnNetRun.Enabled = $true; $btnNetRun.Text = [char]0x25B6 + "  Run Network Test"
        $lblNetEta.Visible = $false
        $lblNetStatus.ForeColor = $ColMuted
        $lblNetStatus.Text = "  $($sync.NetStep)   |   Last run: $(Get-Date -Format 'h:mm tt')"
        $lines = @()
        if ($sync.NetPortFail   -gt 0) { $lines += "Port failures — check the firewall and router. Confirm the uplink adapter is not blocked by a content filter or VLAN policy." }
        if ($sync.NetDomainFail -gt 0) { $lines += "DNS failures — check DNS server settings on this adapter. Confirm the VPU can reach its configured DNS server." }
        if ($lines.Count -gt 0) {
            $lblNetActionText.Text = $lines -join "   |   "
            $pnlNetAction.Visible  = $true
        }
    }
})


# ---- Network Panel ---------------------------------------------------------
$pnlNetwork = New-Object System.Windows.Forms.Panel
$pnlNetwork.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlNetwork.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlNetwork.BackColor = $ColBg; $pnlNetwork.Visible = $false
$pnlNetwork.Anchor = $AnchorTLRB
$form.Controls.Add($pnlNetwork)

$lblNetTitle = New-Object System.Windows.Forms.Label
$lblNetTitle.Text = "Network Connectivity"
$lblNetTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblNetTitle.ForeColor = $ColText
$lblNetTitle.Location = New-Object System.Drawing.Point(10, 16); $lblNetTitle.AutoSize = $true
$pnlNetwork.Controls.Add($lblNetTitle)

$lblNetSub = New-Object System.Windows.Forms.Label
$lblNetSub.Text = "Tests ports and domains required by Pixellot - run on the VPU's internet-connected adapter."
$lblNetSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblNetSub.ForeColor = $ColMuted
$lblNetSub.Location = New-Object System.Drawing.Point(10, 42); $lblNetSub.Size = New-Object System.Drawing.Size(1240, 18)
$pnlNetwork.Controls.Add($lblNetSub)

# Status cards: Internet / Ports / Domains
$netCardDefs = @(
    @{ Key="NetInternet"; Title="Internet";      Sub="Basic reachability";   X=10;  Icon=[char]0xE701; W=250 }
    @{ Key="NetPorts";    Title="Port Tests";    Sub="Required TCP/UDP ports"; X=270; Icon=[char]0xE9D5; W=250 }
    @{ Key="NetDomains";  Title="Domain Tests";  Sub="DNS resolution";       X=530; Icon=[char]0xE7BE; W=250 }
)
$netCards = @{}
foreach ($cd in $netCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $netCards[$cd.Key] = $c
    $pnlNetwork.Controls.Add($c.Panel)
}

# Failure action banner (shown after run when any test fails)
$pnlNetAction = New-Object System.Windows.Forms.Panel
$pnlNetAction.Size      = New-Object System.Drawing.Size(1240, 56)
$pnlNetAction.Location  = New-Object System.Drawing.Point(10, 162)
$pnlNetAction.BackColor = [System.Drawing.Color]::FromArgb(75, 20, 20)
$pnlNetAction.Visible   = $false
$pnlNetwork.Controls.Add($pnlNetAction)

$pnlNetActionBar = New-Object System.Windows.Forms.Panel
$pnlNetActionBar.Size      = New-Object System.Drawing.Size(4, 56)
$pnlNetActionBar.Location  = New-Object System.Drawing.Point(0, 0)
$pnlNetActionBar.BackColor = [System.Drawing.Color]::FromArgb(210, 55, 55)
$pnlNetAction.Controls.Add($pnlNetActionBar)

$lblNetActionIcon = New-Object System.Windows.Forms.Label
$lblNetActionIcon.Text      = [char]0x26A0
$lblNetActionIcon.Font      = New-Object System.Drawing.Font("Segoe UI Symbol", 14)
$lblNetActionIcon.ForeColor = [System.Drawing.Color]::FromArgb(210, 100, 100)
$lblNetActionIcon.Location  = New-Object System.Drawing.Point(14, 14)
$lblNetActionIcon.AutoSize  = $true
$pnlNetAction.Controls.Add($lblNetActionIcon)

$lblNetActionText = New-Object System.Windows.Forms.Label
$lblNetActionText.Text      = ""
$lblNetActionText.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblNetActionText.ForeColor = [System.Drawing.Color]::FromArgb(240, 190, 190)
$lblNetActionText.Location  = New-Object System.Drawing.Point(44, 8)
$lblNetActionText.Size      = New-Object System.Drawing.Size(1186, 40)
$pnlNetAction.Controls.Add($lblNetActionText)

# Run / Cancel buttons
$btnNetRun = New-Object System.Windows.Forms.Button
$btnNetRun.Text = [char]0x25B6 + "  Run Network Test"
$btnNetRun.Size = New-Object System.Drawing.Size(240, 40); $btnNetRun.Location = New-Object System.Drawing.Point(10, 226)
$btnNetRun.BackColor = $ColAccent; $btnNetRun.ForeColor = [System.Drawing.Color]::White
$btnNetRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnNetRun.FlatAppearance.BorderSize = 0
$btnNetRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnNetRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnNetRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlNetwork.Controls.Add($btnNetRun)
$btnNetRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 240, 40)), 6))

$btnNetCancel = New-Object System.Windows.Forms.Button; $btnNetCancel.Text = "Cancel"
$btnNetCancel.Size = New-Object System.Drawing.Size(110, 40); $btnNetCancel.Location = New-Object System.Drawing.Point(258, 226)
$btnNetCancel.BackColor = $ColRed; $btnNetCancel.ForeColor = [System.Drawing.Color]::White
$btnNetCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnNetCancel.FlatAppearance.BorderSize = 0
$btnNetCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnNetCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnNetCancel.Visible = $false
$pnlNetwork.Controls.Add($btnNetCancel)
$btnNetCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 40)), 6))

$lblNetEta = New-Object System.Windows.Forms.Label; $lblNetEta.Text = "est. ~15 sec"
$lblNetEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblNetEta.ForeColor = $ColMuted
$lblNetEta.Location = New-Object System.Drawing.Point(378,236); $lblNetEta.AutoSize = $true
$pnlNetwork.Controls.Add($lblNetEta)

# "Open Network Settings" — shortcut to ncpa.cpl for adapter changes
$btnNetSettings = New-Object System.Windows.Forms.Button
$btnNetSettings.Text      = "Open Network Settings"
$btnNetSettings.Size      = New-Object System.Drawing.Size(180, 40)
$btnNetSettings.Location  = New-Object System.Drawing.Point(1070, 226)
$btnNetSettings.Anchor    = $AnchorTR
$btnNetSettings.BackColor = $ColNavHover
$btnNetSettings.ForeColor = $ColText
$btnNetSettings.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnNetSettings.FlatAppearance.BorderSize = 0
$btnNetSettings.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnNetSettings.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnNetSettings.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 40)), 6))
$btnNetSettings.Add_Click({ try { Start-Process ncpa.cpl } catch { } })
$pnlNetwork.Controls.Add($btnNetSettings)

$lblNetStatus = New-Object System.Windows.Forms.Label; $lblNetStatus.Text = ""
$lblNetStatus.Font = New-Object System.Drawing.Font("Consolas", 8); $lblNetStatus.ForeColor = $ColMuted
$lblNetStatus.Location = New-Object System.Drawing.Point(10, 274); $lblNetStatus.Size = New-Object System.Drawing.Size(1240, 18)
$pnlNetwork.Controls.Add($lblNetStatus)

$lblNetLogHdr = New-Object System.Windows.Forms.Label; $lblNetLogHdr.Text = "Test Results"
$lblNetLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10); $lblNetLogHdr.ForeColor = $ColText
$lblNetLogHdr.Location = New-Object System.Drawing.Point(10, 298); $lblNetLogHdr.AutoSize = $true
$pnlNetwork.Controls.Add($lblNetLogHdr)

$rtbNetLog = New-Object System.Windows.Forms.RichTextBox
$rtbNetLog.Size = New-Object System.Drawing.Size(1240, 280); $rtbNetLog.Location = New-Object System.Drawing.Point(10, 322)
$rtbNetLog.BackColor = $ColLogBg; $rtbNetLog.ForeColor = $ColLogText
$rtbNetLog.Font = New-Object System.Drawing.Font("Consolas", 8); $rtbNetLog.ReadOnly = $true
$rtbNetLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbNetLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$rtbNetLog.Anchor = $AnchorTLRB
$rtbNetLog.Text = "Click 'Run Network Test' to begin."
$pnlNetwork.Controls.Add($rtbNetLog)

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
    foreach ($k in $netCards.Keys) { Update-CardStatus -Card $netCards[$k] -Value "--" -Status "neutral" }
    $pnlNetAction.Visible = $false
    $lblNetEta.Visible = $true
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

