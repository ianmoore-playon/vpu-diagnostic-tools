# =============================================================================
#  UIHelpers.psm1  -  WinForms bootstrap, colors, and shared GUI helpers
# =============================================================================

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

if ($PoeDllPath -and -not ([System.Management.Automation.PSTypeName]'AdlinkPoE').Type) {
    $env:PATH = "$([System.IO.Path]::GetDirectoryName($PoeDllPath));$env:PATH"
    Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class AdlinkPoE {
    // Register_Card: pass card index (0 for first card); returns 0 on success, negative on error.
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Register_Card(ushort card_num);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Release_Card(ushort wCardNumber);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_Temperature(ushort wCardNumber, out double wTemperature);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_POEConsPowbudget(ushort wCardNumber, out double wPower);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_POELeftPowbudget(ushort wCardNumber, out double wPower);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_PSEPortCurrent(ushort wCardNumber, ushort PortNumber, out double wCurrent);
    [DllImport("SmartPoE.dll")]
    public static extern short SmartPoE_Get_PSEPortVoltage(ushort wCardNumber, ushort PortNumber, out double wVoltage);
}
"@
}

if ($VpuTheme -eq "light") {
    # ---- Light palette -------------------------------------------------------
    $ColSidebar    = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $ColNavHover   = [System.Drawing.Color]::FromArgb(226, 232, 240)
    $ColNavActive  = [System.Drawing.Color]::FromArgb(37,  99,  235)
    $ColAccent     = [System.Drawing.Color]::FromArgb(37,  99,  235)
    $ColBg         = [System.Drawing.Color]::FromArgb(241, 245, 249)
    $ColCard       = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $ColBorder     = [System.Drawing.Color]::FromArgb(203, 213, 225)
    $ColText       = [System.Drawing.Color]::FromArgb(15,  23,  42)
    $ColMuted      = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $ColGreen      = [System.Drawing.Color]::FromArgb(22,  163,  74)
    $ColRed        = [System.Drawing.Color]::FromArgb(220,  38,  38)
    $ColYellow     = [System.Drawing.Color]::FromArgb(161,  98,   7)
    $ColLogBg      = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $ColBadgeOkBg  = [System.Drawing.Color]::FromArgb(220, 252, 231)
    $ColBadgeErrBg = [System.Drawing.Color]::FromArgb(254, 226, 226)
    $ColBadgeRunBg = [System.Drawing.Color]::FromArgb(254, 243, 199)
    $ColLogPass    = [System.Drawing.Color]::FromArgb(21,  128,  61)
    $ColLogFail    = [System.Drawing.Color]::FromArgb(185,  28,  28)
    $ColLogWarn    = [System.Drawing.Color]::FromArgb(146,  64,  14)
    $ColLogCyan    = [System.Drawing.Color]::FromArgb(14,  116, 144)
    $ColLogText    = [System.Drawing.Color]::FromArgb(30,  41,  59)
    $ColLogLabel   = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $ColFailBg     = [System.Drawing.Color]::FromArgb(254, 226, 226)
    $ColWarnBg     = [System.Drawing.Color]::FromArgb(254, 243, 199)
    $ColOkBg       = [System.Drawing.Color]::FromArgb(220, 252, 231)
} else {
    # ---- Dark palette (default) ---------------------------------------------
    $ColSidebar    = [System.Drawing.Color]::FromArgb(15,  22,  36)
    $ColNavHover   = [System.Drawing.Color]::FromArgb(38,  52,  70)
    $ColNavActive  = [System.Drawing.Color]::FromArgb(37,  99, 235)
    $ColAccent     = [System.Drawing.Color]::FromArgb(59, 130, 246)
    $ColBg         = [System.Drawing.Color]::FromArgb(10,  16,  30)
    $ColCard       = [System.Drawing.Color]::FromArgb(22,  32,  50)
    $ColBorder     = [System.Drawing.Color]::FromArgb(44,  59,  80)
    $ColText       = [System.Drawing.Color]::FromArgb(220, 228, 240)
    $ColMuted      = [System.Drawing.Color]::FromArgb(110, 128, 155)
    $ColGreen      = [System.Drawing.Color]::FromArgb(34,  197,  94)
    $ColRed        = [System.Drawing.Color]::FromArgb(239,  68,  68)
    $ColYellow     = [System.Drawing.Color]::FromArgb(234, 179,   8)
    $ColLogBg      = [System.Drawing.Color]::FromArgb(6,   10,  20)
    $ColBadgeOkBg  = [System.Drawing.Color]::FromArgb(15,  58,  35)
    $ColBadgeErrBg = [System.Drawing.Color]::FromArgb(90,  18,  18)
    $ColBadgeRunBg = [System.Drawing.Color]::FromArgb(80,  48,   8)
    $ColLogPass    = [System.Drawing.Color]::FromArgb(74,  222, 128)
    $ColLogFail    = [System.Drawing.Color]::FromArgb(252, 165, 165)
    $ColLogWarn    = [System.Drawing.Color]::FromArgb(253, 224,  71)
    $ColLogCyan    = [System.Drawing.Color]::FromArgb(103, 232, 249)
    $ColLogText    = [System.Drawing.Color]::FromArgb(203, 213, 225)
    $ColLogLabel   = [System.Drawing.Color]::FromArgb(100, 116, 139)
    $ColFailBg     = [System.Drawing.Color]::FromArgb(62,  28,  28)
    $ColWarnBg     = [System.Drawing.Color]::FromArgb(58,  50,  16)
    $ColOkBg       = [System.Drawing.Color]::FromArgb(15,  50,  28)
}

# ---------- GUI Helper Functions --------------------------------------------
function New-SidebarButton {
    param([string]$Text, [int]$Y, [bool]$Active = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text; $btn.Size = New-Object System.Drawing.Size(205, 44)
    $btn.Location = New-Object System.Drawing.Point(7, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $ColNavHover
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btn.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $btn.Padding = New-Object System.Windows.Forms.Padding(16,0,0,0)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Active) { $btn.BackColor = $ColNavActive; $btn.ForeColor = [System.Drawing.Color]::White }
    else         { $btn.BackColor = $ColSidebar;   $btn.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184) }
    return $btn
}

function New-TabButton {
    param([string]$Label, [int]$IconCode, [int]$X, [int]$W = 160)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Size      = New-Object System.Drawing.Size($W, $TabH)
    $btn.Location  = New-Object System.Drawing.Point($X, 0)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $ColNavHover
    $btn.BackColor = $ColSidebar
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btn.Text      = ""
    $btn.Tag       = [PSCustomObject]@{ Icon = [char]$IconCode; Label = $Label; Active = $false }
    $btn.Add_Paint({
        $s = $args[0]; $e = $args[1]
        $g = $e.Graphics
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
        $t  = $s.Tag
        $fg = if ($t.Active) { [System.Drawing.Color]::White } else { $ColMuted }
        $iBrush = New-Object System.Drawing.SolidBrush($fg)
        $tBrush = New-Object System.Drawing.SolidBrush($fg)
        $iFont  = New-Object System.Drawing.Font("Segoe MDL2 Assets", 15)
        $tFont  = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $iStr   = [string]$t.Icon
        $tStr   = $t.Label
        $iSz    = $g.MeasureString($iStr, $iFont)
        $tSz    = $g.MeasureString($tStr, $tFont)
        $bW     = [int]$s.Width
        $bH     = [int]$s.Height
        $iY     = [int](($bH - [int]$iSz.Height - [int]$tSz.Height - 5) / 2)
        $tY     = $iY + [int]$iSz.Height + 5
        $g.DrawString($iStr, $iFont, $iBrush, [int](($bW - $iSz.Width) / 2), $iY)
        $g.DrawString($tStr, $tFont, $tBrush, [int](($bW - $tSz.Width) / 2), $tY)
        if ($t.Active) {
            $acPen = New-Object System.Drawing.Pen($ColAccent, 2)
            $g.DrawLine($acPen, 8, ([int]$s.Height - 1), ($bW - 8), ([int]$s.Height - 1))
            $acPen.Dispose()
        }
        $iFont.Dispose(); $tFont.Dispose(); $iBrush.Dispose(); $tBrush.Dispose()
    })
    return $btn
}

function New-StatusCard {
    param([string]$Title, [int]$X, [int]$Y, [string]$Icon = "", [string]$Sub = "", [int]$CardW=178, [int]$CardH=78)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($CardW, $CardH); $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.BackColor = $ColCard; $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $panel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $CardW, $CardH)), 8))
    $panel.Tag = $Icon
    $panel.Add_Paint({
        $g = $args[1].Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
        $pW = [int]$this.Width; $pH = [int]$this.Height
        if ($this.Tag) {
            $iFont  = New-Object System.Drawing.Font("Segoe MDL2 Assets", 26)
            $iBrush = New-Object System.Drawing.SolidBrush($ColBorder)
            $iStr   = [string]$this.Tag
            $iSz    = $g.MeasureString($iStr, $iFont)
            $ix     = $pW - [int]$iSz.Width  - 10
            $iy     = $pH - [int]$iSz.Height - 6
            $g.DrawString($iStr, $iFont, $iBrush, $ix, $iy)
            $iFont.Dispose(); $iBrush.Dispose()
        }
        $rr = New-Object System.Drawing.Rectangle(0, 0, ($pW - 1), ($pH - 1))
        $bp = [GfxHelper]::RoundedRect($rr, 8)
        $pen = New-Object System.Drawing.Pen($ColBorder, 1)
        $g.DrawPath($pen, $bp)
        $pen.Dispose(); $bp.Dispose()
    })

    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = $Title
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lbl.ForeColor = $ColMuted
    $lbl.Location = New-Object System.Drawing.Point(10, 10); $lbl.AutoSize = $true
    $panel.Controls.Add($lbl)

    $val = New-Object System.Windows.Forms.Label; $val.Text = "--"
    $val.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
    $val.ForeColor = $ColText; $val.Location = New-Object System.Drawing.Point(10, 26)
    $val.Size = New-Object System.Drawing.Size(([int]$CardW - 20), 28); $val.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($val)

    $subLbl = New-Object System.Windows.Forms.Label; $subLbl.Text = $Sub
    $subLbl.Font = New-Object System.Drawing.Font("Segoe UI", 7); $subLbl.ForeColor = $ColMuted
    $subLbl.Location = New-Object System.Drawing.Point(10, 57); $subLbl.Size = New-Object System.Drawing.Size(([int]$CardW - 20), 14)
    $subLbl.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($subLbl)

    $dot = New-Object System.Windows.Forms.Panel; $dot.Size = New-Object System.Drawing.Size(10, 10)
    $dot.Location = New-Object System.Drawing.Point(([int]$CardW - 18), 10); $dot.BackColor = $ColMuted
    $dot.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 10, 10)), 5))
    $panel.Controls.Add($dot)

    return @{ Panel=$panel; ValueLabel=$val; DotPanel=$dot; SubLabel=$subLbl }
}

function Update-CardStatus {
    param($Card, [string]$Value, [string]$Status)
    $Card.ValueLabel.Text = $Value
    $fSize = 13
    try {
        $g = $Card.Panel.CreateGraphics()
        while ($fSize -gt 8) {
            $f = New-Object System.Drawing.Font("Segoe UI Semibold", $fSize)
            $tw = $g.MeasureString($Value, $f).Width
            $f.Dispose()
            if ($tw -le ($Card.ValueLabel.Width - 4)) { break }
            $fSize--
        }
        $g.Dispose()
    } catch { $fSize = if ($Value.Length -gt 9) { 10 } else { 13 } }
    $Card.ValueLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", $fSize)
    $dotC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColMuted} }
    $valC = switch ($Status) { "ok" {$ColGreen} "fail" {$ColRed} "warn" {$ColYellow} default {$ColText}  }
    $Card.DotPanel.BackColor   = $dotC
    $Card.ValueLabel.ForeColor = $valC
}


function New-StubPanel {
    param([string]$Title, [string]$SubText = "")
    $p = New-Object System.Windows.Forms.Panel
    $p.Size     = New-Object System.Drawing.Size($ContentW, $ContentH)
    $p.Location = New-Object System.Drawing.Point(0, $ContentY)
    $p.BackColor = $ColBg; $p.Visible = $false; $p.Anchor = $AnchorTLRB
    $form.Controls.Add($p)
    $lTitle = New-Object System.Windows.Forms.Label
    $lTitle.Text = $Title; $lTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
    $lTitle.ForeColor = $ColText; $lTitle.Location = New-Object System.Drawing.Point(10, 16); $lTitle.AutoSize = $true
    $p.Controls.Add($lTitle)
    if ($SubText) {
        $lSub = New-Object System.Windows.Forms.Label; $lSub.Text = $SubText
        $lSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lSub.ForeColor = $ColMuted
        $lSub.Location = New-Object System.Drawing.Point(10, 42); $lSub.Size = New-Object System.Drawing.Size(1240, 18)
        $p.Controls.Add($lSub)
    }
    return $p
}

function Set-ActiveNav {
    param($Active)
    # Includes the v1.0.42-redesigned sidebar nav (Settings + About are now visible
    # nav items rather than hidden compat buttons).
    $tabNavs = @($navSysOverview,$navNetConfig,$navCamera,$navPoE,$navServices,$navDisk,$navEvents,$navReports,$navSysInfo,$navSettings,$navAbout)
    foreach ($nb in $tabNavs) {
        if (-not $nb) { continue }
        # New sidebar buttons paint their own background; reset to base sidebar color.
        $nb.BackColor = $ColSidebar
        if ($nb.Tag -ne $null -and $nb.Tag.PSObject.Properties['Active']) { $nb.Tag.Active = $false }
        $nb.Invalidate()
    }
    if ($Active -and $tabNavs -contains $Active) {
        # Subtle background tint on the active row, plus the in-Paint accent strip.
        $Active.BackColor = [System.Drawing.Color]::FromArgb(28, 42, 62)
        if ($Active.Tag -ne $null -and $Active.Tag.PSObject.Properties['Active']) { $Active.Tag.Active = $true }
        $Active.Invalidate()
    }
}

# ---------- v1.0.42 redesign helpers ---------------------------------------
# Each redesigned panel uses these for consistent header / summary / action-bar
# patterns. Existing panels can be migrated incrementally.

# New-SectionHeader: title + subtitle on the left, "Overall Status" pill on the right.
# Returns a hashtable of references so callers can update the pill state later
# (PillBg, PillIcon, PillTitle, PillSub).
function New-SectionHeader {
    param(
        [System.Windows.Forms.Panel]$Parent,
        [string]$Title,
        [string]$Subtitle,
        [int]$Y = 24
    )
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = $Title
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
    $lblTitle.ForeColor = $ColText
    $lblTitle.Location  = New-Object System.Drawing.Point(28, $Y)
    $lblTitle.Size      = New-Object System.Drawing.Size(900, 30)
    $Parent.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Text      = $Subtitle
    $lblSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblSub.ForeColor = $ColMuted
    $lblSub.Location  = New-Object System.Drawing.Point(28, ($Y + 32))
    $lblSub.Size      = New-Object System.Drawing.Size(900, 20)
    $Parent.Controls.Add($lblSub)

    # "Overall Status" pill on the right — neutral by default; caller updates via Set-SectionPill.
    $pill = New-Object System.Windows.Forms.Panel
    $pill.Size      = New-Object System.Drawing.Size(220, 60)
    $pill.Location  = New-Object System.Drawing.Point(($Parent.Width - 248), $Y)
    $pill.BackColor = $ColCard
    $pill.Anchor    = $AnchorTR
    $pill.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 220, 60)), 8))
    $Parent.Controls.Add($pill)

    $lblPillLabel = New-Object System.Windows.Forms.Label
    $lblPillLabel.Text      = "Overall Status"
    $lblPillLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblPillLabel.ForeColor = $ColMuted
    $lblPillLabel.Location  = New-Object System.Drawing.Point(16, 8)
    $lblPillLabel.Size      = New-Object System.Drawing.Size(140, 16)
    $pill.Controls.Add($lblPillLabel)

    $lblPillIcon = New-Object System.Windows.Forms.Label
    $lblPillIcon.Text      = [char]0xE9D5   # info circle (neutral)
    $lblPillIcon.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 13)
    $lblPillIcon.ForeColor = $ColMuted
    $lblPillIcon.Location  = New-Object System.Drawing.Point(16, 28)
    $lblPillIcon.Size      = New-Object System.Drawing.Size(20, 22)
    $pill.Controls.Add($lblPillIcon)

    $lblPillTitle = New-Object System.Windows.Forms.Label
    $lblPillTitle.Text      = "Pending"
    $lblPillTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $lblPillTitle.ForeColor = $ColMuted
    $lblPillTitle.Location  = New-Object System.Drawing.Point(40, 28)
    $lblPillTitle.Size      = New-Object System.Drawing.Size(170, 22)
    $pill.Controls.Add($lblPillTitle)

    return @{
        Title    = $lblTitle
        Subtitle = $lblSub
        Pill     = $pill
        PillIcon = $lblPillIcon
        PillTitle= $lblPillTitle
    }
}

# Update the section header's status pill. Status is one of: ok, warn, fail, neutral.
function Set-SectionPill {
    param([hashtable]$Header, [string]$Status, [string]$Title = $null)
    if (-not $Header) { return }
    $iconChar = switch ($Status) { "ok"{[char]0xE73E} "warn"{[char]0xE7BA} "fail"{[char]0xEA39} default{[char]0xE9D5} }
    $color    = switch ($Status) { "ok"{$ColGreen}    "warn"{$ColYellow}  "fail"{$ColRed}    default{$ColMuted} }
    $defaultTitle = switch ($Status) { "ok"{"Healthy"} "warn"{"Warning"} "fail"{"Critical"} default{"Pending"} }
    $Header.PillIcon.Text      = $iconChar
    $Header.PillIcon.ForeColor = $color
    $Header.PillTitle.Text     = if ($Title) { $Title } else { $defaultTitle }
    $Header.PillTitle.ForeColor= $color
}

# New-SummaryPanel: bordered card with "Summary" header and a vertically stacked
# checklist of bullet rows. Caller passes in items as @(@{Status="ok";Text="..."}, ...).
# Returns a hashtable with the panel + an Update method via Set-SummaryItems.
function New-SummaryPanel {
    param(
        [System.Windows.Forms.Panel]$Parent,
        [int]$X, [int]$Y, [int]$W, [int]$H,
        [string]$Title = "Summary"
    )
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
    $lblTitle.Location  = New-Object System.Drawing.Point(16, 14)
    $lblTitle.Size      = New-Object System.Drawing.Size(($W - 32), 20)
    $card.Controls.Add($lblTitle)

    $itemsHost = New-Object System.Windows.Forms.Panel
    $itemsHost.Location  = New-Object System.Drawing.Point(8, 40)
    $itemsHost.Size      = New-Object System.Drawing.Size(($W - 16), ($H - 48))
    $itemsHost.BackColor = $ColCard
    $card.Controls.Add($itemsHost)

    return @{ Card = $card; ItemsHost = $itemsHost }
}

# Populate a summary panel with check-bullet rows.
function Set-SummaryItems {
    param([hashtable]$Summary, [array]$Items)
    if (-not $Summary -or -not $Summary.ItemsHost) { return }
    # PowerShell reserves $host for the session-host object. Using it locally
    # triggers "Cannot overwrite variable Host because it is read-only".
    $itemHost = $Summary.ItemsHost
    $itemHost.Controls.Clear()
    $rowY = 0
    foreach ($it in $Items) {
        $st = if ($it.Status) { $it.Status } else { "ok" }
        $iconChar = switch ($st) { "ok"{[char]0xE73E} "warn"{[char]0xE7BA} "fail"{[char]0xEA39} default{[char]0xE9D5} }
        $color    = switch ($st) { "ok"{$ColGreen}    "warn"{$ColYellow}  "fail"{$ColRed}    default{$ColMuted} }

        $lblIcn = New-Object System.Windows.Forms.Label
        $lblIcn.Text      = $iconChar
        $lblIcn.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 9)
        $lblIcn.ForeColor = $color
        $lblIcn.Location  = New-Object System.Drawing.Point(8, ($rowY + 2))
        $lblIcn.Size      = New-Object System.Drawing.Size(18, 18)
        $itemHost.Controls.Add($lblIcn)

        $lblTxt = New-Object System.Windows.Forms.Label
        $lblTxt.Text      = $it.Text
        $lblTxt.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $lblTxt.ForeColor = $ColText
        $lblTxt.Location  = New-Object System.Drawing.Point(28, $rowY)
        $lblTxt.Size      = New-Object System.Drawing.Size(($itemHost.Width - 32), 22)
        $itemHost.Controls.Add($lblTxt)

        $rowY += 22
    }
}

# New-ActionBar: bottom-aligned row with Export (left, secondary) + primary action (right).
# Returns the export & primary buttons so callers can wire Click handlers.
function New-ActionBar {
    param(
        [System.Windows.Forms.Panel]$Parent,
        [int]$Y,
        [string]$ExportText  = "Export Report",
        [string]$PrimaryText = "Run Full Diagnostic"
    )
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size      = New-Object System.Drawing.Size(($Parent.Width - 56), 56)
    $bar.Location  = New-Object System.Drawing.Point(28, $Y)
    $bar.BackColor = $ColBg
    $bar.Anchor    = $AnchorBLR
    $Parent.Controls.Add($bar)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text      = $ExportText
    $btnExport.Size      = New-Object System.Drawing.Size(160, 36)
    $btnExport.Location  = New-Object System.Drawing.Point(0, 10)
    $btnExport.BackColor = $ColCard
    $btnExport.ForeColor = $ColText
    $btnExport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnExport.FlatAppearance.BorderColor = $ColBorder
    $btnExport.FlatAppearance.BorderSize  = 1
    $btnExport.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $btnExport.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnExport.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 160, 36)), 6))
    $bar.Controls.Add($btnExport)

    $btnPrimary = New-Object System.Windows.Forms.Button
    $btnPrimary.Text      = $PrimaryText
    $btnPrimary.Size      = New-Object System.Drawing.Size(200, 36)
    $btnPrimary.Location  = New-Object System.Drawing.Point(($bar.Width - 200), 10)
    $btnPrimary.BackColor = $ColAccent
    $btnPrimary.ForeColor = [System.Drawing.Color]::White
    $btnPrimary.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnPrimary.FlatAppearance.BorderSize = 0
    $btnPrimary.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $btnPrimary.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btnPrimary.Anchor    = $AnchorTR
    $btnPrimary.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 200, 36)), 6))
    $bar.Controls.Add($btnPrimary)

    return @{ Bar = $bar; ExportBtn = $btnExport; PrimaryBtn = $btnPrimary }
}

function Show-Panel {
    param($Panel, [bool]$ShowRight = $false)
    if ($script:allNavPanels) {
        foreach ($p in $script:allNavPanels) { if ($p -is [System.Windows.Forms.Control]) { $p.Visible = $false } }
    }
    $Panel.Visible = $true
    # Defensive: ensure the target panel is on top of any other Z-order siblings.
    # Without this, late-added overlays (e.g. toast, tab bar) can mask a panel that
    # was added earlier — manifests as "Settings button does nothing" (#56).
    try { $Panel.BringToFront() } catch { }
    if ($right)       { $right.Visible       = $ShowRight }
    if ($rightBorder) { $rightBorder.Visible = $ShowRight }
}

function New-LogGrid {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [int]$LabelColW = 200)
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Size     = New-Object System.Drawing.Size($W, $H)
    $dgv.Location = New-Object System.Drawing.Point($X, $Y)
    $dgv.Anchor   = $AnchorTLRB
    $dgv.BackgroundColor = $ColLogBg
    $dgv.GridColor       = $ColLogBg
    $dgv.BorderStyle     = [System.Windows.Forms.BorderStyle]::None
    $dgv.RowHeadersVisible   = $false
    $dgv.ColumnHeadersVisible = $false
    $dgv.ReadOnly             = $true
    $dgv.AllowUserToAddRows   = $false
    $dgv.AllowUserToResizeRows = $false
    $dgv.RowTemplate.Height   = 20
    $dgv.SelectionMode  = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $dgv.MultiSelect    = $false
    $dgv.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::None
    $dgv.DefaultCellStyle.BackColor         = $ColLogBg
    $dgv.DefaultCellStyle.ForeColor         = $ColLogText
    $dgv.DefaultCellStyle.Font              = New-Object System.Drawing.Font("Consolas", 8)
    $dgv.DefaultCellStyle.SelectionBackColor = $ColNavHover
    $dgv.DefaultCellStyle.SelectionForeColor = $ColLogText
    $dgv.DefaultCellStyle.Padding           = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $c0 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c0.Name = "Label"; $c0.Width = $LabelColW; $c0.MinimumWidth = $LabelColW
    $c0.Resizable = [System.Windows.Forms.DataGridViewTriState]::False
    $c0.DefaultCellStyle.ForeColor = $ColLogLabel
    $dgv.Columns.Add($c0) | Out-Null
    $c1 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c1.Name = "Result"; $c1.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $dgv.Columns.Add($c1) | Out-Null
    return $dgv
}

function Add-LogRow {
    param($Grid, [string]$Label, [string]$Result, [string]$Level)
    if ($Level -eq "Section") {
        $i = $Grid.Rows.Add("", "  $($Result.ToUpper())")
        $r = $Grid.Rows[$i]
        $r.DefaultCellStyle.BackColor         = $ColLogBg
        $r.DefaultCellStyle.ForeColor         = $ColMuted
        $r.DefaultCellStyle.Font              = New-Object System.Drawing.Font("Consolas", 7.5, [System.Drawing.FontStyle]::Bold)
        $r.DefaultCellStyle.SelectionBackColor = $ColLogBg
        $r.DefaultCellStyle.SelectionForeColor = $ColMuted
    } else {
        $i = $Grid.Rows.Add($Label, $Result)
        $r = $Grid.Rows[$i]
        $col = switch ($Level) {
            "Pass" { $ColLogPass  }
            "Fail" { $ColLogFail  }
            "Warn" { $ColLogWarn  }
            "Cyan" { $ColLogCyan  }
            "Gray" { $ColMuted    }
            default{ $ColLogText  }
        }
        $r.Cells[1].Style.ForeColor = $col
    }
    try { $Grid.FirstDisplayedScrollingRowIndex = $Grid.Rows.Count - 1 } catch { }
}
