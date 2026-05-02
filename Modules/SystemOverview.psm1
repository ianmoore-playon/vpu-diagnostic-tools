# =============================================================================
#  SystemOverview.psm1  -  System Overview hub panel
# =============================================================================

# ---- System Overview Hub ---------------------------------------------------
$pnlSysOverview = New-Object System.Windows.Forms.Panel
$pnlSysOverview.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlSysOverview.Location  = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlSysOverview.BackColor = $ColBg
$pnlSysOverview.Anchor    = $AnchorTLRB
$form.Controls.Add($pnlSysOverview)

$lblHubTitle = New-Object System.Windows.Forms.Label
$lblHubTitle.Text      = "Home"
$lblHubTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$lblHubTitle.ForeColor = $ColText
$lblHubTitle.Location  = New-Object System.Drawing.Point(24, 22)
$lblHubTitle.Size      = New-Object System.Drawing.Size(700, 34)
$pnlSysOverview.Controls.Add($lblHubTitle)

$lblHubSub = New-Object System.Windows.Forms.Label
$lblHubSub.Text      = "Select a module below, or run a Full Diagnostic for a complete system check."
$lblHubSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblHubSub.ForeColor = $ColMuted
$lblHubSub.Location  = New-Object System.Drawing.Point(24, 58)
$lblHubSub.Size      = New-Object System.Drawing.Size(800, 20)
$pnlSysOverview.Controls.Add($lblHubSub)

function New-SectionCard {
    param([string]$Title,[string]$Desc,[int]$IconCode,[int]$X,[int]$Y,[int]$W=296,[int]$H=200)
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Size      = New-Object System.Drawing.Size($W, $H)
    $pnl.Location  = New-Object System.Drawing.Point($X, $Y)
    $pnl.BackColor = $ColCard
    $pnl.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $pnl.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $W, $H)), 10))
    $pnl.Add_Paint({
        $g = $args[1].Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $bp  = [GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ([int]$this.Width - 1), ([int]$this.Height - 1))), 10)
        $pen = New-Object System.Drawing.Pen($ColBorder, 1)
        $g.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
    })
    $iLbl = New-Object System.Windows.Forms.Label
    $iLbl.Text      = [char]$IconCode
    $iLbl.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 22)
    $iLbl.ForeColor = $ColAccent
    $iLbl.Location  = New-Object System.Drawing.Point(20, 20)
    $iLbl.Size      = New-Object System.Drawing.Size(48, 42)
    $iLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($iLbl)
    $tLbl = New-Object System.Windows.Forms.Label
    $tLbl.Text      = $Title
    $tLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $tLbl.ForeColor = $ColText
    $tLbl.Location  = New-Object System.Drawing.Point(20, 76)
    $tLbl.Size      = New-Object System.Drawing.Size(([int]$W - 28), 24)
    $tLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($tLbl)
    $dLbl = New-Object System.Windows.Forms.Label
    $dLbl.Text      = $Desc
    $dLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $dLbl.ForeColor = $ColMuted
    $dLbl.Location  = New-Object System.Drawing.Point(20, 104)
    $dLbl.Size      = New-Object System.Drawing.Size(([int]$W - 28), 76)
    $dLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($dLbl)
    return $pnl
}

$hubCardDefs = @(
    @{Nav="navSysInfo";  Title="System Information"; Desc="Hardware specs, OS version, uptime, and Pixellot software versions"; Icon=0xE80F; R=0;C=0}
    @{Nav="navNetConfig";Title="Network";            Desc="Test required ports and domain DNS; identify firewall blocks";       Icon=0xE701; R=0;C=1}
    @{Nav="navCamera";   Title="Camera";             Desc="Detect cameras and test connectivity; identify cable or PoE faults"; Icon=0xE722; R=0;C=2}
    @{Nav="navServices"; Title="Services";           Desc="Verify Pixellot agent, encoder, watchdog, and remote services";      Icon=0xE9F5; R=0;C=3}
    @{Nav="navPoE";      Title="Hardware";           Desc="PoE budget, GPU, monitor, peripherals, and NIC link uptime";         Icon=0xE7E8; R=1;C=0}
    @{Nav="navDisk";     Title="Disks";              Desc="Free space, SMART health, and disk-related event log errors";        Icon=0xEDA2; R=1;C=1}
    @{Nav="navEvents";   Title="OS Event Logs";      Desc="Recent OS errors filtered to VPU-relevant providers";                Icon=0xE7BA; R=1;C=2}
    @{Nav="navReports";  Title="Reports";            Desc="View, copy, and export saved diagnostic reports";                    Icon=0xE7C3; R=1;C=3}
)
$hCH = 200; $hGap = 16; $hMargin = 24; $hCols = 4; $hRows = 2
$hubNavLookup = @{
    navSysInfo     = $navSysInfo
    navNetConfig   = $navNetConfig
    navCamera      = $navCamera
    navPoE         = $navPoE
    navServices    = $navServices
    navDisk        = $navDisk
    navEvents      = $navEvents
    navReports     = $navReports
}
$script:hubTiles = @()
foreach ($hc in $hubCardDefs) {
    $hCW  = [int](($pnlSysOverview.Width - 2*$hMargin - ($hCols-1)*$hGap) / $hCols)
    $hx   = $hMargin + $hc.C * ($hCW + $hGap)
    $hy   = 90 + $hc.R * ($hCH + $hGap)
    $cp   = New-SectionCard -Title $hc.Title -Desc $hc.Desc -IconCode $hc.Icon -X $hx -Y $hy -W $hCW -H $hCH
    $pnlSysOverview.Controls.Add($cp)
    $script:hubTiles += $cp
    $navBtn = $hubNavLookup[$hc.Nav]
    $clickBlock = { $navBtn.PerformClick() }.GetNewClosure()
    $cp.Add_Click($clickBlock)
    foreach ($ctrl in @($cp.Controls)) { $ctrl.Add_Click($clickBlock) }
}

$pnlSysOverview.Add_SizeChanged({
    # Suspend layout while we move all 8 tiles — without this, each Location/Size
    # change triggers an intermediate paint at a different intermediate position,
    # which is what made the tiles appear "stuck" after resize-back (#58).
    $pnlSysOverview.SuspendLayout()
    try {
        $pw   = $pnlSysOverview.Width
        $hCW  = [int](($pw - 2*$hMargin - ($hCols-1)*$hGap) / $hCols)
        for ($i = 0; $i -lt $script:hubTiles.Count; $i++) {
            $col = $i % $hCols; $row = [int]($i / $hCols)
            $tile = $script:hubTiles[$i]
            $tile.Location = New-Object System.Drawing.Point(($hMargin + $col*($hCW+$hGap)), (90 + $row*($hCH+$hGap)))
            $tile.Size     = New-Object System.Drawing.Size($hCW, $hCH)
            # Refresh the rounded-rect Region to match the new size — without this
            # the clip stays at the old bounds and content gets cut off / mis-aligned.
            $tile.Region   = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $hCW, $hCH)), 10))
            $tile.Invalidate()
        }
        $btnHubLastReport.Location = New-Object System.Drawing.Point($hMargin, (90 + $hRows*($hCH+$hGap) + 10))
    } finally {
        $pnlSysOverview.ResumeLayout()
    }
})

$btnHubLastReport = New-Object System.Windows.Forms.Button
$btnHubLastReport.Text      = "Open Last Report"
$btnHubLastReport.Size      = New-Object System.Drawing.Size(180, 44)
$btnHubLastReport.Location  = New-Object System.Drawing.Point(24, 524)
$btnHubLastReport.BackColor = $ColNavHover
$btnHubLastReport.ForeColor = $ColText
$btnHubLastReport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHubLastReport.FlatAppearance.BorderSize = 0
$btnHubLastReport.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$btnHubLastReport.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnHubLastReport.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 44)), 7))
$pnlSysOverview.Controls.Add($btnHubLastReport)

$btnHubLastReport.Add_Click({
    $latest = Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { Start-Process notepad.exe $latest.FullName }
    else { [System.Windows.Forms.MessageBox]::Show("No reports found yet.", "Open Last Report", "OK", "Information") | Out-Null }
})

# ---- Last-run summary row -------------------------------------------------------
# Surfaces date, overall result, and VPU model from the most recent report so users
# can see at a glance whether anything has been run on this machine and how it went.
$lblHubLastRun = New-Object System.Windows.Forms.Label
$lblHubLastRun.Text      = ""
$lblHubLastRun.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblHubLastRun.ForeColor = $ColMuted
$lblHubLastRun.Location  = New-Object System.Drawing.Point(220, 535)
$lblHubLastRun.Size      = New-Object System.Drawing.Size(900, 22)
$lblHubLastRun.AutoEllipsis = $true
$pnlSysOverview.Controls.Add($lblHubLastRun)

# Refresh the summary every time the panel becomes visible (cheap — one file stat + ~10 lines read)
$pnlSysOverview.Add_VisibleChanged({
    if (-not $pnlSysOverview.Visible) { return }
    try {
        $latest = Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            $lblHubLastRun.Text      = "No diagnostic has been run yet."
            $lblHubLastRun.ForeColor = $ColMuted
            return
        }
        $head = Get-Content $latest.FullName -TotalCount 25 -ErrorAction SilentlyContinue
        # Try to extract VPU model and overall result from the first 25 lines
        $model = ($head | Where-Object { $_ -match '^VPU Model\s*:\s*(.+)$' } | Select-Object -First 1) -replace '^VPU Model\s*:\s*',''
        $overall = ($head | Where-Object { $_ -match '^(Overall|Result|Status)\s*:\s*(.+)$' } | Select-Object -First 1)
        $whenStr = $latest.LastWriteTime.ToString("MMM d, h:mm tt")
        $modelStr = if ($model) { " — $model" } else { "" }
        $resStr = if ($overall) { ($overall -replace '^[^:]+:\s*','') } else { "" }
        $color = if ($resStr -match 'fail|error|critical') { $ColRed } `
                 elseif ($resStr -match 'warn|issue|degrad') { $ColYellow } `
                 elseif ($resStr) { $ColGreen } `
                 else { $ColMuted }
        $resBlock = if ($resStr) { "   |   $resStr" } else { "" }
        $lblHubLastRun.Text      = "Last run: $whenStr$modelStr$resBlock"
        $lblHubLastRun.ForeColor = $color
    } catch {
        $lblHubLastRun.Text = "Last run: report unreadable"
        $lblHubLastRun.ForeColor = $ColMuted
    }
})

