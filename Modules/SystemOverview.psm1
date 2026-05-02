# =============================================================================
#  SystemOverview.psm1  -  Home / System Overview hub panel (v1.0.42 redesign)
# =============================================================================

# ---- Home Panel ------------------------------------------------------------
$pnlSysOverview = New-Object System.Windows.Forms.Panel
$pnlSysOverview.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlSysOverview.Location  = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlSysOverview.BackColor = $ColBg
$pnlSysOverview.Anchor    = $AnchorTLRB
$form.Controls.Add($pnlSysOverview)

# Title row — "VPU Diagnostic Tool Suite" matching the mockup
$lblHubTitle = New-Object System.Windows.Forms.Label
$lblHubTitle.Text      = "VPU Diagnostic Tool Suite"
$lblHubTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 17)
$lblHubTitle.ForeColor = $ColText
$lblHubTitle.Location  = New-Object System.Drawing.Point(28, 24)
$lblHubTitle.Size      = New-Object System.Drawing.Size(900, 32)
$pnlSysOverview.Controls.Add($lblHubTitle)

$lblHubSub = New-Object System.Windows.Forms.Label
$lblHubSub.Text      = "All-in-one diagnostic and troubleshooting tool for Pixellot VPU systems."
$lblHubSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblHubSub.ForeColor = $ColMuted
$lblHubSub.Location  = New-Object System.Drawing.Point(28, 60)
$lblHubSub.Size      = New-Object System.Drawing.Size(900, 22)
$pnlSysOverview.Controls.Add($lblHubSub)

# ---- Tile factory ----------------------------------------------------------
# Each tile mirrors the mockup: large icon in a colored circular badge, title,
# and a 2-line description. Hovering raises a subtle border highlight.
function New-HubTile {
    param(
        [string]$Title, [string]$Desc, [int]$IconCode,
        [int]$X, [int]$Y, [int]$W, [int]$H,
        [System.Drawing.Color]$IconColor
    )
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Size      = New-Object System.Drawing.Size($W, $H)
    $pnl.Location  = New-Object System.Drawing.Point($X, $Y)
    $pnl.BackColor = $ColCard
    $pnl.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $pnl.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $W, $H)), 10))

    # Hover state — track via Tag so re-paint can react
    $pnl.Tag = [PSCustomObject]@{ Hovered = $false; IconColor = $IconColor }
    $pnl.Add_MouseEnter({ $this.Tag.Hovered = $true; $this.Invalidate() })
    $pnl.Add_MouseLeave({ $this.Tag.Hovered = $false; $this.Invalidate() })

    # Custom paint draws: rounded card border, icon badge (filled circle behind icon)
    $pnl.Add_Paint({
        $g = $args[1].Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        # Border (slightly brighter on hover)
        $borderColor = if ($this.Tag.Hovered) { $ColAccent } else { $ColBorder }
        $bp  = [GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ([int]$this.Width - 1), ([int]$this.Height - 1))), 10)
        $pen = New-Object System.Drawing.Pen($borderColor, 1)
        $g.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()

        # Icon badge — filled circle in the icon's accent color (subtle alpha)
        $badgeBg = [System.Drawing.Color]::FromArgb(28, $this.Tag.IconColor.R, $this.Tag.IconColor.G, $this.Tag.IconColor.B)
        $badgeBrush = New-Object System.Drawing.SolidBrush($badgeBg)
        $g.FillEllipse($badgeBrush, 22, 24, 56, 56)
        $badgeBrush.Dispose()
    })

    $iLbl = New-Object System.Windows.Forms.Label
    $iLbl.Text      = [char]$IconCode
    $iLbl.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 22)
    $iLbl.ForeColor = $IconColor
    $iLbl.Location  = New-Object System.Drawing.Point(36, 36)
    $iLbl.Size      = New-Object System.Drawing.Size(32, 32)
    $iLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($iLbl)

    $tLbl = New-Object System.Windows.Forms.Label
    $tLbl.Text         = $Title
    $tLbl.UseMnemonic  = $false  # otherwise `&` is eaten as Alt-key accelerator
    $tLbl.Font         = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $tLbl.ForeColor    = $ColText
    $tLbl.Location     = New-Object System.Drawing.Point(20, 96)
    $tLbl.Size         = New-Object System.Drawing.Size(([int]$W - 28), 24)
    $tLbl.BackColor    = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($tLbl)

    $dLbl = New-Object System.Windows.Forms.Label
    $dLbl.Text      = $Desc
    $dLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $dLbl.ForeColor = $ColMuted
    $dLbl.Location  = New-Object System.Drawing.Point(20, 122)
    $dLbl.Size      = New-Object System.Drawing.Size(([int]$W - 28), 56)
    $dLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($dLbl)

    return $pnl
}

# ---- 8 tiles (4×2 grid) — order and copy mirrors the mockup ---------------
$tealBlue   = [System.Drawing.Color]::FromArgb(59, 130, 246)
$accentBlue = [System.Drawing.Color]::FromArgb(96, 165, 250)
$violet     = [System.Drawing.Color]::FromArgb(167, 139, 250)
$cyan       = [System.Drawing.Color]::FromArgb(34, 211, 238)
$emerald    = [System.Drawing.Color]::FromArgb(52, 211, 153)
$amber      = [System.Drawing.Color]::FromArgb(251, 191, 36)
$rose       = [System.Drawing.Color]::FromArgb(248, 113, 113)
$indigo     = [System.Drawing.Color]::FromArgb(129, 140, 248)

$hubCardDefs = @(
    @{ Nav="navSysInfo";    Title="System Overview";        Desc="Hardware specs, OS version, uptime, and Pixellot software versions"; Icon=0xE80F; Color=$tealBlue;   R=0; C=0 }
    @{ Nav="navNetConfig";  Title="Network Configuration";  Desc="IP, DNS, firewall, and connectivity tests for required ports";       Icon=0xE701; Color=$accentBlue; R=0; C=1 }
    @{ Nav="navCamera";     Title="Camera Connectivity";    Desc="Cameras, NICs, link status, and the Fault Isolator wizard";          Icon=0xE722; Color=$cyan;       R=0; C=2 }
    @{ Nav="navServices";   Title="Pixellot Services";      Desc="Pixellot agent, encoder, watchdog, and remote service status";       Icon=0xE9F5; Color=$violet;     R=0; C=3 }
    @{ Nav="navPoE";        Title="PoE / NIC Hardware";     Desc="PoE budget, GPU, monitor, peripherals, and per-port NIC layout";     Icon=0xE7E8; Color=$emerald;    R=1; C=0 }
    @{ Nav="navDisk";       Title="System & Disk Health";   Desc="Free space, SMART health, and disk-related event log errors";        Icon=0xEDA2; Color=$amber;      R=1; C=1 }
    @{ Nav="navEvents";     Title="Event Viewer";           Desc="Recent OS errors filtered to VPU-relevant providers";                Icon=0xE7BA; Color=$rose;       R=1; C=2 }
    @{ Nav="navReports";    Title="Reports";                Desc="View, copy, and export saved diagnostic reports";                    Icon=0xE7C3; Color=$indigo;     R=1; C=3 }
)

# Tile geometry — derived from panel width (resizes responsively).
# ContentArea: $WideW = 1280, margin 28 each side, gap 16, 4 cols ⇒ tile ≈ 290 wide.
$hCH = 200; $hGap = 16; $hMargin = 28; $hCols = 4; $hRows = 2

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
    if ($hCW -lt 50) { $hCW = 50 }
    $hx   = $hMargin + $hc.C * ($hCW + $hGap)
    $hy   = 110 + $hc.R * ($hCH + $hGap)
    $cp   = New-HubTile -Title $hc.Title -Desc $hc.Desc -IconCode $hc.Icon -X $hx -Y $hy -W $hCW -H $hCH -IconColor $hc.Color
    $pnlSysOverview.Controls.Add($cp)
    $script:hubTiles += $cp

    $navBtn = $hubNavLookup[$hc.Nav]
    $clickBlock = { $navBtn.PerformClick() }.GetNewClosure()
    $cp.Add_Click($clickBlock)
    foreach ($ctrl in @($cp.Controls)) { $ctrl.Add_Click($clickBlock); $ctrl.Cursor = [System.Windows.Forms.Cursors]::Hand }
}

# ---- Resize handling -------------------------------------------------------
# Same deterministic recalc + debounce pattern from v1.0.39 (#61). Re-runs the
# full layout via Update-HubTileLayout to avoid drift on window resize.
function Update-HubTileLayout {
    if (-not $script:hubTiles -or $script:hubTiles.Count -eq 0) { return }
    $pw = $pnlSysOverview.ClientSize.Width
    if ($pw -le 0) { return }
    $hCW = [int](($pw - 2*$hMargin - ($hCols-1)*$hGap) / $hCols)
    if ($hCW -lt 50) { $hCW = 50 }
    for ($i = 0; $i -lt $script:hubTiles.Count; $i++) {
        $col  = $i % $hCols
        $row  = [int]($i / $hCols)
        $tile = $script:hubTiles[$i]
        if (-not $tile) { continue }
        $newX = $hMargin + $col * ($hCW + $hGap)
        $newY = 110 + $row * ($hCH + $hGap)
        $tile.Anchor = [System.Windows.Forms.AnchorStyles]::None
        $tile.Bounds = New-Object System.Drawing.Rectangle($newX, $newY, $hCW, $hCH)
        $tile.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $hCW, $hCH)), 10))
    }
    if ($pnlHubActions) {
        $pnlHubActions.Location = New-Object System.Drawing.Point($hMargin, (110 + $hRows*($hCH+$hGap) + 12))
    }
    $pnlSysOverview.Invalidate($true)
}

Update-HubTileLayout

$script:hubResizeTimer = New-Object System.Windows.Forms.Timer
$script:hubResizeTimer.Interval = 80
$script:hubResizeTimer.Add_Tick({
    $script:hubResizeTimer.Stop()
    Update-HubTileLayout
})
$pnlSysOverview.Add_SizeChanged({
    $script:hubResizeTimer.Stop()
    $script:hubResizeTimer.Start()
})

# ---- Bottom action row -----------------------------------------------------
# Run Full Diagnostic (primary) + Open Last Report (secondary), with last-run
# summary text inline. Anchored bottom-stretch so the row reflows on resize.
$pnlHubActions = New-Object System.Windows.Forms.Panel
$pnlHubActions.Size      = New-Object System.Drawing.Size(($pnlSysOverview.Width - 2*$hMargin), 70)
$pnlHubActions.Location  = New-Object System.Drawing.Point($hMargin, (110 + $hRows*($hCH+$hGap) + 12))
$pnlHubActions.BackColor = $ColBg
$pnlSysOverview.Controls.Add($pnlHubActions)

$btnHubRunFull = New-Object System.Windows.Forms.Button
$btnHubRunFull.Text      = [char]0x25B6 + "  Run Full Diagnostic"
$btnHubRunFull.Size      = New-Object System.Drawing.Size(220, 44)
$btnHubRunFull.Location  = New-Object System.Drawing.Point(0, 8)
$btnHubRunFull.BackColor = $ColAccent
$btnHubRunFull.ForeColor = [System.Drawing.Color]::White
$btnHubRunFull.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHubRunFull.FlatAppearance.BorderSize = 0
$btnHubRunFull.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
$btnHubRunFull.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$btnHubRunFull.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnHubRunFull.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 220, 44)), 7))
$pnlHubActions.Controls.Add($btnHubRunFull)
$btnHubRunFull.Add_Click({ Start-FullDiagnostic })

$btnHubLastReport = New-Object System.Windows.Forms.Button
$btnHubLastReport.Text      = "Open Last Report"
$btnHubLastReport.Size      = New-Object System.Drawing.Size(180, 44)
$btnHubLastReport.Location  = New-Object System.Drawing.Point(232, 8)
$btnHubLastReport.BackColor = $ColCard
$btnHubLastReport.ForeColor = $ColText
$btnHubLastReport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHubLastReport.FlatAppearance.BorderColor = $ColBorder
$btnHubLastReport.FlatAppearance.BorderSize  = 1
$btnHubLastReport.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$btnHubLastReport.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnHubLastReport.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 44)), 7))
$pnlHubActions.Controls.Add($btnHubLastReport)

$btnHubLastReport.Add_Click({
    $latest = Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { Start-Process notepad.exe $latest.FullName }
    else { [System.Windows.Forms.MessageBox]::Show("No reports found yet.", "Open Last Report", "OK", "Information") | Out-Null }
})

# Last-run summary line — to the right of the action buttons
$lblHubLastRun = New-Object System.Windows.Forms.Label
$lblHubLastRun.Text         = "Last Run: Never"
$lblHubLastRun.Font         = New-Object System.Drawing.Font("Segoe UI", 9)
$lblHubLastRun.ForeColor    = $ColMuted
$lblHubLastRun.Location     = New-Object System.Drawing.Point(($pnlHubActions.Width - 360), 20)
$lblHubLastRun.Size         = New-Object System.Drawing.Size(360, 22)
$lblHubLastRun.TextAlign    = [System.Drawing.ContentAlignment]::MiddleRight
$lblHubLastRun.AutoEllipsis = $true
$lblHubLastRun.Anchor       = $AnchorTR
$pnlHubActions.Controls.Add($lblHubLastRun)

# Refresh the last-run line whenever the panel becomes visible
$pnlSysOverview.Add_VisibleChanged({
    if (-not $pnlSysOverview.Visible) { return }
    try {
        $latest = Get-ChildItem -Path $OutputDir -Filter "Pulse_Results_*.txt" -ErrorAction SilentlyContinue |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $latest) {
            $lblHubLastRun.Text      = "Last Run: Never"
            $lblHubLastRun.ForeColor = $ColMuted
            return
        }
        $head    = Get-Content $latest.FullName -TotalCount 25 -ErrorAction SilentlyContinue
        $model   = ($head | Where-Object { $_ -match '^VPU Model\s*:\s*(.+)$' } | Select-Object -First 1) -replace '^VPU Model\s*:\s*',''
        $overall = ($head | Where-Object { $_ -match '^(Overall|Result|Status)\s*:\s*(.+)$' } | Select-Object -First 1)
        $whenStr = $latest.LastWriteTime.ToString("MMM d, h:mm tt")
        $modelStr = if ($model)   { " — $model" }                       else { "" }
        $resStr   = if ($overall) { ($overall -replace '^[^:]+:\s*','') } else { "" }
        $color = if ($resStr -match 'fail|error|critical') { $ColRed } `
                 elseif ($resStr -match 'warn|issue|degrad') { $ColYellow } `
                 elseif ($resStr) { $ColGreen } `
                 else { $ColMuted }
        $resBlock = if ($resStr) { "   |   $resStr" } else { "" }
        $lblHubLastRun.Text      = "Last Run: $whenStr$modelStr$resBlock"
        $lblHubLastRun.ForeColor = $color
    } catch {
        $lblHubLastRun.Text      = "Last Run: report unreadable"
        $lblHubLastRun.ForeColor = $ColMuted
    }
})
