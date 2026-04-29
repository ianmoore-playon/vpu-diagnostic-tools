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

function New-StatusCard {
    param([string]$Title, [int]$X, [int]$Y, [string]$Icon = "", [string]$Sub = "", [int]$CardW=178, [int]$CardH=78)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Size = New-Object System.Drawing.Size($CardW, $CardH); $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.BackColor = $ColCard; $panel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $panel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $CardW, $CardH)), 8))
    $panel.Add_Paint(({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $e.Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
        if ($Icon) {
            $iFont  = New-Object System.Drawing.Font("Segoe MDL2 Assets", 26)
            $iBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 210, 222))
            $iStr   = [string]$Icon
            $iSz    = $e.Graphics.MeasureString($iStr, $iFont)
            $ix     = $CardW - [int]$iSz.Width  - 10
            $iy     = $CardH - [int]$iSz.Height - 6
            $e.Graphics.DrawString($iStr, $iFont, $iBrush, $ix, $iy)
            $iFont.Dispose(); $iBrush.Dispose()
        }
        $rr = New-Object System.Drawing.Rectangle(0, 0, $CardW - 1, $CardH - 1)
        $bp = [GfxHelper]::RoundedRect($rr, 8)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 218, 228), 1)
        $e.Graphics.DrawPath($pen, $bp)
        $pen.Dispose(); $bp.Dispose()
    }).GetNewClosure())

    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = $Title
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 7.5); $lbl.ForeColor = $ColMuted
    $lbl.Location = New-Object System.Drawing.Point(10, 10); $lbl.AutoSize = $true
    $panel.Controls.Add($lbl)

    $val = New-Object System.Windows.Forms.Label; $val.Text = "--"
    $val.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
    $val.ForeColor = $ColText; $val.Location = New-Object System.Drawing.Point(10, 26)
    $val.Size = New-Object System.Drawing.Size($CardW - 20, 28); $val.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($val)

    $subLbl = New-Object System.Windows.Forms.Label; $subLbl.Text = $Sub
    $subLbl.Font = New-Object System.Drawing.Font("Segoe UI", 7); $subLbl.ForeColor = $ColMuted
    $subLbl.Location = New-Object System.Drawing.Point(10, 57); $subLbl.Size = New-Object System.Drawing.Size($CardW - 20, 14)
    $subLbl.BackColor = [System.Drawing.Color]::Transparent
    $panel.Controls.Add($subLbl)

    $dot = New-Object System.Windows.Forms.Panel; $dot.Size = New-Object System.Drawing.Size(10, 10)
    $dot.Location = New-Object System.Drawing.Point($CardW - 18, 10); $dot.BackColor = $ColMuted
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
    $p.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
    $p.Location = New-Object System.Drawing.Point($SideW, $HdrH)
    $p.BackColor = $ColBg; $p.Visible = $false; $p.Anchor = $AnchorTLRB
    $form.Controls.Add($p)
    $lTitle = New-Object System.Windows.Forms.Label
    $lTitle.Text = $Title; $lTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
    $lTitle.ForeColor = $ColText; $lTitle.Location = New-Object System.Drawing.Point(10, 16); $lTitle.AutoSize = $true
    $p.Controls.Add($lTitle)
    if ($SubText) {
        $lSub = New-Object System.Windows.Forms.Label; $lSub.Text = $SubText
        $lSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lSub.ForeColor = $ColMuted
        $lSub.Location = New-Object System.Drawing.Point(10, 42); $lSub.Size = New-Object System.Drawing.Size(762, 18)
        $p.Controls.Add($lSub)
    }
    return $p
}

function Set-ActiveNav {
    param($Active)
    $visibleNavs = @($navSysOverview,$navNetConfig,$navCamera,$navPoE,$navServices,$navDisk,$navEvents,$navReports,$navSettings,$navAbout)
    foreach ($nb in $visibleNavs) {
        $nb.BackColor = $ColSidebar; $nb.ForeColor = [System.Drawing.Color]::FromArgb(148,163,184)
    }
    if ($Active -and $visibleNavs -contains $Active) {
        $Active.BackColor = $ColNavActive; $Active.ForeColor = [System.Drawing.Color]::White
    }
}

function Show-Panel {
    param($Panel, [bool]$ShowRight = $false)
    if ($script:allNavPanels) {
        foreach ($p in $script:allNavPanels) { $p.Visible = $false }
    }
    $Panel.Visible   = $true
    $right.Visible        = $ShowRight
    $rightBorder.Visible  = $ShowRight
}
