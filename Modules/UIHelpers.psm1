# =============================================================================
#  UIHelpers.psm1  —  WinForms bootstrap, colors, shared GUI helpers
#  Dot-sourced first by Start-VPUDiagnostic.ps1 before anything else.
# =============================================================================

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

# ---------- Color palette ----------------------------------------------------
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

# ---------- Nav button -------------------------------------------------------
function New-NavButton {
    param([string]$Text, [int]$Y, [bool]$Active = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Size      = New-Object System.Drawing.Size(210, 40)
    $btn.Location  = New-Object System.Drawing.Point(5, $Y)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = $ColNavHover
    $btn.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btn.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $btn.Padding   = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $btn.Text      = $Text
    if ($Active) { $btn.BackColor = $ColNavActive; $btn.ForeColor = [System.Drawing.Color]::White }
    else         { $btn.BackColor = $ColSidebar;   $btn.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184) }
    return $btn
}
function New-SidebarButton { param([string]$Text,[int]$Y,[bool]$Active=$false); return New-NavButton $Text $Y $Active }

# ---------- Status card (NIC port / diagnostic summary card) -----------------
function New-StatusCard {
    param([string]$Title, [string]$Sub = "", [int]$X, [int]$Y,
          [char]$Icon = [char]0xE7BA, [int]$CardW = 180, [int]$CardH = 90)
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Size      = New-Object System.Drawing.Size($CardW, $CardH)
    $pnl.Location  = New-Object System.Drawing.Point($X, $Y)
    $pnl.BackColor = [System.Drawing.Color]::White
    $pnl.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $CardW, $CardH)), 8))
    $pnl.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $bp  = [GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $s.Width - 1, $s.Height - 1)), 8)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(226, 232, 240), 1)
        $e.Graphics.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
    })

    $dot = New-Object System.Windows.Forms.Panel
    $dot.Size      = New-Object System.Drawing.Size(8, 8)
    $dot.Location  = New-Object System.Drawing.Point(12, 12)
    $dot.BackColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $dot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
    $pnl.Controls.Add($dot)

    $iLbl = New-Object System.Windows.Forms.Label
    $iLbl.Text      = [string]$Icon
    $iLbl.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 10)
    $iLbl.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $iLbl.Location  = New-Object System.Drawing.Point(26, 8)
    $iLbl.Size      = New-Object System.Drawing.Size(22, 22)
    $iLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($iLbl)

    $tLbl = New-Object System.Windows.Forms.Label
    $tLbl.Text      = $Title
    $tLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 8)
    $tLbl.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $tLbl.Location  = New-Object System.Drawing.Point(12, 28)
    $tLbl.Size      = New-Object System.Drawing.Size($CardW - 16, 16)
    $tLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($tLbl)

    $vLbl = New-Object System.Windows.Forms.Label
    $vLbl.Text      = "--"
    $vLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
    $vLbl.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $vLbl.Location  = New-Object System.Drawing.Point(12, 44)
    $vLbl.Size      = New-Object System.Drawing.Size($CardW - 16, 28)
    $vLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($vLbl)

    if ($Sub) {
        $sLbl = New-Object System.Windows.Forms.Label
        $sLbl.Text      = $Sub
        $sLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 7)
        $sLbl.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
        $sLbl.Location  = New-Object System.Drawing.Point(12, 72)
        $sLbl.Size      = New-Object System.Drawing.Size($CardW - 16, 14)
        $sLbl.BackColor = [System.Drawing.Color]::Transparent
        $pnl.Controls.Add($sLbl)
    }

    return @{ Panel = $pnl; DotPanel = $dot; ValueLabel = $vLbl }
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

# ---------- Generic stub panel -----------------------------------------------
function New-StubPanel {
    param([string]$Title, [string]$Sub)
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
    $pnl.Location  = New-Object System.Drawing.Point($SideW, $HdrH)
    $pnl.BackColor = $ColBg
    $pnl.Anchor    = $AnchorTLRB
    $pnl.Visible   = $false
    $form.Controls.Add($pnl)

    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text = $Title; $lblT.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
    $lblT.ForeColor = $ColText; $lblT.Location = New-Object System.Drawing.Point(10, 16); $lblT.AutoSize = $true
    $pnl.Controls.Add($lblT)

    $lblS = New-Object System.Windows.Forms.Label
    $lblS.Text = $Sub; $lblS.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblS.ForeColor = $ColMuted
    $lblS.Location = New-Object System.Drawing.Point(10, 42); $lblS.Size = New-Object System.Drawing.Size(800, 18)
    $pnl.Controls.Add($lblS)

    $sep = New-Object System.Windows.Forms.Panel
    $sep.Size = New-Object System.Drawing.Size($WideW - 20, 1); $sep.Location = New-Object System.Drawing.Point(10, 66)
    $sep.BackColor = $ColBorder; $pnl.Controls.Add($sep)

    $lblPh = New-Object System.Windows.Forms.Label
    $lblPh.Text = "This section is under development."; $lblPh.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblPh.ForeColor = $ColMuted; $lblPh.Location = New-Object System.Drawing.Point(10, 86); $lblPh.AutoSize = $true
    $pnl.Controls.Add($lblPh)

    $btnRFD = New-Object System.Windows.Forms.Button
    $btnRFD.Text = [char]0x25B6 + "  Run Full Diagnostic"
    $btnRFD.Size = New-Object System.Drawing.Size(230, 38); $btnRFD.Location = New-Object System.Drawing.Point(10, $ContentH - 56)
    $btnRFD.BackColor = $ColAccent; $btnRFD.ForeColor = [System.Drawing.Color]::White
    $btnRFD.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnRFD.FlatAppearance.BorderSize = 0
    $btnRFD.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $btnRFD.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $btnRFD.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnRFD.Anchor = $AnchorBLR
    $btnRFD.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,230,38)),6))
    $btnRFD.Add_Click({ $navCamera.PerformClick(); $btnRun.PerformClick() })
    $pnl.Controls.Add($btnRFD)

    $btnExp = New-Object System.Windows.Forms.Button
    $btnExp.Text = "Export Section"
    $btnExp.Size = New-Object System.Drawing.Size(160, 38); $btnExp.Location = New-Object System.Drawing.Point(250, $ContentH - 56)
    $btnExp.BackColor = [System.Drawing.Color]::FromArgb(226,232,240); $btnExp.ForeColor = $ColText
    $btnExp.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnExp.FlatAppearance.BorderSize = 0
    $btnExp.Font = New-Object System.Drawing.Font("Segoe UI", 9.5); $btnExp.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnExp.Anchor = $AnchorBLR
    $btnExp.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,160,38)),6))
    $pnl.Controls.Add($btnExp)

    return $pnl
}
