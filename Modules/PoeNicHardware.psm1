# =============================================================================
#  PoeNicHardware.psm1  -  VPU Hardware panel
#  Shows GPU model, monitor/mouse/keyboard status, NIC link uptime, and PoE data.
#  NIC uptime and PoE data are populated by the Camera Connectivity runspace;
#  this panel reads them from $sync without a second DLL call.
# =============================================================================

# ---------- VPU Hardware background script -----------------------------------
$HwScript = {
    param($sync)
    $sync.HwRunning = $true; $sync.HwComplete = $false; $sync.HwCancelled = $false
    $item = $null; while ($sync.HwQueue.TryDequeue([ref]$item)) { }
    function Hw-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.HwQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Hw-Section { param([string]$Title)
        $sync.HwQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    # -- GPU model ---------------------------------------------------------------
    # Prefer discrete GPU over integrated (Intel UHD/HD Graphics) when both are present.
    # The Pixellot encoding workload runs on the discrete card; surfacing the iGPU
    # mis-leads IT teams diagnosing performance issues.
    $sync.HwStep = "Querying GPU..."
    Hw-Section "Graphics"
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
                  Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" })
        $discrete = @($gpus | Where-Object { $_.Name -notlike "*Intel*" -and $_.Name -notlike "*Microsoft*" })
        if ($discrete.Count -gt 0) { $gpus = $discrete }
        $gpu = $gpus | Select-Object -First 1
        $gpuName = if ($gpu) { $gpu.Name } else { "Not detected" }
        Hw-Log "GPU" $gpuName "Info"
        $sync.Cards["HwGpu"] = @{ Value=$gpuName; Status="neutral" }
    } catch {
        Hw-Log "GPU" "Query failed" "Warn"
        $sync.Cards["HwGpu"] = @{ Value="Error"; Status="warn" }
    }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- Monitor connection -------------------------------------------------------
    $sync.HwStep = "Checking monitor..."
    Hw-Section "Peripherals"
    $monCount = 0
    try {
        $monitors = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction Stop |
                      Where-Object { $_.Availability -eq 3 })
        $monCount = $monitors.Count
        if ($monCount -eq 0) {
            $pnpMon = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Monitor'" -ErrorAction SilentlyContinue)
            $monCount = $pnpMon.Count
        }
        $monStr = if ($monCount -gt 0) { "$monCount connected" } else { "None detected" }
        $monLvl = if ($monCount -gt 0) { "Pass" } else { "Warn" }
        Hw-Log "Monitor" $monStr $monLvl
        $sync.Cards["HwMonitor"] = @{ Value=$monStr; Status=if($monCount -gt 0){"ok"}else{"warn"} }
    } catch {
        Hw-Log "Monitor" "Query failed" "Warn"
        $sync.Cards["HwMonitor"] = @{ Value="Error"; Status="warn" }
    }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- Mouse & keyboard ---------------------------------------------------------
    $sync.HwStep = "Checking peripherals..."
    $mouseOk = $false; $kbdOk = $false
    try {
        $mouseOk = (@(Get-CimInstance Win32_PointingDevice -ErrorAction Stop)).Count -gt 0
        Hw-Log "Mouse"    $(if($mouseOk){"Connected"}else{"None"}) $(if($mouseOk){"Pass"}else{"Warn"})
    } catch { Hw-Log "Mouse"    "Query failed" "Warn" }
    try {
        $kbdOk = (@(Get-CimInstance Win32_Keyboard -ErrorAction Stop)).Count -gt 0
        Hw-Log "Keyboard" $(if($kbdOk){"Connected"}else{"None"}) $(if($kbdOk){"Pass"}else{"Warn"})
    } catch { Hw-Log "Keyboard" "Query failed" "Warn" }

    $ms = if ($mouseOk) { [char]0x2713 } else { [char]0x2717 }
    $kb = if ($kbdOk)   { [char]0x2713 } else { [char]0x2717 }
    $mmkStr    = "Mouse:$ms  KB:$kb"
    $mmkStatus = if ($mouseOk -and $kbdOk) { "ok" } else { "warn" }
    $sync.Cards["HwMmk"] = @{ Value=$mmkStr; Status=$mmkStatus }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- NIC port uptime (cached by Camera Connectivity runspace) ----------------
    $sync.HwStep = "Reading NIC uptime..."
    Hw-Section "NIC Port Uptime"
    if ($sync.NicLinkUptimes.Count -gt 0) {
        foreach ($entry in @($sync.NicLinkUptimes)) {
            $lvl = if ($entry.Uptime -eq ">48h") { "Pass" } else { "Info" }
            Hw-Log $entry.Name "Link up: $($entry.Uptime)" $lvl
        }
    } else {
        Hw-Log "NIC Uptime" "Run Camera Connectivity first to collect uptime data" "Gray"
    }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- PoE data (cached by Camera Connectivity runspace) -----------------------
    $sync.HwStep = "Reading PoE data..."
    Hw-Section "PoE Status"
    if ($sync.PoeAvailable -and $sync.PoePortData.Count -gt 0) {
        Hw-Log "Total Budget" ("{0:F1} W  (Consumed: {1:F1} W)" -f $sync.PoeTotal, $sync.PoeConsumed) "Info"
        Hw-Log "NIC Temp"     ("{0:F1}$([char]0xB0)C" -f $sync.PoeTemp) "Info"
        foreach ($p in @($sync.PoePortData)) {
            $stateStr = if ($p.PoeOn) { "PoE ON" } else { "PoE OFF" }
            $lvl      = if ($p.PoeOn) { "Pass" } else { "Gray" }
            Hw-Log $p.Port ("{0:F2} V  {1:F3} A  {2:F1} W  [{3}]" -f $p.Voltage, $p.Current, $p.Watts, $stateStr) $lvl
        }
        if ($sync.PoeBudgetLow) {
            Hw-Log "Budget" ("LOW: {0:F0} W - check Molex connector on PoE NIC" -f $sync.PoeTotal) "Fail"
        }
    } else {
        Hw-Log "PoE Data" "Run Camera Connectivity first to collect PoE data" "Gray"
    }

    $sync.HwStep = "Complete"; $sync.HwRunning=$false; $sync.HwComplete=$true
}


# ---------- VPU Hardware timer -----------------------------------------------
$hwTimer = New-Object System.Windows.Forms.Timer; $hwTimer.Interval = 300
$hwTimer.Add_Tick({
    $hwItem = $null
    while ($sync.HwQueue.TryDequeue([ref]$hwItem)) {
        Add-LogRow $dgvHwLog $hwItem.Label $hwItem.Result $hwItem.L
    }
    foreach ($key in $hwCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $hwCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $hwCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.HwRunning) {
        $script:hwSpinIdx=($script:hwSpinIdx+1)%4
        $lblHwStatus.ForeColor=$ColAccent
        $lblHwStatus.Text=" $(@('|','/','-','\')[$script:hwSpinIdx])  $($sync.HwStep)"
    }
    if ($sync.HwComplete -and -not $sync.HwRunning) {
        $hwTimer.Stop(); $btnHwCancel.Visible=$false
        $btnHwRun.Enabled=$true; $btnHwRun.Text=[char]0x25B6+"  Run Full Diagnostic"
        $lblHwStatus.ForeColor=$ColMuted; $lblHwStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"
        # Refresh the port diagram with current link state (#7)
        try { Update-HwPortDiagram } catch { }

        # Update Overall Status pill from worst card status
        $hwWorst = "ok"
        $pri = @{ fail=3; warn=2; ok=1; neutral=0 }
        foreach ($k in @("HwGpu","HwMonitor","HwMmk")) {
            if ($sync.Cards.ContainsKey($k)) {
                $s = $sync.Cards[$k].Status
                if ($s -and $pri[$s] -gt $pri[$hwWorst]) { $hwWorst = $s }
            }
        }
        Set-SectionPill $hwHeader $hwWorst

        # Build Summary
        $sumItems = @()
        $gpuC = $sync.Cards["HwGpu"]
        if ($gpuC -and $gpuC.Value -ne "--") { $sumItems += @{ Status="ok"; Text="GPU detected: $($gpuC.Value)" } }
        $monC = $sync.Cards["HwMonitor"]
        if ($monC) { $sumItems += @{ Status=$monC.Status; Text="Monitor: $($monC.Value)" } }
        $mmkC = $sync.Cards["HwMmk"]
        if ($mmkC) { $sumItems += @{ Status=$mmkC.Status; Text="Input devices: $($mmkC.Value)" } }
        if ($sync.NicLinkUptimes -and $sync.NicLinkUptimes.Count -gt 0) {
            $sumItems += @{ Status="ok"; Text="$($sync.NicLinkUptimes.Count) NIC ports reporting link uptime" }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No hardware data collected" }) }
        Set-SummaryItems $hwSummary $sumItems
    }
})


# ---- VPU Hardware Panel -----------------------------------------------------
$pnlPoE = New-Object System.Windows.Forms.Panel
$pnlPoE.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlPoE.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlPoE.BackColor = $ColBg; $pnlPoE.Visible = $false; $pnlPoE.Anchor = $AnchorTLRB
$form.Controls.Add($pnlPoE)

# v1.0.43 redesign — section header (with status pill) + cards + NIC port diagram + action bar
$hwHeader = New-SectionHeader -Parent $pnlPoE `
    -Title    "PoE / NIC Hardware" `
    -Subtitle "GPU, peripherals, NIC link uptime, PoE power, and physical port layout."

# When Camera Connectivity hasn't run, surface a yellow note in the subtitle position.
$script:hwSubDefault = $hwHeader.Subtitle.Text
$pnlPoE.Add_VisibleChanged({
    if (-not $pnlPoE.Visible) { return }
    if (-not $sync.NicLinkUptimes -or $sync.NicLinkUptimes.Count -eq 0) {
        $hwHeader.Subtitle.Text      = "Run Camera Connectivity first to populate PoE budget and NIC uptime."
        $hwHeader.Subtitle.ForeColor = $ColYellow
    } else {
        $hwHeader.Subtitle.Text      = $script:hwSubDefault
        $hwHeader.Subtitle.ForeColor = $ColMuted
    }
})

# 3 status cards — GPU / Monitor / Input — at Y=110
$hwCardDefs = @(
    @{ Key="HwGpu";     Title="GPU";           Sub="Graphics adapter";   X=28;   Icon=[char]0xE7F4; W=400 }
    @{ Key="HwMonitor"; Title="Monitor";       Sub="Display connected";  X=440;  Icon=[char]0xE7F4; W=400 }
    @{ Key="HwMmk";     Title="Input Devices"; Sub="Keyboard & mouse";   X=852;  Icon=[char]0xE7C8; W=400 }
)
$hwCards = @{}
foreach ($cd in $hwCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 110 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $hwCards[$cd.Key] = $c; $pnlPoE.Controls.Add($c.Panel)
}

$lblHwStatus = New-Object System.Windows.Forms.Label
$lblHwStatus.Text      = ""
$lblHwStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblHwStatus.ForeColor = $ColMuted
$lblHwStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblHwStatus.Size      = New-Object System.Drawing.Size(($pnlPoE.Width - 56), 16)
$lblHwStatus.Anchor    = $AnchorBLR
$pnlPoE.Controls.Add($lblHwStatus)

# ---- NIC Port Layout — horizontal "card + ports below" mockup-style design (#7) -------
# Layout from top to bottom in the panel area Y=242..602:
#   1. Section header at Y=242
#   2. Stylized NIC bracket render at Y=266 (~80 high) with 4 jack rectangles + status light
#   3. Leader lines (drawn in Paint) from each jack down to its info box
#   4. Row of 4 port info boxes at Y=380, ~120 high, with port number / status / speed / duplex / errors
#   5. Hardware Details log below at Y=508
# Right sidebar (always visible) at X=1010, W=240: NIC Info card + Status Legend card.

$lblHwPortHdr = New-Object System.Windows.Forms.Label
$lblHwPortHdr.Text      = "NIC Port Layout"
$lblHwPortHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$lblHwPortHdr.ForeColor = $ColText
$lblHwPortHdr.Location  = New-Object System.Drawing.Point(28, 218)
$lblHwPortHdr.AutoSize  = $true
$pnlPoE.Controls.Add($lblHwPortHdr)

$lblHwPortSub = New-Object System.Windows.Forms.Label
$lblHwPortSub.Text      = "Physical port mapping with live link state. Port 1 sits next to the status light on the actual card."
$lblHwPortSub.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblHwPortSub.ForeColor = $ColMuted
$lblHwPortSub.Location  = New-Object System.Drawing.Point(158, 221)
$lblHwPortSub.AutoSize  = $true
$pnlPoE.Controls.Add($lblHwPortSub)

# Container panel for the card-and-ports visualization. Custom Paint event draws the
# NIC bracket outline, jack rectangles, status light, and leader lines from each
# jack down to its info box.
$pnlHwNicCanvas = New-Object System.Windows.Forms.Panel
$pnlHwNicCanvas.Size      = New-Object System.Drawing.Size(990, 200)
$pnlHwNicCanvas.Location  = New-Object System.Drawing.Point(28, 246)
$pnlHwNicCanvas.BackColor = $ColCard
$pnlHwNicCanvas.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 990, 200)), 8))
$pnlPoE.Controls.Add($pnlHwNicCanvas)

# Constants for the canvas Paint — easier to tune without touching multiple call sites.
$script:nicCardY      = 18           # top of the card body inside the canvas
$script:nicCardH      = 90           # card body height (PCB area)
$script:nicJackY      = 38           # top of the jack openings (relative to canvas)
$script:nicJackH      = 36           # jack rectangle height
$script:nicJackW      = 64           # jack rectangle width
$script:nicJackGap    = 14           # gap between jacks
# Center the row of 4 jacks within the canvas. Status light sits to the LEFT of port 1.
# Total jack-row width = 4*64 + 3*14 = 298. Plus status-light area (~40) on the left.
$script:nicJackRowW   = 4 * $script:nicJackW + 3 * $script:nicJackGap   # 298
$script:nicStatusOffX = 36           # status light is this far left of port 1
$script:nicJackStartX = [int](( ($pnlHwNicCanvas.Width) - $script:nicJackRowW + $script:nicStatusOffX) / 2)
$script:nicLightX     = $script:nicJackStartX - $script:nicStatusOffX
# Port info boxes sit below the canvas — record their target connection points so
# the leader lines can dock correctly.
$script:nicPortBoxY   = 460          # absolute Y of port info boxes (in pnlPoE coords)
$script:nicCanvasBaseY= 246          # absolute Y of canvas top-left
$script:nicPortBoxW   = 240          # width of each port info box
$script:nicPortBoxH   = 110

# Custom Paint — draws PCB rectangle, 4 RJ45 jack openings, status light next to Port 1,
# and short connector stubs hanging down from each jack. Full leader lines are drawn
# on the parent pnlPoE Paint event since they cross panel boundaries.
$pnlHwNicCanvas.Add_Paint({
    $g = $args[1].Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
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
    $brkRect  = New-Object System.Drawing.Rectangle(20, ($script:nicCardY + $script:nicCardH), ($cw - 40), 18)
    $g.FillRectangle($brkBrush, $brkRect); $brkBrush.Dispose()
    # Status light — small green LED next to Port 1 (bottom-left jack position)
    $litX = $script:nicLightX
    $litY = $script:nicJackY + ($script:nicJackH / 2) - 5
    $litBrush = New-Object System.Drawing.SolidBrush($ColGreen)
    $g.FillEllipse($litBrush, $litX, $litY, 10, 10); $litBrush.Dispose()
    # Tiny "PWR" label under the status light for clarity
    $hintFont = New-Object System.Drawing.Font("Segoe UI", 7)
    $hintBrush = New-Object System.Drawing.SolidBrush($ColMuted)
    $g.DrawString("PWR", $hintFont, $hintBrush, ($litX - 6), ($litY + 14))
    $hintFont.Dispose(); $hintBrush.Dispose()
    # 4 RJ45 jack openings (Port 1 leftmost — matches photo)
    $jackBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(15, 25, 35))
    $jackPen   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 90, 100), 1)
    for ($p = 0; $p -lt 4; $p++) {
        $jx = $script:nicJackStartX + $p * ($script:nicJackW + $script:nicJackGap)
        $jackRect = New-Object System.Drawing.Rectangle($jx, $script:nicJackY, $script:nicJackW, $script:nicJackH)
        $g.FillRectangle($jackBrush, $jackRect)
        $g.DrawRectangle($jackPen, $jackRect)
        # "Port N" label below each jack
        $lblFont  = New-Object System.Drawing.Font("Segoe UI", 7.5)
        $lblBrush = New-Object System.Drawing.SolidBrush($ColMuted)
        $g.DrawString("Port $($p + 1)", $lblFont, $lblBrush, ($jx + 12), ($script:nicJackY + $script:nicJackH + 22))
        $lblFont.Dispose(); $lblBrush.Dispose()
    }
    $jackBrush.Dispose(); $jackPen.Dispose()

    # Per-port colored LED dots inside each jack — fill in based on $script:hwPortLedColors
    if ($script:hwPortLedColors -and $script:hwPortLedColors.Count -ge 4) {
        for ($p = 0; $p -lt 4; $p++) {
            $jx = $script:nicJackStartX + $p * ($script:nicJackW + $script:nicJackGap)
            $ledX = $jx + ($script:nicJackW / 2) - 4
            $ledY = $script:nicJackY + $script:nicJackH - 12
            $ledBrush = New-Object System.Drawing.SolidBrush($script:hwPortLedColors[$p])
            $g.FillEllipse($ledBrush, $ledX, $ledY, 8, 8)
            $ledBrush.Dispose()
        }
    }
})
$script:hwPortLedColors = @($ColMuted, $ColMuted, $ColMuted, $ColMuted)

# 4 port info boxes — horizontal row below the canvas. Port 1 leftmost, Port 4 rightmost
# (matches photo orientation and the canvas above).
$script:hwPortTiles = @()
$portBoxStartX = 28
$portBoxGap    = 12
for ($p = 0; $p -lt 4; $p++) {
    $portNum = $p + 1   # left-to-right: 1, 2, 3, 4
    $tileX   = $portBoxStartX + $p * ($script:nicPortBoxW + $portBoxGap)
    $tile = New-Object System.Windows.Forms.Panel
    $tile.Size      = New-Object System.Drawing.Size($script:nicPortBoxW, $script:nicPortBoxH)
    $tile.Location  = New-Object System.Drawing.Point($tileX, $script:nicPortBoxY)
    $tile.BackColor = $ColCard
    $tile.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $script:nicPortBoxW, $script:nicPortBoxH)), 6))
    $pnlPoE.Controls.Add($tile)

    # Header row — Port N + status icon + status text
    $lblNum = New-Object System.Windows.Forms.Label
    $lblNum.Text      = "Port $portNum"
    $lblNum.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
    $lblNum.ForeColor = $ColText
    $lblNum.Location  = New-Object System.Drawing.Point(12, 8)
    $lblNum.Size      = New-Object System.Drawing.Size(80, 20)
    $tile.Controls.Add($lblNum)

    $lblStatusIcon = New-Object System.Windows.Forms.Label
    $lblStatusIcon.Text      = [char]0x26AB   # neutral dot until populated
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
    $lblStatusText.Size      = New-Object System.Drawing.Size(100, 20)
    $tile.Controls.Add($lblStatusText)

    # Detail rows: Speed / Duplex / MAC / Errors
    function _AddPortRow {
        param($parent, $y, $label, $valueRef, $ColMuted, $ColText)
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
    $lblSpeedV  = _AddPortRow $tile 36 "Speed:"  $null $ColMuted $ColText
    $lblDuplexV = _AddPortRow $tile 54 "Duplex:" $null $ColMuted $ColText
    $lblMacV    = _AddPortRow $tile 72 "MAC:"    $null $ColMuted $ColText
    $lblMacV.Font = New-Object System.Drawing.Font("Consolas", 8)
    $lblErrV    = _AddPortRow $tile 90 "Errors:" $null $ColMuted $ColText

    $script:hwPortTiles += @{
        PortNum   = $portNum
        Tile      = $tile
        StatusIcn = $lblStatusIcon
        StatusTxt = $lblStatusText
        SpeedV    = $lblSpeedV
        DuplexV   = $lblDuplexV
        MacV      = $lblMacV
        ErrV      = $lblErrV
    }
}

# Right sidebar — NIC Information card + Status Legend
# X = 1010 puts it past the 990-wide canvas (which starts at X=10). Full panel width is 1280.
# So sidebar gets ~250 wide.
$pnlHwNicInfo = New-Object System.Windows.Forms.Panel
$pnlHwNicInfo.Size      = New-Object System.Drawing.Size(240, 150)
$pnlHwNicInfo.Location  = New-Object System.Drawing.Point(1024, 246)
$pnlHwNicInfo.BackColor = $ColCard
$pnlHwNicInfo.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 240, 150)), 8))
$pnlPoE.Controls.Add($pnlHwNicInfo)

$lblNicInfoHdr = New-Object System.Windows.Forms.Label
$lblNicInfoHdr.Text      = "NIC Information"
$lblNicInfoHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$lblNicInfoHdr.ForeColor = $ColText
$lblNicInfoHdr.Location  = New-Object System.Drawing.Point(12, 10)
$lblNicInfoHdr.AutoSize  = $true
$pnlHwNicInfo.Controls.Add($lblNicInfoHdr)

$script:hwNicInfoLines = @{}
$infoRows = @("Model","MAC Base","Driver","Total ports")
$ny = 32
foreach ($row in $infoRows) {
    $lblL = New-Object System.Windows.Forms.Label
    $lblL.Text      = "$($row):"
    $lblL.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblL.ForeColor = $ColMuted
    $lblL.Location  = New-Object System.Drawing.Point(12, $ny)
    $lblL.Size      = New-Object System.Drawing.Size(76, 16)
    $pnlHwNicInfo.Controls.Add($lblL)
    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text      = "--"
    $lblV.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblV.ForeColor = $ColText
    $lblV.Location  = New-Object System.Drawing.Point(88, $ny)
    $lblV.Size      = New-Object System.Drawing.Size(140, 16)
    $pnlHwNicInfo.Controls.Add($lblV)
    $script:hwNicInfoLines[$row] = $lblV
    $ny += 22
}

# Status Legend card
$pnlHwLegend = New-Object System.Windows.Forms.Panel
$pnlHwLegend.Size      = New-Object System.Drawing.Size(240, 130)
$pnlHwLegend.Location  = New-Object System.Drawing.Point(1024, 408)
$pnlHwLegend.BackColor = $ColCard
$pnlHwLegend.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 240, 130)), 8))
$pnlPoE.Controls.Add($pnlHwLegend)

$lblLegendHdr = New-Object System.Windows.Forms.Label
$lblLegendHdr.Text      = "Status Legend"
$lblLegendHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$lblLegendHdr.ForeColor = $ColText
$lblLegendHdr.Location  = New-Object System.Drawing.Point(12, 10)
$lblLegendHdr.AutoSize  = $true
$pnlHwLegend.Controls.Add($lblLegendHdr)

$legendItems = @(
    @{ Color=$ColGreen;  Text="Linked - 1 Gbps healthy" },
    @{ Color=$ColYellow; Text="Degraded - sub-gigabit" },
    @{ Color=$ColMuted;  Text="No cable / disabled" },
    @{ Color=$ColRed;    Text="Error / fault" }
)
$ly = 34
foreach ($it in $legendItems) {
    $dot = New-Object System.Windows.Forms.Panel
    $dot.Size      = New-Object System.Drawing.Size(10, 10)
    $dot.Location  = New-Object System.Drawing.Point(14, ($ly + 4))
    $dot.BackColor = $it.Color
    $dot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 10, 10)), 5))
    $pnlHwLegend.Controls.Add($dot)
    $lblL = New-Object System.Windows.Forms.Label
    $lblL.Text      = $it.Text
    $lblL.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblL.ForeColor = $ColText
    $lblL.Location  = New-Object System.Drawing.Point(32, $ly)
    $lblL.Size      = New-Object System.Drawing.Size(200, 18)
    $pnlHwLegend.Controls.Add($lblL)
    $ly += 22
}

# Hardware Details log card — sits left, Summary panel sits right
$hwLogCard = New-Object System.Windows.Forms.Panel
$hwLogCard.Size      = New-Object System.Drawing.Size(740, 90)
$hwLogCard.Location  = New-Object System.Drawing.Point(28, 588)
$hwLogCard.BackColor = $ColCard
$hwLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 740, 90)), 8))
$pnlPoE.Controls.Add($hwLogCard)

$lblHwLogHdr = New-Object System.Windows.Forms.Label
$lblHwLogHdr.Text      = "Hardware Details"
$lblHwLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblHwLogHdr.ForeColor = $ColText
$lblHwLogHdr.Location  = New-Object System.Drawing.Point(16, 10)
$lblHwLogHdr.AutoSize  = $true
$hwLogCard.Controls.Add($lblHwLogHdr)

$dgvHwLog = New-LogGrid -X 8 -Y 32 -W 724 -H 50
$hwLogCard.Controls.Add($dgvHwLog)

$hwSummary = New-SummaryPanel -Parent $pnlPoE -X 784 -Y 588 -W 480 -H 90 -Title "Summary"
Set-SummaryItems $hwSummary @(@{ Status="neutral"; Text="Run Full Diagnostic to populate the summary" })

# Bottom action bar
$hwActions = New-ActionBar -Parent $pnlPoE -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Full Diagnostic")
$btnHwRun    = $hwActions.PrimaryBtn
$btnHwExport = $hwActions.ExportBtn

$btnHwCancel = New-Object System.Windows.Forms.Button
$btnHwCancel.Text      = "Cancel"
$btnHwCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnHwCancel.Location  = New-Object System.Drawing.Point(168, 10)
$btnHwCancel.BackColor = $ColRed
$btnHwCancel.ForeColor = [System.Drawing.Color]::White
$btnHwCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHwCancel.FlatAppearance.BorderSize = 0
$btnHwCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnHwCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnHwCancel.Visible   = $false
$btnHwCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$hwActions.Bar.Controls.Add($btnHwCancel)

$lblHwEta = New-Object System.Windows.Forms.Label
$lblHwEta.Visible = $false
$pnlPoE.Controls.Add($lblHwEta)

# Refresh function — populates the 4 tiles from Get-NetAdapter, sorted by MAC ascending
# so index 0 of sorted = Port 1 (lowest MAC). Tiles are arranged top-to-bottom 4,3,2,1
# so we index them in reverse.
function Update-HwPortDiagram {
    # Try the Pixellot-NIC driver patterns first (Intel I210/I211/I350/I354/82574L).
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

    # Fallback: if no NICs match the strict driver patterns, show ALL physical adapters
    # sorted by MAC. Better to display SOMETHING than blank tiles.
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

    # Tiles are indexed 0..3 corresponding to port numbers 1..4 (left to right).
    # sortedNics is also 0..N where index 0 is the lowest MAC = Port 1.
    $ledColors = @($ColMuted, $ColMuted, $ColMuted, $ColMuted)
    for ($tileIdx = 0; $tileIdx -lt 4; $tileIdx++) {
        $tile = $script:hwPortTiles[$tileIdx]
        $portNum  = $tile.PortNum
        $sortIdx  = $portNum - 1
        if ($sortIdx -lt $sortedNics.Count) {
            $nic = $sortedNics[$sortIdx]
            $mac = $nic.MacAddress
            $speed = $nic.LinkSpeed
            $status = $nic.Status
            $isUp = ($status -eq "Up")
            # Speed label: short form
            $speedLabel = if ($speed -and $speed -match '(\d+)\s*Gbps')      { "$($Matches[1]) Gbps" } `
                          elseif ($speed -and $speed -match '(\d+)\s*Mbps') { "$($Matches[1]) Mbps" } `
                          elseif ($isUp)                                     { "Up" } `
                          else                                                { "--" }
            # Color tier: green = 1 Gbps healthy, yellow = sub-gigabit linked, gray = no link
            $tier = if (-not $isUp)                            { "off"  } `
                    elseif ($speed -match '^1\s*Gbps')         { "ok"   } `
                    elseif ($speed -match '(100|10)\s*Mbps')   { "warn" } `
                    else                                       { "info" }
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
            $duplexLabel = if ($nic.FullDuplex -eq $true) { "Full" } `
                           elseif ($nic.FullDuplex -eq $false) { "Half" } `
                           else { "--" }
            # Errors counter — try Get-NetAdapterStatistics for cumulative bad packets
            $errCount = "--"
            try {
                $stats = Get-NetAdapterStatistics -Name $nic.Name -ErrorAction SilentlyContinue
                if ($stats) {
                    $err = [long]([long]$stats.OutboundPacketsWithErrors + [long]$stats.ReceivedPacketsWithErrors)
                    $errCount = "$err"
                }
            } catch { }

            $tile.StatusIcn.Text      = if ($tier -eq "off") { [char]0x26AB } elseif ($tier -eq "warn") { [char]0x26A0 } else { [char]0x25CF }
            $tile.StatusIcn.ForeColor = $accentColor
            $tile.StatusTxt.Text      = $statusText
            $tile.StatusTxt.ForeColor = $accentColor
            $tile.SpeedV.Text         = $speedLabel
            $tile.SpeedV.ForeColor    = if ($isUp) { $accentColor } else { $ColMuted }
            $tile.DuplexV.Text        = $duplexLabel
            $tile.MacV.Text           = $mac
            $tile.ErrV.Text           = $errCount
            $tile.ErrV.ForeColor      = if ($errCount -ne "--" -and [int]$errCount -gt 0) { $ColYellow } else { $ColText }
            $ledColors[$portNum - 1]  = $accentColor
        } else {
            $tile.StatusIcn.Text      = [char]0x26AB
            $tile.StatusIcn.ForeColor = $ColMuted
            $tile.StatusTxt.Text      = "Not detected"
            $tile.StatusTxt.ForeColor = $ColMuted
            $tile.SpeedV.Text         = "--"
            $tile.DuplexV.Text        = "--"
            $tile.MacV.Text           = "--"
            $tile.ErrV.Text           = "--"
        }
    }

    # Refresh the in-jack LED colors and repaint the canvas
    $script:hwPortLedColors = $ledColors
    if ($pnlHwNicCanvas) { $pnlHwNicCanvas.Invalidate() }

    # Populate the right-sidebar NIC Information card
    if ($script:hwNicInfoLines) {
        $modelInfo = $null
        try { $modelInfo = Get-AdlinkCardInfo $sortedNics } catch { }
        $modelStr = if ($modelInfo -and $modelInfo.Label) { $modelInfo.Label } `
                    elseif ($sortedNics.Count -gt 0)       { $sortedNics[0].InterfaceDescription } `
                    else                                    { "Not detected" }
        $macBase = if ($sortedNics.Count -gt 0) { $sortedNics[0].MacAddress } else { "--" }
        $driverState = if ($sortedNics.Count -gt 0 -and $sortedNics[0].Status) { "Loaded" } else { "Not loaded" }
        $totalPorts  = "$($sortedNics.Count) detected"
        if ($script:hwNicInfoLines["Model"])       { $script:hwNicInfoLines["Model"].Text       = $modelStr }
        if ($script:hwNicInfoLines["MAC Base"])    { $script:hwNicInfoLines["MAC Base"].Text    = $macBase }
        if ($script:hwNicInfoLines["Driver"])      { $script:hwNicInfoLines["Driver"].Text      = $driverState }
        if ($script:hwNicInfoLines["Driver"])      { $script:hwNicInfoLines["Driver"].ForeColor = if ($driverState -eq "Loaded") { $ColGreen } else { $ColRed } }
        if ($script:hwNicInfoLines["Total ports"]) { $script:hwNicInfoLines["Total ports"].Text = $totalPorts }
    }
}

# Refresh the diagram when the panel becomes visible AND when a hardware diagnostic
# completes (in case link state changed during the test).
$pnlPoE.Add_VisibleChanged({
    if ($pnlPoE.Visible) { try { Update-HwPortDiagram } catch { } }
})

$script:hwRunspace = $null; $script:hwPs = $null; $script:hwSpinIdx = 0


function Start-HwDiagnostic {
    if ($sync.HwRunning) { return }
    $sync.HwCancelled = $false
    foreach ($key in $hwCards.Keys) { $sync.Cards[$key] = @{ Value="--"; Status="neutral" } }
    foreach ($key in $hwCards.Keys) { Update-CardStatus -Card $hwCards[$key] -Value "--" -Status "neutral" }
    $dgvHwLog.Rows.Clear(); $btnHwRun.Enabled=$false; $btnHwRun.Text="  Running..."
    $btnHwCancel.Visible=$true; $script:hwSpinIdx=0
    $lblHwStatus.ForeColor=$ColAccent; $lblHwStatus.Text=" |  Starting..."
    if ($script:hwRunspace) { try { $script:hwRunspace.Close() } catch { } }
    if ($script:hwPs) { try { $script:hwPs.Dispose() } catch { }; $script:hwPs = $null }
    $script:hwRunspace = [runspacefactory]::CreateRunspace()
    $script:hwRunspace.ApartmentState="STA"; $script:hwRunspace.ThreadOptions="ReuseThread"; $script:hwRunspace.Open()
    $script:hwPs = [powershell]::Create(); $script:hwPs.Runspace=$script:hwRunspace
    $script:hwPs.AddScript($HwScript) | Out-Null
    $script:hwPs.AddParameters(@{ sync=$sync }) | Out-Null
    $script:hwPs.BeginInvoke() | Out-Null; $hwTimer.Start()
}

$btnHwRun.Add_Click({ Start-HwDiagnostic })
$btnHwCancel.Add_Click({ $sync.HwCancelled=$true; $btnHwCancel.Visible=$false })
