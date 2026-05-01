# =============================================================================
#  Pulse.ps1  -  Pulse - Pixellot Unified Live System Evaluator
#  Loads modules from .\Modules\ and runs the GUI.
#
#  HOW TO RUN: double-click "Pulse.bat"  (handles elevation automatically)
# =============================================================================

$ScriptVersion = "1.0.28"

# Load feedback token from DPAPI-encrypted file (set once per machine via Set-FeedbackToken.ps1)
$script:FeedbackToken = ""
try {
    $keyPath = "C:\ProgramData\Pulse\feedback.key"
    if (Test-Path $keyPath) {
        Add-Type -AssemblyName System.Security
        $enc   = [System.IO.File]::ReadAllBytes($keyPath)
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $enc, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        $script:FeedbackToken = [System.Text.Encoding]::UTF8.GetString($bytes)
        [System.Array]::Clear($bytes, 0, $bytes.Length)
    }
} catch { $script:FeedbackToken = "" }

# ---------- Self-elevation ---------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevArgs = "-NoProfile -ExecutionPolicy Bypass"
    if ($PSCommandPath) {
        Start-Process PowerShell -Verb RunAs -ArgumentList "$elevArgs -File `"$PSCommandPath`""
    }
    exit
}

# ---------- Configuration ----------------------------------------------------
$OutputBaseDir     = if ($PSScriptRoot) { $PSScriptRoot } else { [Environment]::GetFolderPath('Desktop') }
$OutputDir         = Join-Path $OutputBaseDir "Pulse_Results"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$LogDir  = Join-Path $OutputDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
try { Start-Transcript -Path (Join-Path $LogDir "session_$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -ErrorAction SilentlyContinue } catch { }
$NicDriverPatterns = @("Intel(R) 82574L*", "Intel(R) I210*", "Intel(R) I211*", "Intel(R) I350*", "Intel(R) I354*")

function Get-AdlinkCardInfo {
    param($nics)
    $desc = if ($nics.Count -gt 0) { $nics[0].InterfaceDescription } else { "" }
    $count = $nics.Count
    if     ($desc -like "*82574L*") { @{ Label = "ADLINK GIE64  (Intel 82574L x$count)";     PoeMgmtSupported = $false } }
    elseif ($desc -like "*I210*")   { @{ Label = "ADLINK GIE74P  (Intel I210 x$count)";       PoeMgmtSupported = $true  } }
    elseif ($desc -like "*I211*")   { @{ Label = "ADLINK GIE74P  (Intel I211 x$count)";       PoeMgmtSupported = $true  } }
    elseif ($desc -like "*I350*")   { @{ Label = "ADLINK GIE74P-AN  (Intel I350 x$count)";    PoeMgmtSupported = $false } }
    elseif ($desc -like "*I354*")   { @{ Label = "ADLINK GIE74P-AN  (Intel I354 x$count)";    PoeMgmtSupported = $false } }
    elseif ($count -gt 0)           { @{ Label = "Unknown NIC  ($desc)";                       PoeMgmtSupported = $false } }
    else                            { @{ Label = "No NIC detected";                            PoeMgmtSupported = $false } }
}
$RenegotiateWaitSec = 30
$EventLogHours      = 48
$PixellotLogPaths   = @(
    "C:\Pixellot\Data\Log"
    "C:\Pixellot\logs"
    "C:\Pixellot\Logs"
    "C:\Program Files\Pixellot\logs"
    "C:\ProgramData\Pixellot\logs"
)
$RtspPort  = 554
$OcrMacOui = "00-D0-89"

# ---------- ADLINK SmartPoE DLL search ---------------------------------------
$PoeDllPath = $null
foreach ($c in @(
    "C:\Program Files\ADLINK\GIE Series\Library\Dll\x64\SmartPoE.dll"
    "$env:SystemRoot\System32\SmartPoE.dll"
    "C:\Program Files\ADLINK\SmartPoE\SmartPoE.dll"
    "C:\Program Files (x86)\ADLINK\SmartPoE\SmartPoE.dll"
    "C:\Program Files\ADLINK\PCIe-GIE7x\SmartPoE.dll"
    "C:\ADLINK\SmartPoE\SmartPoE.dll"
)) { if (Test-Path $c) { $PoeDllPath = $c; break } }
if (-not $PoeDllPath) {
    foreach ($reg in @("HKLM:\SOFTWARE\ADLINK\SmartPoE","HKLM:\SOFTWARE\WOW6432Node\ADLINK\SmartPoE","HKLM:\SOFTWARE\ADLINK\GigE Tool")) {
        try { $k = Get-ItemPropertyValue $reg "InstallDir" -ErrorAction Stop; $c = Join-Path $k "SmartPoE.dll"; if (Test-Path $c) { $PoeDllPath = $c; break } } catch { }
    }
}
if (-not $PoeDllPath) {
    foreach ($root in @("C:\Program Files\ADLINK","C:\Program Files (x86)\ADLINK","C:\ADLINK")) {
        if (Test-Path $root) {
            $found = Get-ChildItem $root -Recurse -Filter "SmartPoE.dll" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "*x86*" } | Select-Object -First 1
            if ($found) { $PoeDllPath = $found.FullName; break }
        }
    }
}

# ---------- Theme settings ---------------------------------------------------
$SettingsPath = Join-Path $PSScriptRoot "settings.json"
$VpuTheme = "dark"
if (Test-Path $SettingsPath) {
    try { $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json; if ($s.Theme -eq "light") { $VpuTheme = "light" } } catch { }
}

# ---------- Load modules (dot-sourced into this scope) -----------------------
$ModulesDir = Join-Path $PSScriptRoot "Modules"
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
    $tabNavs = @($navSysOverview,$navNetConfig,$navCamera,$navPoE,$navServices,$navDisk,$navEvents,$navReports,$navSysInfo)
    foreach ($nb in $tabNavs) {
        $nb.BackColor = $ColSidebar
        if ($nb.Tag -ne $null) { $nb.Tag.Active = $false }
        $nb.Invalidate()
    }
    if ($Active -and $tabNavs -contains $Active) {
        $Active.BackColor = $ColNavActive
        $Active.Tag.Active = $true
        $Active.Invalidate()
    }
}

function Show-Panel {
    param($Panel, [bool]$ShowRight = $false)
    if ($script:allNavPanels) {
        foreach ($p in $script:allNavPanels) { if ($p -is [System.Windows.Forms.Control]) { $p.Visible = $false } }
    }
    $Panel.Visible   = $true
    $right.Visible        = $ShowRight
    $rightBorder.Visible  = $ShowRight
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

# ---------- Shared state (runspace <-> UI timer) ----------------------------
# ---------- Shared state (runspace <-> UI timer) ----------------------------
$sync = [hashtable]::Synchronized(@{
    SummaryQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    Running    = $false
    Complete   = $false
    Cancelled  = $false
    AllClear   = $false
    VpuModel   = ""
    OutputFile = ""
    RunId      = ""
    TotalDowngrades = 0
    LastRunLine     = ""
    CurrentStep     = "Ready"
    StepsDone   = [hashtable]::Synchronized(@{})
    Cards = @{
        SmartSpeed = @{ Value = "--"; Status = "neutral" }
        PingCHU    = @{ Value = "--"; Status = "neutral" }
        ArpEntry   = @{ Value = "--"; Status = "neutral" }
        ChuDetect  = @{ Value = "--"; Status = "neutral" }
        PoEBudget  = @{ Value = "--"; Status = "neutral" }
        NetInternet = @{ Value = "--"; Status = "neutral" }
        NetPorts    = @{ Value = "--"; Status = "neutral" }
        NetDomains  = @{ Value = "--"; Status = "neutral" }
        SvcStatus       = @{ Value = "--"; Status = "neutral" }
        SvcAgent        = @{ Value = "--"; Status = "neutral" }
        SvcKeepAgentUp  = @{ Value = "--"; Status = "neutral" }
        SvcCoordinator  = @{ Value = "--"; Status = "neutral" }
        SvcLogMeIn      = @{ Value = "--"; Status = "neutral" }
        SvcVpu          = @{ Value = "--"; Status = "neutral" }
        SvcScoreconnect = @{ Value = "--"; Status = "neutral" }
        DiskStatus  = @{ Value = "--"; Status = "neutral" }
        MemStatus   = @{ Value = "--"; Status = "neutral" }
        EvtStatus   = @{ Value = "--"; Status = "neutral" }
        HwGpu       = @{ Value = "--"; Status = "neutral" }
        HwMonitor   = @{ Value = "--"; Status = "neutral" }
        HwMmk       = @{ Value = "--"; Status = "neutral" }
        SysInfo     = @{ Value = "--"; Status = "neutral" }
    }
    PortResults     = [System.Collections.ArrayList]::new()
    CamResults      = [System.Collections.ArrayList]::new()
    AppIssues       = [System.Collections.ArrayList]::new()
    NextSteps       = [System.Collections.ArrayList]::new()
    UpdateAvailable = ""
    AppLogTime      = $null
    PoeBudgetLow    = $false
    PoeAvailable    = $false
    NetRunning      = $false
    NetComplete     = $false
    NetCancelled    = $false
    NetAllClear     = $false
    NetBasicOk      = $false
    NetStep         = "Ready"
    NetQueue        = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    NetPortPass     = 0
    NetPortFail     = 0
    NetPortInfo     = 0
    NetDomainPass   = 0
    NetDomainFail   = 0
    NetDomainInfo   = 0
    NetAdapters     = [System.Collections.ArrayList]::new()
    SvcRunning      = $false
    SvcComplete     = $false
    SvcCancelled    = $false
    SvcStep         = "Ready"
    SvcQueue        = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    DiskRunning     = $false
    DiskComplete    = $false
    DiskCancelled   = $false
    DiskStep        = "Ready"
    DiskQueue       = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    EvtRunning      = $false
    EvtComplete     = $false
    EvtCancelled    = $false
    EvtStep         = "Ready"
    EvtQueue        = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    HwRunning       = $false
    HwComplete      = $false
    HwCancelled     = $false
    HwStep          = "Ready"
    HwQueue         = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    SysInfoRunning   = $false
    SysInfoComplete  = $false
    SysInfoCancelled = $false
    SysInfoStep      = "Ready"
    SysInfoQueue     = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
    PoePortData     = [System.Collections.ArrayList]::new()
    PoeConsumed     = 0.0
    PoeTotal        = 0.0
    PoeTemp         = 0.0
    NicLinkUptimes  = [System.Collections.ArrayList]::new()
})


# ---------- Form + layout ----------------------------------------------------
# ---------- Form ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Pulse - Pixellot Unified Live System Evaluator"
$form.ClientSize = New-Object System.Drawing.Size(1280, 760)
$form.MinimumSize = $form.Size
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $ColBg
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$AssetsDir = Join-Path $PSScriptRoot "Assets"
$icoPath   = Join-Path $AssetsDir "icon.ico"
if (Test-Path $icoPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch { }
} else {
    $iconPngPath = Join-Path $AssetsDir "icon.png"
    if (Test-Path $iconPngPath) {
        try {
            $iconBmp     = New-Object System.Drawing.Bitmap($iconPngPath)
            $iconResized = New-Object System.Drawing.Bitmap(48, 48)
            $iconG       = [System.Drawing.Graphics]::FromImage($iconResized)
            $iconG.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $iconG.DrawImage($iconBmp, 0, 0, 48, 48)
            $iconG.Dispose(); $iconBmp.Dispose()
            $form.Icon = [System.Drawing.Icon]::FromHandle($iconResized.GetHicon())
            $iconResized.Dispose()
        } catch { }
    }
}

$AnchorTLRB = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTLR  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorTLB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTRB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorBLR  = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorBL   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$AnchorTR   = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right

# Layout constants - typed [int] so arithmetic never fails on malformed environments
[int]$HdrH     = 68
[int]$TabH     = 64
[int]$SbarH    = 28
[int]$SideW    = 0                              # no sidebar
[int]$ContentX = 0
[int]$ContentY = $HdrH + $TabH                 # 120
[int]$ContentH = 760 - $HdrH - $TabH - $SbarH  # 612
[int]$ContentW = 1280                           # full-width content area
# Legacy aliases - Phase 2 will rewrite panel modules to use ContentW/ContentH directly
[int]$WideW    = $ContentW
[int]$NarrowW  = $ContentW
[int]$RightX   = $ContentW
[int]$RightW   = 0

# ---- Header ----------------------------------------------------------------
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Size     = New-Object System.Drawing.Size(1280, $HdrH)
$pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
$pnlHeader.BackColor = $ColSidebar
$pnlHeader.Anchor    = $AnchorTLR
$form.Controls.Add($pnlHeader)

$lblHdrIcon = New-Object System.Windows.Forms.Label
$lblHdrIcon.Text      = [char]0xF785
$lblHdrIcon.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 22)
$lblHdrIcon.ForeColor = $ColAccent
$lblHdrIcon.Location  = New-Object System.Drawing.Point(14, 10)
$lblHdrIcon.Size      = New-Object System.Drawing.Size(46, 46)
$pnlHeader.Controls.Add($lblHdrIcon)
$lblHdrTitle = New-Object System.Windows.Forms.Label
$lblHdrTitle.Text      = "Pulse"
$lblHdrTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHdrTitle.ForeColor = [System.Drawing.Color]::White
$lblHdrTitle.Location  = New-Object System.Drawing.Point(64, 10)
$lblHdrTitle.Size      = New-Object System.Drawing.Size(700, 26)
$pnlHeader.Controls.Add($lblHdrTitle)
$lblHdrSub = New-Object System.Windows.Forms.Label
$lblHdrSub.Text      = "Pixellot Unified Live System Evaluator"
$lblHdrSub.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblHdrSub.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblHdrSub.Location  = New-Object System.Drawing.Point(66, 38)
$lblHdrSub.Size      = New-Object System.Drawing.Size(560, 16)
$pnlHeader.Controls.Add($lblHdrSub)

$lblHdrVer = New-Object System.Windows.Forms.Label
$lblHdrVer.Text      = "Version $ScriptVersion"
$lblHdrVer.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblHdrVer.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblHdrVer.Size      = New-Object System.Drawing.Size(160, $SbarH)
$lblHdrVer.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblHdrVer.Anchor    = $AnchorTR

$pnlBadge = New-Object System.Windows.Forms.Panel
$pnlBadge.Size      = New-Object System.Drawing.Size(120, 28)
$pnlBadge.Location  = New-Object System.Drawing.Point(1146, 20)
$pnlBadge.BackColor = $ColBadgeOkBg
$pnlBadge.Anchor    = $AnchorTR
$pnlHeader.Controls.Add($pnlBadge)
$pnlBadge.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 120, 28)), 14))

$pnlBadgeDot = New-Object System.Windows.Forms.Panel
$pnlBadgeDot.Size      = New-Object System.Drawing.Size(8, 8)
$pnlBadgeDot.Location  = New-Object System.Drawing.Point(12, 10)
$pnlBadgeDot.BackColor = $ColGreen
$pnlBadgeDot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
$pnlBadge.Controls.Add($pnlBadgeDot)

$lblBadge = New-Object System.Windows.Forms.Label
$lblBadge.Text      = "Ready"
$lblBadge.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$lblBadge.ForeColor = $ColGreen
$lblBadge.Location  = New-Object System.Drawing.Point(26, 0)
$lblBadge.Size      = New-Object System.Drawing.Size(88, 28)
$lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlBadge.Controls.Add($lblBadge)

$sepHdr = New-Object System.Windows.Forms.Panel
$sepHdr.Size      = New-Object System.Drawing.Size(1280, 1)
$sepHdr.Location  = New-Object System.Drawing.Point(0, ([int]$HdrH - 1))
$sepHdr.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sepHdr.Anchor    = $AnchorTLR
$pnlHeader.Controls.Add($sepHdr)

# ---- Bottom Status Bar -----------------------------------------------------
$pnlStatusBar = New-Object System.Windows.Forms.Panel
$pnlStatusBar.Size      = New-Object System.Drawing.Size(1280, $SbarH)
$pnlStatusBar.Location  = New-Object System.Drawing.Point(0, (760 - [int]$SbarH))
$pnlStatusBar.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$pnlStatusBar.Anchor    = $AnchorBLR
$form.Controls.Add($pnlStatusBar)

$pnlSbarDot = New-Object System.Windows.Forms.Panel
$pnlSbarDot.Size      = New-Object System.Drawing.Size(8, 8)
$pnlSbarDot.Location  = New-Object System.Drawing.Point(14, 10)
$pnlSbarDot.BackColor = $ColGreen
$pnlSbarDot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
$pnlStatusBar.Controls.Add($pnlSbarDot)

$lblSbarStatus = New-Object System.Windows.Forms.Label
$lblSbarStatus.Text      = "Status: Ready"
$lblSbarStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblSbarStatus.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblSbarStatus.Location  = New-Object System.Drawing.Point(28, 0)
$lblSbarStatus.Size      = New-Object System.Drawing.Size(200, $SbarH)
$lblSbarStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlStatusBar.Controls.Add($lblSbarStatus)

$lblSbarLastRun = New-Object System.Windows.Forms.Label
$lblSbarLastRun.Text      = "Last Run: Never"
$lblSbarLastRun.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblSbarLastRun.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblSbarLastRun.Location  = New-Object System.Drawing.Point(300, 0)
$lblSbarLastRun.Size      = New-Object System.Drawing.Size(400, $SbarH)
$lblSbarLastRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlStatusBar.Controls.Add($lblSbarLastRun)

$lblHdrVer.Location = New-Object System.Drawing.Point(1110, 0)
$pnlStatusBar.Controls.Add($lblHdrVer)

$btnSbarSettings = New-Object System.Windows.Forms.Button
$btnSbarSettings.Text      = "Settings"
$btnSbarSettings.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$btnSbarSettings.Size      = New-Object System.Drawing.Size(90, 20)
$btnSbarSettings.Location  = New-Object System.Drawing.Point(980, 4)
$btnSbarSettings.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSbarSettings.FlatAppearance.BorderColor = $ColBorder
$btnSbarSettings.FlatAppearance.BorderSize  = 1
$btnSbarSettings.BackColor = $ColCard
$btnSbarSettings.ForeColor = $ColMuted
$btnSbarSettings.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSbarSettings.Anchor    = $AnchorTR
$pnlStatusBar.Controls.Add($btnSbarSettings)
$btnSbarSettings.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,90,20)),4))
$btnSbarSettings.Add_Click({ $navSettings.PerformClick() })

# ---- Tab navigation bar ----------------------------------------------------
$pnlTabBar = New-Object System.Windows.Forms.Panel
$pnlTabBar.Size      = New-Object System.Drawing.Size(1280, $TabH)
$pnlTabBar.Location  = New-Object System.Drawing.Point(0, $HdrH)
$pnlTabBar.BackColor = $ColSidebar
$pnlTabBar.Anchor    = $AnchorTLR
$form.Controls.Add($pnlTabBar)

$sepTab = New-Object System.Windows.Forms.Panel
$sepTab.Size      = New-Object System.Drawing.Size(1280, 1)
$sepTab.Location  = New-Object System.Drawing.Point(0, ([int]$TabH - 1))
$sepTab.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sepTab.Anchor    = $AnchorTLR
$pnlTabBar.Controls.Add($sepTab)

$tabW = 142  # 9 tabs × 142px ≈ 1280px
$navSysOverview = New-TabButton "Home"                 0xE80F  (0 * $tabW)  $tabW
$navSysInfo     = New-TabButton "System Information"   0xE9A0  (1 * $tabW)  $tabW
$navNetConfig   = New-TabButton "Network"              0xE701  (2 * $tabW)  $tabW
$navCamera      = New-TabButton "Camera"               0xE722  (3 * $tabW)  $tabW
$navServices    = New-TabButton "Services"             0xE9F5  (4 * $tabW)  $tabW
$navPoE         = New-TabButton "Hardware"             0xE7E8  (5 * $tabW)  $tabW
$navDisk        = New-TabButton "Disks"                0xEDA2  (6 * $tabW)  $tabW
$navEvents      = New-TabButton "OS Event Logs"        0xE7BA  (7 * $tabW)  $tabW
$navReports     = New-TabButton "Reports"              0xE7C3  (8 * $tabW)  $tabW

$btnTabFullDiag = New-Object System.Windows.Forms.Button
$btnTabFullDiag.Text      = [char]0x25B6 + "  Run Diagnostic"
$btnTabFullDiag.Size      = New-Object System.Drawing.Size(132, 38)
$btnTabFullDiag.Location  = New-Object System.Drawing.Point(1004, 15)
$btnTabFullDiag.BackColor = $ColAccent
$btnTabFullDiag.ForeColor = [System.Drawing.Color]::White
$btnTabFullDiag.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTabFullDiag.FlatAppearance.BorderSize = 0
$btnTabFullDiag.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$btnTabFullDiag.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnTabFullDiag.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnTabFullDiag.Anchor    = $AnchorTR
$btnTabFullDiag.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,132,38)),6))

$pnlTabBar.Controls.AddRange(@(
    $navSysOverview,$navSysInfo,$navNetConfig,$navCamera,$navServices,
    $navPoE,$navDisk,$navEvents,$navReports
))

# ---- Tab hover tooltips -----------------------------------------------------
$tabTip = New-Object System.Windows.Forms.ToolTip
$tabTip.AutoPopDelay = 8000   # stay visible 8 s
$tabTip.InitialDelay = 550    # appear after 550 ms hover
$tabTip.ReshowDelay  = 300
$tabTip.ShowAlways   = $true  # show even when form lacks focus
$tabTip.SetToolTip($navSysOverview, "Run Full Diagnostic across all modules and view a health summary")
$tabTip.SetToolTip($navSysInfo,     "CPU, RAM, GPU, storage, and network adapter inventory")
$tabTip.SetToolTip($navNetConfig,   "Internet access, required port connectivity, and DNS resolution for Pixellot services")
$tabTip.SetToolTip($navCamera,      "Camera NIC link speeds, cable-fault detection, ping/RTSP checks, and PoE power budget")
$tabTip.SetToolTip($navServices,    "Running status of Pixellot agent, encoder, and support services")
$tabTip.SetToolTip($navPoE,         "PoE card power budget, per-port voltage and current, and connected peripheral devices")
$tabTip.SetToolTip($navDisk,        "Drive free space, disk health, and system memory availability")
$tabTip.SetToolTip($navEvents,      "Recent OS system errors filtered for hardware and service-related issues")
$tabTip.SetToolTip($navReports,     "View, copy, or export previously saved diagnostic reports")

# Helper for hidden compat buttons (no tab appearance needed)
function New-NavButton {
    param([string]$Text, [int]$Y, [bool]$Active = $false)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Size = New-Object System.Drawing.Size(0, 0); $btn.Visible = $false
    return $btn
}

# Hidden buttons kept for internal PerformClick() compatibility
$navSettings = New-NavButton ""; $navAbout    = New-NavButton ""
$navOverview = New-NavButton ""; $navTests    = New-NavButton ""
$navHistory  = New-NavButton ""; $navHelp     = New-NavButton ""
$form.Controls.AddRange(@($navSettings,$navAbout,$navOverview,$navTests,$navHistory,$navHelp))

# Update notification - placed in header
$lblUpdate = New-Object System.Windows.Forms.Label
$lblUpdate.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblUpdate.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
$lblUpdate.Location  = New-Object System.Drawing.Point(630, 8)
$lblUpdate.Size      = New-Object System.Drawing.Size(190, 32)
$lblUpdate.Visible   = $false
$pnlHeader.Controls.Add($lblUpdate)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text      = "  Update Now"
$btnUpdate.Size      = New-Object System.Drawing.Size(116, 24)
$btnUpdate.Location  = New-Object System.Drawing.Point(828, 16)
$btnUpdate.BackColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
$btnUpdate.ForeColor = [System.Drawing.Color]::FromArgb(30, 27, 12)
$btnUpdate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUpdate.FlatAppearance.BorderSize = 0
$btnUpdate.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$btnUpdate.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnUpdate.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnUpdate.Visible   = $false
$btnUpdate.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 116, 24)), 5))
$pnlHeader.Controls.Add($btnUpdate)
$pnlHeader.Controls.Add($btnTabFullDiag)

# Compat controls referenced by timer code - hidden, off-screen
$lblVpuVal     = New-Object System.Windows.Forms.Label; $lblVpuVal.Visible     = $false
$pnlSideDot    = New-Object System.Windows.Forms.Panel; $pnlSideDot.Visible    = $false; $pnlSideDot.BackColor = $ColGreen
$lblSideStatus = New-Object System.Windows.Forms.Label; $lblSideStatus.Visible = $false
$form.Controls.AddRange(@($lblVpuVal, $pnlSideDot, $lblSideStatus))


# ---------- Load panel modules -----------------------------------------------
$script:allNavPanels = @()   # modules append via +=; full assignment follows at form-load
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
$lblHubSub.Text      = "Pixellot Unified Live System Evaluator — identify and resolve VPU issues fast."
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
    @{Nav="navSysInfo";  Title="System Information"; Desc="CPU, RAM, GPU, storage and NIC inventory";               Icon=0xE80F; R=0;C=0}
    @{Nav="navNetConfig";Title="Network";            Desc="Internet, port connectivity and DNS for Pixellot";        Icon=0xE701; R=0;C=1}
    @{Nav="navCamera";   Title="Camera";             Desc="NIC link speeds, cable faults, ping and RTSP checks";     Icon=0xE722; R=0;C=2}
    @{Nav="navServices"; Title="Services";           Desc="Pixellot agent, encoder and support services status";     Icon=0xE9F5; R=0;C=3}
    @{Nav="navPoE";      Title="Hardware";           Desc="PoE NIC budget, GPU, peripherals and NIC uptime";         Icon=0xE7E8; R=1;C=0}
    @{Nav="navDisk";     Title="Disks";              Desc="Drive space, SMART health and disk event log errors";     Icon=0xEDA2; R=1;C=1}
    @{Nav="navEvents";   Title="OS Event Logs";      Desc="Recent OS errors filtered for hardware and services";     Icon=0xE7BA; R=1;C=2}
    @{Nav="navReports";  Title="Reports";            Desc="View, copy and export saved diagnostic reports";          Icon=0xE7C3; R=1;C=3}
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
    $pw   = $pnlSysOverview.Width
    $hCW  = [int](($pw - 2*$hMargin - ($hCols-1)*$hGap) / $hCols)
    for ($i = 0; $i -lt $script:hubTiles.Count; $i++) {
        $col = $i % $hCols; $row = [int]($i / $hCols)
        $script:hubTiles[$i].Location = New-Object System.Drawing.Point(($hMargin + $col*($hCW+$hGap)), (90 + $row*($hCH+$hGap)))
        $script:hubTiles[$i].Size     = New-Object System.Drawing.Size($hCW, $hCH)
    }
    $btnHubLastReport.Location = New-Object System.Drawing.Point($hMargin, (90 + $hRows*($hCH+$hGap) + 10))
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
            if ($sync.Cancelled) { break }
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
    $btnRun.Enabled = $false; $btnRun.Text = "  Running..."
    $btnRetest.Enabled = $false
    $script:spinIdx = 0; $lblStatus.ForeColor = $ColAccent; $lblStatus.Text = " |  Starting..."

    if ($script:runspace) { try { $script:runspace.Close() } catch { } }
    if ($script:diagPs) { try { $script:diagPs.Dispose() } catch { }; $script:diagPs = $null }
    $script:runspace = [runspacefactory]::CreateRunspace()
    $script:runspace.ApartmentState = "STA"
    $script:runspace.ThreadOptions  = "ReuseThread"
    $script:runspace.Open()

    $script:diagPs = [powershell]::Create()
    $script:diagPs.Runspace = $script:runspace
    $script:diagPs.AddScript($DiagScript) | Out-Null
    $filterNicVal = if ($cboNic.SelectedIndex -gt 0) { ($cboNic.SelectedItem -as [string]) -replace '\s+\(.*', '' } else { "" }
    $script:diagPs.AddParameters(@{
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
    $script:diagPs.BeginInvoke() | Out-Null
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
    [PSCustomObject]@{ Protocol="TCP"; Port=1935; ProbeHost="pixellot.stream";        Reliable=$false; Purpose="SportzCast remote management";             Note="Also covers ports 1400-1405. Dynamic stream server." },
    [PSCustomObject]@{ Protocol="UDP"; Port=2088; ProbeHost="prod-echo.pixellot.tv";  Reliable=$true;  Purpose="Video streaming - Zixi primary";           Note="Firewall must allow outbound UDP 2088 to Pixellot servers." },
    [PSCustomObject]@{ Protocol="TCP"; Port=5672; ProbeHost="app.singular.live";      Reliable=$false; Purpose="Graphics and watermark generation";        Note="Does not accept raw probes. See *.app.singular.live domain test." },
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
    [PSCustomObject]@{ Domain="leaf-downloads.s3.amazonaws.com"; Wildcard=$false; Purpose="Canopy downloads";                                  Note="" }
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
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $c   = $tcp.BeginConnect($HostName, $Port, $null, $null)
            $ok  = $c.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok) { try { $tcp.EndConnect($c) } catch { $ok = $false } }
            $tcp.Close(); return $ok
        } catch { return $false }
    }
    function Test-UdpDns {
        param([string]$Server, [int]$TimeoutMs)
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
            $udp.Close()
            return ($r -and $r.Length -gt 6 -and ($r[3] -band 0x0F) -eq 0)
        } catch { return $false }
    }
    function Test-UdpNtp {
        param([string]$Server, [int]$TimeoutMs)
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
            $udp.Close()
            return ($r -and $r.Length -ge 48)
        } catch { return $false }
    }
    function Test-UdpEcho {
        param([string]$Server, [int]$Port, [int]$TimeoutMs)
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
            $udp.Close()
            return ([System.Text.Encoding]::ASCII.GetString($r) -eq "testing UDP on port $Port")
        } catch { return $false }
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
            $rtbNetLog.SelectionFont  = New-Object System.Drawing.Font("Consolas", 7.5, [System.Drawing.FontStyle]::Bold)
            $rtbNetLog.SelectionColor = $ColMuted
            $rtbNetLog.AppendText("`n  $($netItem.Result.ToUpper())`n")
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
        foreach ($netKey in $netCards.Keys) {
            $val = $sync["_nc_$netKey"]
            $sts = $sync["_ncs_$netKey"]
            if ($val) {
                Update-CardStatus -Card $netCards[$netKey] -Value $val -Status $sts
            }
        }
        $netTimer.Stop()
        $btnNetCancel.Visible = $false
        $btnNetRun.Enabled = $true; $btnNetRun.Text = [char]0x25B6 + "  Run Network Test"
        $lblNetStatus.ForeColor = $ColMuted
        $lblNetStatus.Text = "  $($sync.NetStep)"
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

$lblNetEta = New-Object System.Windows.Forms.Label; $lblNetEta.Text = "est. ~20 sec"
$lblNetEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblNetEta.ForeColor = $ColMuted
$lblNetEta.Location = New-Object System.Drawing.Point(378,236); $lblNetEta.AutoSize = $true
$pnlNetwork.Controls.Add($lblNetEta)

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

# =============================================================================
#  ReportGenerator.psm1  -  Run History panel
# =============================================================================

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
            $lines = Get-Content -Path $f.FullName -Tail 100 -ErrorAction Stop
            $statusLine = $lines | Where-Object { $_ -match '^STATUS:' } | Select-Object -Last 1
            $failLines  = @($lines | Where-Object { $_ -match 'DEGRADED' })
            if ($statusLine -match 'ALL_CLEAR') {
                $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
            } elseif ($statusLine -match 'ISSUES_FOUND' -or $failLines.Count -gt 0) {
                $resultText = "Issues Found"; $resultColor = $ColRed
                $ports = $failLines | ForEach-Object {
                    if ($_ -match '^\s+(.+?)\s{2,}DEGRADED') { $Matches[1].Trim() }
                } | Where-Object { $_ }
                $summary = "$($failLines.Count) fault(s)" + $(if ($ports) { " - " + ($ports -join ", ") } else { "" })
            } elseif (@($lines | Where-Object { $_ -match 'Complete' }).Count -gt 0) {
                $resultText = "All Clear"; $resultColor = $ColGreen; $summary = "All ports healthy"
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


# ---- History Panel (embedded in Reports) -----------------------------------
$pnlHistory = New-Object System.Windows.Forms.Panel
$pnlHistory.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlHistory.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlHistory.BackColor = $ColBg; $pnlHistory.Visible = $false
$pnlHistory.Anchor = $AnchorTLRB
$form.Controls.Add($pnlHistory)

$lblHistTitle = New-Object System.Windows.Forms.Label
$lblHistTitle.Text = "Run History"
$lblHistTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHistTitle.ForeColor = $ColText
$lblHistTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHistTitle.AutoSize = $true
$pnlHistory.Controls.Add($lblHistTitle)

$lblHistSub = New-Object System.Windows.Forms.Label
$lblHistSub.Text = "Past diagnostic runs - double-click a row to open the full report."
$lblHistSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5); $lblHistSub.ForeColor = $ColMuted
$lblHistSub.Location = New-Object System.Drawing.Point(10, 42); $lblHistSub.Size = New-Object System.Drawing.Size(1000, 18)
$pnlHistory.Controls.Add($lblHistSub)

$lnkHistRefresh = New-Object System.Windows.Forms.LinkLabel; $lnkHistRefresh.Text = "Refresh"
$lnkHistRefresh.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lnkHistRefresh.LinkColor = $ColMuted
$lnkHistRefresh.Location = New-Object System.Drawing.Point(1180, 44); $lnkHistRefresh.AutoSize = $true
$pnlHistory.Controls.Add($lnkHistRefresh)
$lnkHistRefresh.Add_LinkClicked({ Update-HistoryList })

$lvHistory = New-Object System.Windows.Forms.ListView
$lvHistory.Size = New-Object System.Drawing.Size(1240, 534)
$lvHistory.Location = New-Object System.Drawing.Point(10, 68); $lvHistory.Anchor = $AnchorTLRB
$lvHistory.View = [System.Windows.Forms.View]::Details
$lvHistory.FullRowSelect = $true
$lvHistory.GridLines = $false
$lvHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lvHistory.BackColor = $ColCard
$lvHistory.ForeColor = $ColText
$lvHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lvHistory.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$lvHistory.UseCompatibleStateImageBehavior = $false
$pnlHistory.Controls.Add($lvHistory)
$lvHistory.Columns.Add("Date / Time",   142) | Out-Null
$lvHistory.Columns.Add("Result",         92) | Out-Null
$lvHistory.Columns.Add("Summary",       948) | Out-Null
$lvHistory.Columns.Add("Size",           58) | Out-Null

$lvHistory.Add_DoubleClick({
    if ($lvHistory.SelectedItems.Count -gt 0) {
        $path = $lvHistory.SelectedItems[0].Tag
        if ($path -and (Test-Path $path)) { Start-Process notepad.exe $path }
    }
})

# =============================================================================
#  HelpAbout.psm1  -  About / Help panel
# =============================================================================

# ---- Help Panel (shown via About nav) --------------------------------------
$pnlHelp = New-Object System.Windows.Forms.Panel
$pnlHelp.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlHelp.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlHelp.BackColor = $ColBg; $pnlHelp.Visible = $false
$pnlHelp.Anchor = $AnchorTLRB
$form.Controls.Add($pnlHelp)

$lblHelpTitle = New-Object System.Windows.Forms.Label
$lblHelpTitle.Text = "How to Use This Tool"
$lblHelpTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHelpTitle.ForeColor = $ColText
$lblHelpTitle.Location = New-Object System.Drawing.Point(10, 16); $lblHelpTitle.AutoSize = $true
$pnlHelp.Controls.Add($lblHelpTitle)

# Help content — anchored top only so feedback section can sit at the bottom
$rtbHelp = New-Object System.Windows.Forms.RichTextBox
$rtbHelp.Size = New-Object System.Drawing.Size(1240, ($ContentH - 240))
$rtbHelp.Location = New-Object System.Drawing.Point(24, 46)
$rtbHelp.Anchor = $AnchorTLR
$rtbHelp.BackColor = $ColBg; $rtbHelp.ForeColor = $ColText
$rtbHelp.Font = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.ReadOnly = $true
$rtbHelp.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbHelp.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$pnlHelp.Controls.Add($rtbHelp)

$helpSections = @(
    @{ H="What this tool does"; B="Pulse (Pixellot Unified Live System Evaluator) is an all-in-one diagnostic tool for Pixellot VPU systems. It checks camera NIC link speeds and SmartSpeed events, pings cameras, analyses the Pixellot application log, verifies network connectivity, inspects running services, reads disk health, and scans the OS event log. Run it on-site or remotely to quickly identify what is causing a problem on a VPU." }
    @{ H="Home - running a full diagnostic"; B="From the Home screen, click the Run Full Diagnostic button (top-right of the header) and wait about 60-90 seconds. Each module row updates live as checks complete. When all seven modules finish, a banner shows either all clear or a count of issues with module names.`n`nUse the View button on any highlighted row to jump directly to that module's detail panel. Use Re-run Failed Only to quickly re-check only the modules that had issues." }
    @{ H="Camera tab"; B="Shows link speed for each Intel camera NIC port (P1, P2, ...). Green = 1 Gbps healthy. Red = 100 Mbps degraded (physical fault). Grey = no cable connected.`n`nThe SmartSpeed card counts Intel Event ID 40 - these events fire only when the NIC tried gigabit but the physical medium could not sustain it. A non-zero SmartSpeed count is definitive evidence of a cable or NIC fault, not a camera issue. Zero events on a 100 Mbps port means the device is 100-Mbps-only (OCR camera - no action needed).`n`nThe Ping and CHU Detection cards tell you whether the camera is reachable on the network and responding to RTSP." }
    @{ H="Network tab"; B="Tests ports and domains required by Pixellot using real protocol probes (DNS, NTP, TCP). Reliable tests show PASS or FAIL. Unreliable tests (dynamic stream servers) show INFO - these servers do not respond to raw probes and should be verified via the domain test instead.`n`nIf any test fails, check the uplink adapter, router, and firewall. Ensure Pixellot ports are not blocked." }
    @{ H="Services tab"; B="Shows whether core Pixellot processes are running: Agent, KeepAgentUp, Coordinator, LogMeIn, VPU, and Scoreconnect. VPU.exe not running is normal when no cameras are actively streaming - this is not a fault.`n`nIf Agent, KeepAgentUp, or Coordinator are missing, reboot the VPU or manually restart the processes. Check Windows Services (services.msc) if they do not come back." }
    @{ H="Hardware tab"; B="Shows GPU model, monitor connection, keyboard and mouse status, NIC link uptime, and PoE power budget. NIC uptime and PoE data are populated by the Camera tab - run Camera first to see these values.`n`nIf PoE budget shows LOW, check the Molex power connector on the PoE NIC card inside the VPU." }
    @{ H="Disks tab"; B="Checks physical drive health (SMART status), free space on each volume, Pixellot storage path sizes, largest top-level folders per drive, and disk-related event log errors from the last 48 hours.`n`nRed = critical (less than 5 GB free or over 97% used). Yellow = warning (less than 15 GB free or over 90% used). Clear old recordings from C:\Pixellot\recordings if space is low." }
    @{ H="Event Logs tab"; B="Reads System and Application event logs and displays errors and warnings from the last 24 hours. A high error count (especially disk, NTFS, or driver errors) often correlates with hardware problems seen in other tabs.`n`nUp to 20 errors and 10 warnings are shown per log. Use Event Viewer (eventvwr.msc) to see the full list with all details." }
    @{ H="Reports tab"; B="Lists all past Full Diagnostic runs stored in the Pulse_Results folder. Double-click any row to open the full report in Notepad. Green rows are all-clear; red rows show which ports had faults.`n`nReports are saved automatically after each Camera diagnostic run." }
    @{ H="What is a SmartSpeed event?"; B="Intel SmartSpeed Event ID 40 fires when the NIC tried to establish a gigabit link but the physical medium could not sustain it. It only fires on physical-layer failures - it never fires when a device (like an OCR camera) simply does not support gigabit.`n`nAny non-zero SmartSpeed count on a camera NIC is definitive evidence of a cable, connector, or NIC fault. Zero events on a 100 Mbps port means the device is 100-Mbps-only and gigabit was never attempted." }
    @{ H="Frequently asked questions"; B="Q: VPU.exe shows Not running - is that a problem?`nA: No. VPU.exe only runs when cameras are actively streaming. It is normal for it to be absent between games.`n`nQ: A NIC port shows No link - is that a fault?`nA: No link is normal for ports that do not have a camera connected. Only ports with a camera attached that show 100 Mbps are faults.`n`nQ: Network tests fail for pixellot.stream - is that a problem?`nA: pixellot.stream is marked INFO because it is a dynamic streaming server that does not respond to raw probes. Check the domain test result for pixellot.stream instead.`n`nQ: The tool says it cannot read the event log - what does that mean?`nA: This can happen if the Windows Event Log service is stopped or the account running the tool lacks permission. Restart the service via services.msc." }
)
$firstHelp = $true
foreach ($s in $helpSections) {
    if (-not $firstHelp) {
        $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
        $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI",5); $rtbHelp.SelectionColor = $ColBg; $rtbHelp.AppendText("`n")
    }
    $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
    $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5); $rtbHelp.SelectionColor = $ColText; $rtbHelp.AppendText("$($s.H)`n")
    $rtbHelp.SelectionStart = $rtbHelp.TextLength; $rtbHelp.SelectionLength = 0
    $rtbHelp.SelectionFont = New-Object System.Drawing.Font("Segoe UI", 9); $rtbHelp.SelectionColor = $ColMuted; $rtbHelp.AppendText("$($s.B)`n")
    $firstHelp = $false
}

# ---- Feedback Section -------------------------------------------------------
$sepFb = New-Object System.Windows.Forms.Panel
$sepFb.Size     = New-Object System.Drawing.Size($WideW, 1)
$sepFb.Location = New-Object System.Drawing.Point(0, ($ContentH - 189))
$sepFb.BackColor = $ColCard
$sepFb.Anchor   = $AnchorBLR
$pnlHelp.Controls.Add($sepFb)

$lblFbTitle = New-Object System.Windows.Forms.Label
$lblFbTitle.Text      = "Submit Feedback"
$lblFbTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$lblFbTitle.ForeColor = $ColText
$lblFbTitle.Location  = New-Object System.Drawing.Point(24, ($ContentH - 183))
$lblFbTitle.AutoSize  = $true
$lblFbTitle.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbTitle)

$lblFbSub = New-Object System.Windows.Forms.Label
$lblFbSub.Text      = "Report a bug or suggest an improvement — submitted directly as a GitHub issue."
$lblFbSub.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFbSub.ForeColor = $ColMuted
$lblFbSub.Location  = New-Object System.Drawing.Point(24, ($ContentH - 163))
$lblFbSub.Size      = New-Object System.Drawing.Size(900, 18)
$lblFbSub.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbSub)

$lblFbType = New-Object System.Windows.Forms.Label
$lblFbType.Text      = "Type:"
$lblFbType.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFbType.ForeColor = $ColText
$lblFbType.Location  = New-Object System.Drawing.Point(24, ($ContentH - 137))
$lblFbType.AutoSize  = $true
$lblFbType.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbType)

$cboFbType = New-Object System.Windows.Forms.ComboBox
$cboFbType.Items.AddRange(@("Bug Report", "Suggestion")) | Out-Null
$cboFbType.SelectedIndex = 0
$cboFbType.Size          = New-Object System.Drawing.Size(180, 24)
$cboFbType.Location      = New-Object System.Drawing.Point(70, ($ContentH - 140))
$cboFbType.BackColor     = $ColCard
$cboFbType.ForeColor     = $ColText
$cboFbType.Font          = New-Object System.Drawing.Font("Segoe UI", 9)
$cboFbType.FlatStyle     = [System.Windows.Forms.FlatStyle]::Flat
$cboFbType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cboFbType.Anchor        = $AnchorBL
$pnlHelp.Controls.Add($cboFbType)

$chkFbSysInfo = New-Object System.Windows.Forms.CheckBox
$chkFbSysInfo.Text      = "Include system info (hostname, OS, Pulse version)"
$chkFbSysInfo.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$chkFbSysInfo.ForeColor = $ColMuted
$chkFbSysInfo.Location  = New-Object System.Drawing.Point(270, ($ContentH - 138))
$chkFbSysInfo.Size      = New-Object System.Drawing.Size(380, 20)
$chkFbSysInfo.Checked   = $true
$chkFbSysInfo.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($chkFbSysInfo)

$lblFbDetails = New-Object System.Windows.Forms.Label
$lblFbDetails.Text      = "Details:"
$lblFbDetails.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFbDetails.ForeColor = $ColText
$lblFbDetails.Location  = New-Object System.Drawing.Point(24, ($ContentH - 107))
$lblFbDetails.AutoSize  = $true
$lblFbDetails.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbDetails)

$txtFbDetails = New-Object System.Windows.Forms.TextBox
$txtFbDetails.Multiline    = $true
$txtFbDetails.Size         = New-Object System.Drawing.Size(1148, 52)
$txtFbDetails.Location     = New-Object System.Drawing.Point(70, ($ContentH - 110))
$txtFbDetails.BackColor    = $ColCard
$txtFbDetails.ForeColor    = $ColText
$txtFbDetails.Font         = New-Object System.Drawing.Font("Segoe UI", 9)
$txtFbDetails.BorderStyle  = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtFbDetails.ScrollBars   = [System.Windows.Forms.ScrollBars]::Vertical
$txtFbDetails.Anchor       = $AnchorBLR
$pnlHelp.Controls.Add($txtFbDetails)

$lblFbStatus = New-Object System.Windows.Forms.Label
$lblFbStatus.Text      = ""
$lblFbStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFbStatus.ForeColor = $ColMuted
$lblFbStatus.Location  = New-Object System.Drawing.Point(24, ($ContentH - 50))
$lblFbStatus.Size      = New-Object System.Drawing.Size(900, 18)
$lblFbStatus.Anchor    = $AnchorBL
$pnlHelp.Controls.Add($lblFbStatus)

$btnFbSend = New-Object System.Windows.Forms.Button
$btnFbSend.Text      = "Send Feedback"
$btnFbSend.Size      = New-Object System.Drawing.Size(130, 28)
$btnFbSend.Location  = New-Object System.Drawing.Point(($WideW - 154), ($ContentH - 54))
$btnFbSend.BackColor = $ColAccent
$btnFbSend.ForeColor = [System.Drawing.Color]::White
$btnFbSend.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFbSend.FlatAppearance.BorderSize = 0
$btnFbSend.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$btnFbSend.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFbSend.Anchor    = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlHelp.Controls.Add($btnFbSend)

$btnFbSend.Add_Click({
    $fbType = $cboFbType.SelectedItem
    $fbText = $txtFbDetails.Text.Trim()

    if (-not $script:FeedbackToken) {
        $lblFbStatus.ForeColor = $ColYellow
        $lblFbStatus.Text = "Feedback token not configured — contact your administrator."
        return
    }
    if (-not $fbText) {
        $lblFbStatus.ForeColor = $ColYellow
        $lblFbStatus.Text = "Please enter a description before sending."
        return
    }

    $firstLine  = ($fbText -split "`n")[0].Trim()
    $issueTitle = "[$fbType] " + $(if ($firstLine.Length -gt 100) { $firstLine.Substring(0,100) + "..." } else { $firstLine })

    $sysBlock = ""
    if ($chkFbSysInfo.Checked) {
        $vpuModel = if ($sync.VpuModel) { $sync.VpuModel } else { "Unknown" }
        $sysBlock  = "`n`n---`n**System Info**`n- Host: $($env:COMPUTERNAME)`n- OS: $([System.Environment]::OSVersion.VersionString)`n- Pulse: $ScriptVersion`n- VPU Model: $vpuModel"
    }

    $label     = if ($fbType -eq "Bug Report") { "bug" } else { "enhancement" }
    $issueBody = @{ title=$issueTitle; body="$fbText$sysBlock"; labels=@($label) } | ConvertTo-Json -Compress

    $btnFbSend.Enabled     = $false
    $lblFbStatus.ForeColor = $ColMuted
    $lblFbStatus.Text      = "Submitting..."

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("Authorization",        "Bearer $script:FeedbackToken")
        $wc.Headers.Add("User-Agent",           "Pulse-VPU-Diagnostics/$ScriptVersion")
        $wc.Headers.Add("Content-Type",         "application/json")
        $wc.Headers.Add("Accept",               "application/vnd.github+json")
        $wc.Headers.Add("X-GitHub-Api-Version", "2022-11-28")
        $result = $wc.UploadString("https://api.github.com/repos/ianmoore-playon/vpu-diagnostic-tools/issues", "POST", $issueBody)
        $resp   = $result | ConvertFrom-Json
        $lblFbStatus.ForeColor = $ColGreen
        $lblFbStatus.Text      = "Submitted — Issue #$($resp.number). Thank you!"
        $txtFbDetails.Text     = ""
    } catch {
        $plain = "[$fbType]`n$fbText$sysBlock"
        try { [System.Windows.Forms.Clipboard]::SetText($plain) } catch { }
        $lblFbStatus.ForeColor = $ColYellow
        $lblFbStatus.Text      = "Could not reach GitHub. Feedback copied to clipboard."
    } finally {
        $btnFbSend.Enabled = $true
    }
})
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
    $sync.HwStep = "Querying GPU..."
    Hw-Section "Graphics"
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
               Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" } |
               Select-Object -First 1
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
        $btnHwRun.Enabled=$true; $btnHwRun.Text=[char]0x25B6+"  Check Hardware"
        $lblHwStatus.ForeColor=$ColMuted; $lblHwStatus.Text="  $($sync.HwStep)"
    }
})


# ---- VPU Hardware Panel -----------------------------------------------------
$pnlPoE = New-Object System.Windows.Forms.Panel
$pnlPoE.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlPoE.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlPoE.BackColor = $ColBg; $pnlPoE.Visible = $false; $pnlPoE.Anchor = $AnchorTLRB
$form.Controls.Add($pnlPoE)

$lblHwTitle = New-Object System.Windows.Forms.Label; $lblHwTitle.Text = "VPU Hardware"
$lblHwTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblHwTitle.ForeColor = $ColText
$lblHwTitle.Location = New-Object System.Drawing.Point(10,16); $lblHwTitle.AutoSize = $true
$pnlPoE.Controls.Add($lblHwTitle)

$lblHwSub = New-Object System.Windows.Forms.Label
$lblHwSub.Text = "GPU model, peripheral connections, NIC link uptime, and PoE power status."
$lblHwSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblHwSub.ForeColor = $ColMuted
$lblHwSub.Location = New-Object System.Drawing.Point(10,42); $lblHwSub.Size = New-Object System.Drawing.Size(1240,18)
$pnlPoE.Controls.Add($lblHwSub)

$hwCardDefs = @(
    @{ Key="HwGpu";     Title="GPU";     Sub="Graphics adapter";  X=10;  Icon=[char]0xE7F4; W=400 }
    @{ Key="HwMonitor"; Title="Monitor"; Sub="Display connected";  X=420; Icon=[char]0xE7F4; W=400 }
    @{ Key="HwMmk";     Title="Input Devices"; Sub="Keyboard & mouse"; X=830; Icon=[char]0xE7C8; W=400 }
)
$hwCards = @{}
foreach ($cd in $hwCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $hwCards[$cd.Key] = $c; $pnlPoE.Controls.Add($c.Panel)
}

$btnHwRun = New-Object System.Windows.Forms.Button; $btnHwRun.Text = [char]0x25B6 + "  Check Hardware"
$btnHwRun.Size = New-Object System.Drawing.Size(220,40); $btnHwRun.Location = New-Object System.Drawing.Point(10,170)
$btnHwRun.BackColor = $ColAccent; $btnHwRun.ForeColor = [System.Drawing.Color]::White
$btnHwRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnHwRun.FlatAppearance.BorderSize = 0
$btnHwRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnHwRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnHwRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlPoE.Controls.Add($btnHwRun)
$btnHwRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,220,40)),6))

$btnHwCancel = New-Object System.Windows.Forms.Button; $btnHwCancel.Text = "Cancel"
$btnHwCancel.Size = New-Object System.Drawing.Size(100,40); $btnHwCancel.Location = New-Object System.Drawing.Point(238,170)
$btnHwCancel.BackColor = $ColRed; $btnHwCancel.ForeColor = [System.Drawing.Color]::White
$btnHwCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnHwCancel.FlatAppearance.BorderSize = 0
$btnHwCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnHwCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnHwCancel.Visible = $false
$pnlPoE.Controls.Add($btnHwCancel)
$btnHwCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))

$lblHwEta = New-Object System.Windows.Forms.Label; $lblHwEta.Text = "est. ~5 sec"
$lblHwEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblHwEta.ForeColor = $ColMuted
$lblHwEta.Location = New-Object System.Drawing.Point(348,180); $lblHwEta.AutoSize = $true
$pnlPoE.Controls.Add($lblHwEta)

$lblHwStatus = New-Object System.Windows.Forms.Label; $lblHwStatus.Text = ""
$lblHwStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblHwStatus.ForeColor = $ColMuted
$lblHwStatus.Location = New-Object System.Drawing.Point(10,218); $lblHwStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlPoE.Controls.Add($lblHwStatus)

$lblHwLogHdr = New-Object System.Windows.Forms.Label; $lblHwLogHdr.Text = "Hardware Details"
$lblHwLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblHwLogHdr.ForeColor = $ColText
$lblHwLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblHwLogHdr.AutoSize = $true
$pnlPoE.Controls.Add($lblHwLogHdr)

$dgvHwLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlPoE.Controls.Add($dgvHwLog)

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
# =============================================================================
#  PixellotServices.psm1  -  Pixellot Services panel
# =============================================================================

# ---------- Services background script ---------------------------------------
$SvcScript = {
    param($sync)
    $sync.SvcRunning = $true; $sync.SvcComplete = $false; $sync.SvcCancelled = $false
    $item = $null; while ($sync.SvcQueue.TryDequeue([ref]$item)) { }
    function Svc-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.SvcQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Svc-Section { param([string]$Title)
        $sync.SvcQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    $critFail = 0; $warnCount = 0

    # ── Core Pixellot Processes ───────────────────────────────────────────────
    $sync.SvcStep = "Checking core Pixellot processes..."
    Svc-Section "Core Pixellot Processes"

    $required = @(
        @{ Proc="Agent";       Label="Agent.exe";       CardKey="SvcAgent";       Note="" }
        @{ Proc="KeepAgentUp"; Label="KeepAgentUp.exe"; CardKey="SvcKeepAgentUp"; Note="" }
        @{ Proc="Coordinator"; Label="Coordinator.exe"; CardKey="SvcCoordinator"; Note="" }
        @{ Proc="LogMeIn";     Label="LogMeIn.exe";     CardKey="SvcLogMeIn";     Note="" }
    )

    foreach ($r in $required) {
        if ($sync.SvcCancelled) { $sync.SvcRunning=$false; $sync.SvcComplete=$true; return }
        $procs = @(Get-Process -Name $r.Proc -ErrorAction SilentlyContinue)
        if ($procs.Count -gt 0) {
            $pidStr = ($procs | ForEach-Object { $_.Id }) -join ", "
            Svc-Log $r.Label "Running  (PID $pidStr)" "Pass"
            $sync.Cards[$r.CardKey] = @{ Value = "Running"; Status = "ok" }
        } else {
            Svc-Log $r.Label "NOT running" "Fail"
            $sync.Cards[$r.CardKey] = @{ Value = "Not running"; Status = "fail" }
            $critFail++
        }
    }

    # VPU.exe - informational; not running is normal when cameras are idle
    if (-not $sync.SvcCancelled) {
        $vpuProc = @(Get-Process -Name "VPU" -ErrorAction SilentlyContinue)
        if ($vpuProc.Count -gt 0) {
            $pidStr = ($vpuProc | ForEach-Object { $_.Id }) -join ", "
            Svc-Log "VPU.exe" "Running  (PID $pidStr)  - cameras active" "Pass"
            $sync.Cards["SvcVpu"] = @{ Value = "Active"; Status = "ok" }
        } else {
            Svc-Log "VPU.exe" "Not running  - normal when cameras are idle" "Gray"
            $sync.Cards["SvcVpu"] = @{ Value = "Idle"; Status = "neutral" }
        }
    }

    # ── Scoreconnect ─────────────────────────────────────────────────────────
    if ($sync.SvcCancelled) { $sync.SvcRunning=$false; $sync.SvcComplete=$true; return }
    $sync.SvcStep = "Checking Scoreconnect..."
    Svc-Section "Scoreconnect"

    $scSvcs = @()
    try { $scSvcs += @(Get-Service -Name        "Scoreconnect*" -ErrorAction SilentlyContinue) } catch {}
    try { $scSvcs += @(Get-Service -DisplayName "Scoreconnect*" -ErrorAction SilentlyContinue) } catch {}
    $scSvcs = @($scSvcs | Sort-Object Name -Unique)

    if ($scSvcs.Count -gt 0) {
        foreach ($svc in $scSvcs) {
            if ($svc.Status -eq "Running") {
                Svc-Log "Service: $($svc.DisplayName)" "Running" "Pass"
            } else {
                Svc-Log "Service: $($svc.DisplayName)" $svc.Status.ToString() "Warn"
                $warnCount++
            }
        }
    }

    $scProcs = @(Get-Process -Name "Scoreconnect*" -ErrorAction SilentlyContinue)
    if ($scProcs.Count -gt 0) {
        foreach ($p in $scProcs) { Svc-Log "$($p.Name).exe" "Running  (PID $($p.Id))" "Pass" }
    } elseif ($scSvcs.Count -gt 0) {
        Svc-Log "Scoreconnect*.exe" "Process not running" "Warn"; $warnCount++
    } else {
        Svc-Log "Scoreconnect" "Not detected on this VPU" "Gray"
    }

    if ($scSvcs.Count -gt 0 -or $scProcs.Count -gt 0) {
        $isRunning = (($scSvcs | Where-Object { $_.Status -eq "Running" }).Count -gt 0) -or ($scProcs.Count -gt 0)
        $sync.Cards["SvcScoreconnect"] = if ($isRunning) { @{ Value="Running"; Status="ok" } } else { @{ Value="Stopped"; Status="warn" } }
    } else {
        $sync.Cards["SvcScoreconnect"] = @{ Value = "Not installed"; Status = "neutral" }
    }

    # ── Overall summary card (used by hub tile) ───────────────────────────────
    if ($critFail -gt 0) {
        $noun = if ($critFail -eq 1) { "process" } else { "processes" }
        $sync.Cards["SvcStatus"] = @{ Value="$critFail required $noun not running"; Status="fail" }
    } elseif ($warnCount -gt 0) {
        $sync.Cards["SvcStatus"] = @{ Value="Core OK - Scoreconnect needs attention"; Status="warn" }
    } else {
        $sync.Cards["SvcStatus"] = @{ Value="All core processes running"; Status="ok" }
    }

    $sync.SvcStep = "Complete"; $sync.SvcRunning=$false; $sync.SvcComplete=$true
}


# ---------- Services timer --------------------------------------------------
$svcTimer = New-Object System.Windows.Forms.Timer; $svcTimer.Interval = 300
$svcTimer.Add_Tick({
    $svcItem = $null
    while ($sync.SvcQueue.TryDequeue([ref]$svcItem)) {
        Add-LogRow $dgvSvcLog $svcItem.Label $svcItem.Result $svcItem.L
    }
    foreach ($key in $svcCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $svcCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $svcCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.SvcRunning) {
        $script:svcSpinIdx=($script:svcSpinIdx+1)%4
        $lblSvcStatus.ForeColor=$ColAccent
        $lblSvcStatus.Text=" $(@('|','/','-','\')[$script:svcSpinIdx])  $($sync.SvcStep)"
    }
    if ($sync.SvcComplete -and -not $sync.SvcRunning) {
        $svcTimer.Stop(); $btnSvcCancel.Visible=$false
        $btnSvcRun.Enabled=$true; $btnSvcRun.Text=[char]0x25B6+"  Check Services"
        $lblSvcStatus.ForeColor=$ColMuted; $lblSvcStatus.Text="  $($sync.SvcStep)"
    }
})


# ---- Pixellot Services Panel -----------------------------------------------
$pnlServices = New-Object System.Windows.Forms.Panel
$pnlServices.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlServices.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlServices.BackColor = $ColBg; $pnlServices.Visible = $false; $pnlServices.Anchor = $AnchorTLRB
$form.Controls.Add($pnlServices)

$lblSvcTitle = New-Object System.Windows.Forms.Label; $lblSvcTitle.Text = "Pixellot Services"
$lblSvcTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblSvcTitle.ForeColor = $ColText
$lblSvcTitle.Location = New-Object System.Drawing.Point(10,16); $lblSvcTitle.AutoSize = $true
$pnlServices.Controls.Add($lblSvcTitle)

$lblSvcSub = New-Object System.Windows.Forms.Label
$lblSvcSub.Text = "Running status of core Pixellot processes, remote access, and Scoreconnect service."
$lblSvcSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblSvcSub.ForeColor = $ColMuted
$lblSvcSub.Location = New-Object System.Drawing.Point(10,42); $lblSvcSub.Size = New-Object System.Drawing.Size(1240,18)
$pnlServices.Controls.Add($lblSvcSub)

# 6 service cards: Agent, KeepAgentUp, Coordinator, LogMeIn, VPU, Scoreconnect
# Layout: 6 cards across 1260px with 12px gaps  →  W=200, step=212
$svcCardDefs = @(
    @{ Key="SvcAgent";        Title="Agent";        Sub="Core process";   X=10;   Icon=[char]0xE9F5; W=200 }
    @{ Key="SvcKeepAgentUp";  Title="KeepAgentUp";  Sub="Watchdog";       X=222;  Icon=[char]0xE9F5; W=200 }
    @{ Key="SvcCoordinator";  Title="Coordinator";  Sub="Core process";   X=434;  Icon=[char]0xE9F5; W=200 }
    @{ Key="SvcLogMeIn";      Title="LogMeIn";      Sub="Remote access";  X=646;  Icon=[char]0xE9F5; W=200 }
    @{ Key="SvcVpu";          Title="VPU";          Sub="Camera encoder"; X=858;  Icon=[char]0xE9F5; W=200 }
    @{ Key="SvcScoreconnect"; Title="Scoreconnect"; Sub="Score overlay";  X=1070; Icon=[char]0xE9F5; W=200 }
)
$svcCards = @{}
foreach ($cd in $svcCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $svcCards[$cd.Key] = $c; $pnlServices.Controls.Add($c.Panel)
}

$btnSvcRun = New-Object System.Windows.Forms.Button; $btnSvcRun.Text = [char]0x25B6 + "  Check Services"
$btnSvcRun.Size = New-Object System.Drawing.Size(220,40); $btnSvcRun.Location = New-Object System.Drawing.Point(10,170)
$btnSvcRun.BackColor = $ColAccent; $btnSvcRun.ForeColor = [System.Drawing.Color]::White
$btnSvcRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnSvcRun.FlatAppearance.BorderSize = 0
$btnSvcRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnSvcRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnSvcRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlServices.Controls.Add($btnSvcRun)
$btnSvcRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,220,40)),6))

$lblSvcEta = New-Object System.Windows.Forms.Label; $lblSvcEta.Text = "est. ~3 sec"
$lblSvcEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblSvcEta.ForeColor = $ColMuted
$lblSvcEta.Location = New-Object System.Drawing.Point(240,180); $lblSvcEta.AutoSize = $true
$pnlServices.Controls.Add($lblSvcEta)

$btnSvcCancel = New-Object System.Windows.Forms.Button; $btnSvcCancel.Text = "Cancel"
$btnSvcCancel.Size = New-Object System.Drawing.Size(100,40); $btnSvcCancel.Location = New-Object System.Drawing.Point(340,170)
$btnSvcCancel.BackColor = $ColRed; $btnSvcCancel.ForeColor = [System.Drawing.Color]::White
$btnSvcCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnSvcCancel.FlatAppearance.BorderSize = 0
$btnSvcCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnSvcCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnSvcCancel.Visible = $false
$pnlServices.Controls.Add($btnSvcCancel)
$btnSvcCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))

$lblSvcStatus = New-Object System.Windows.Forms.Label; $lblSvcStatus.Text = ""
$lblSvcStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblSvcStatus.ForeColor = $ColMuted
$lblSvcStatus.Location = New-Object System.Drawing.Point(10,218); $lblSvcStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlServices.Controls.Add($lblSvcStatus)

$lblSvcLogHdr = New-Object System.Windows.Forms.Label; $lblSvcLogHdr.Text = "Service Details"
$lblSvcLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblSvcLogHdr.ForeColor = $ColText
$lblSvcLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblSvcLogHdr.AutoSize = $true
$pnlServices.Controls.Add($lblSvcLogHdr)

$dgvSvcLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlServices.Controls.Add($dgvSvcLog)
$script:svcRunspace = $null; $script:svcPs = $null; $script:svcSpinIdx = 0


function Start-SvcDiagnostic {
    if ($sync.SvcRunning) { return }
    $sync.SvcCancelled = $false
    foreach ($key in $svcCards.Keys) {
        $sync.Cards[$key] = @{ Value="--"; Status="neutral" }
        Update-CardStatus -Card $svcCards[$key] -Value "--" -Status "neutral"
    }
    $dgvSvcLog.Rows.Clear(); $btnSvcRun.Enabled=$false; $btnSvcRun.Text="  Running..."
    $btnSvcCancel.Visible=$true; $script:svcSpinIdx=0
    $lblSvcStatus.ForeColor=$ColAccent; $lblSvcStatus.Text=" |  Starting..."
    if ($script:svcRunspace) { try { $script:svcRunspace.Close() } catch { } }
    if ($script:svcPs) { try { $script:svcPs.Dispose() } catch { }; $script:svcPs = $null }
    $script:svcRunspace = [runspacefactory]::CreateRunspace()
    $script:svcRunspace.ApartmentState="STA"; $script:svcRunspace.ThreadOptions="ReuseThread"; $script:svcRunspace.Open()
    $script:svcPs = [powershell]::Create(); $script:svcPs.Runspace=$script:svcRunspace
    $script:svcPs.AddScript($SvcScript) | Out-Null
    $script:svcPs.AddParameters(@{ sync=$sync }) | Out-Null
    $script:svcPs.BeginInvoke() | Out-Null; $svcTimer.Start()
}

$btnSvcRun.Add_Click({ Start-SvcDiagnostic })
$btnSvcCancel.Add_Click({ $sync.SvcCancelled=$true; $btnSvcCancel.Visible=$false })
# =============================================================================
#  DiskHealth.psm1  -  System and Disk Health panel
# =============================================================================

# ---------- Disk/System health background script -----------------------------
$DiskScript = {
    param($sync)
    $sync.DiskRunning = $true; $sync.DiskComplete = $false; $sync.DiskCancelled = $false
    $item = $null; while ($sync.DiskQueue.TryDequeue([ref]$item)) { }
    function Disk-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.DiskQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Disk-Section { param([string]$Title)
        $sync.DiskQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }
    function Format-Size {
        param([double]$Bytes)
        if ($Bytes -ge 1TB) { return "{0:F2} TB" -f ($Bytes/1TB) }
        if ($Bytes -ge 1GB) { return "{0:F1} GB" -f ($Bytes/1GB) }
        if ($Bytes -ge 1MB) { return "{0:F0} MB" -f ($Bytes/1MB) }
        return "{0:F0} KB" -f ($Bytes/1KB)
    }

    $overallWorst = "ok"
    $osDrive      = $env:SystemDrive  # e.g. "C:"

    # ── 1. Physical Drives ────────────────────────────────────────────────────
    $sync.DiskStep = "Inventorying physical drives..."
    Disk-Section "Physical Drives"

    # Try Storage module for MediaType & HealthStatus (PS 5.1+, Storage cmdlets)
    $pdHealth = @{}
    try {
        @(Get-PhysicalDisk -ErrorAction Stop) | ForEach-Object {
            $pdHealth[$_.FriendlyName] = $_
        }
    } catch {}

    # SMART failure prediction - build per-disk-index hashtable so attribution is correct on multi-disk systems
    $smartFails = @{}
    try {
        @(Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue) |
            Where-Object { $_.PredictFailure } |
            ForEach-Object { if ($_.InstanceName -match '(\d+)') { $smartFails[[string]$Matches[1]] = $true } }
    } catch {}

    $physDisks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Sort-Object Index)
    foreach ($phys in $physDisks) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }

        $sizeStr = Format-Size ([double]$phys.Size)

        # Media type: prefer Get-PhysicalDisk, fall back to model name heuristic
        $mediaType = "Unknown"
        $matchPd = $pdHealth.Values | Where-Object {
            $phys.Model -like "*$($_.FriendlyName)*" -or $_.FriendlyName -like "*$($phys.Model)*"
        } | Select-Object -First 1
        if ($matchPd -and $matchPd.MediaType -ne "Unspecified") {
            $mediaType = $matchPd.MediaType
        } elseif ($phys.Model -match "SSD|Solid.State|NVMe|M\.2") { $mediaType = "SSD" }
        elseif ($phys.Model -match "HDD|Hard.Disk") { $mediaType = "HDD" }
        elseif ($phys.MediaType -match "Fixed") { $mediaType = "HDD" }

        # Health: Win32_DiskDrive.Status + Get-PhysicalDisk.HealthStatus
        $healthStr = $phys.Status
        $healthLvl = if ($phys.Status -eq "OK") { "Pass" } else { "Warn" }
        if ($matchPd) {
            $healthStr = $matchPd.HealthStatus
            $healthLvl = switch ($matchPd.HealthStatus) {
                "Healthy"   { "Pass" }
                "Warning"   { "Warn" }
                "Unhealthy" { "Fail" }
                default     { "Info" }
            }
        }
        if ($smartFails.ContainsKey([string]$phys.Index) -and $healthLvl -eq "Pass") { $healthStr = "SMART Predict Failure"; $healthLvl = "Fail" }
        if ($healthLvl -in @("Warn","Fail")) { $overallWorst = if ($healthLvl -eq "Fail") { "fail" } elseif ($overallWorst -ne "fail") { "warn" } else { $overallWorst } }

        $typeLabel = if ($mediaType -ne "Unknown") { "  [$mediaType]" } else { "" }
        Disk-Log "Disk $($phys.Index)  $($phys.Model)" "$sizeStr  $($phys.InterfaceType)$typeLabel" "Info"
        Disk-Log "  Health / SMART" $healthStr $healthLvl
        if ($phys.FirmwareRevision) { Disk-Log "  Firmware" $phys.FirmwareRevision "Gray" }
        if ($phys.SerialNumber -and $phys.SerialNumber.Trim()) { Disk-Log "  Serial" $phys.SerialNumber.Trim() "Gray" }
    }

    if ($physDisks.Count -eq 0) { Disk-Log "Physical drives" "None detected" "Warn" }

    # ── 2. Volumes & Space ────────────────────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Checking volumes and space..."
    Disk-Section "Volumes & Space"

    # Pixellot path patterns used to identify recording/storage drives
    $pixStorePaths = @("Pixellot\recordings","Pixellot\data","Pixellot\Data","recordings")

    $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
    $cardFreeGB = 0; $cardPct = 0

    foreach ($vol in $volumes) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }

        # Inaccessible / unformatted
        if (-not $vol.Size -or $vol.Size -eq 0) {
            Disk-Log "$($vol.DeviceID)  $($vol.VolumeName)" "Inaccessible or unformatted" "Warn"
            if ($overallWorst -ne "fail") { $overallWorst = "warn" }
            continue
        }

        $totalGB = [math]::Round($vol.Size   / 1GB, 1)
        $freeGB  = [math]::Round($vol.FreeSpace / 1GB, 1)
        $usedGB  = [math]::Round(($vol.Size - $vol.FreeSpace) / 1GB, 1)
        $usedPct = [math]::Round((1 - $vol.FreeSpace/$vol.Size) * 100)
        $freePct = 100 - $usedPct

        # Drive role
        $roles = @()
        if ($vol.DeviceID -eq $osDrive) { $roles += "OS Drive" }
        foreach ($pp in $pixStorePaths) {
            if (Test-Path "$($vol.DeviceID)\$pp" -ErrorAction SilentlyContinue) { $roles += "Recording / Storage"; break }
        }
        if (-not $roles) { $roles += if ($totalGB -gt 200) { "Storage" } else { "Data" } }
        $roleLabel = " [$($roles -join ' / ')]"

        # Thresholds: absolute free space + percentage (tighter % catches large drives)
        $lvl = "Pass"
        if ($freeGB -lt 5  -or $usedPct -gt 97) { $lvl = "Fail" }
        elseif ($freeGB -lt 15 -or $usedPct -gt 90) { $lvl = "Warn" }

        if ($lvl -eq "Fail" -and $overallWorst -ne "fail")            { $overallWorst = "fail" }
        elseif ($lvl -eq "Warn" -and $overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }

        $volName  = if ($vol.VolumeName) { "  $($vol.VolumeName)" } else { "" }
        $headline = "$($vol.DeviceID)$volName$roleLabel"
        $detail   = "{0} GB used  /  {1} GB free  /  {2} GB total   ({3}% used  |  {4}% free)" -f $usedGB,$freeGB,$totalGB,$usedPct,$freePct
        Disk-Log $headline $detail $lvl

        # Threshold guidance
        if ($lvl -eq "Fail") {
            Disk-Log "  >> Action" "Critically low - free space immediately or VPU may stop recording" "Fail"
        } elseif ($lvl -eq "Warn") {
            Disk-Log "  >> Action" "Space getting low - review large files and clear old recordings or logs" "Warn"
        }

        $volKey = "DiskVol_$($vol.DeviceID -replace ':','')"
        $volSt  = if ($lvl -eq "Fail") { "fail" } elseif ($lvl -eq "Warn") { "warn" } else { "ok" }
        $sync.Cards[$volKey] = @{ Value = "$freeGB GB free  ($freePct% free)"; Status = $volSt }
        if ($vol.DeviceID -eq $osDrive) { $cardFreeGB = $freeGB; $cardPct = $usedPct }
    }

    if ($volumes.Count -eq 0) { Disk-Log "Volumes" "No fixed volumes detected" "Warn"; $overallWorst = "fail" }

    # ── 3. Pixellot Storage Paths ─────────────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Scanning Pixellot paths..."
    Disk-Section "Pixellot Storage Paths"

    $pixPaths = @(
        @{ Path="C:\Pixellot\Data\Log";         Label="Pixellot Logs";        Warn=2GB;  Crit=5GB  }
        @{ Path="C:\Pixellot\recordings";        Label="Recordings (C:)";      Warn=10GB; Crit=50GB }
        @{ Path="C:\Pixellot\Data";              Label="Pixellot Data";        Warn=5GB;  Crit=20GB }
        @{ Path="C:\Pixellot\temp";              Label="Pixellot Temp";        Warn=1GB;  Crit=3GB  }
        @{ Path="C:\Pixellot";                   Label="Pixellot Root (total)"; Warn=20GB; Crit=80GB }
        @{ Path="C:\Windows\Temp";              Label="Windows Temp";          Warn=2GB;  Crit=5GB  }
        @{ Path="$env:TEMP";                    Label="User Temp";             Warn=2GB;  Crit=5GB  }
        @{ Path="C:\Users";                     Label="User Profiles (total)"; Warn=10GB; Crit=30GB }
    )

    foreach ($pp in $pixPaths) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
        if (-not (Test-Path $pp.Path -ErrorAction SilentlyContinue)) {
            Disk-Log $pp.Label "Path not found" "Gray"
            continue
        }
        try {
            $sz = (Get-ChildItem $pp.Path -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
                   Measure-Object Length -Sum).Sum
            if (-not $sz) { $sz = 0 }
            $szStr = Format-Size $sz
            $lvl   = if ($sz -ge $pp.Crit) { "Fail" }
                     elseif ($sz -ge $pp.Warn) { "Warn" }
                     else { "Pass" }
            Disk-Log $pp.Label $szStr $lvl
            if ($lvl -eq "Fail") {
                Disk-Log "  >> Action" "Unusually large - investigate and clear if safe" "Fail"
            } elseif ($lvl -eq "Warn") {
                Disk-Log "  >> Action" "Growing large - consider cleaning up old files" "Warn"
            }
        } catch {
            Disk-Log $pp.Label "Could not read (access error)" "Warn"
        }
    }

    # Additional recording drives (non-C: drives containing Pixellot paths)
    foreach ($vol in ($volumes | Where-Object { $_.DeviceID -ne "C:" })) {
        foreach ($pp in @("Pixellot\recordings","recordings","Pixellot\Data")) {
            $testPath = "$($vol.DeviceID)\$pp"
            if (Test-Path $testPath -ErrorAction SilentlyContinue) {
                try {
                    $sz = (Get-ChildItem $testPath -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
                           Measure-Object Length -Sum).Sum
                    Disk-Log "Recordings ($($vol.DeviceID))" (Format-Size $sz) "Info"
                } catch { Disk-Log "Recordings ($($vol.DeviceID))" "Found (size unavailable)" "Info" }
                break
            }
        }
    }

    # ── 4. Top Space Consumers (per drive, top-level scan) ────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Finding large folders..."
    Disk-Section "Largest Top-Level Folders"

    $scanSw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($vol in $volumes) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
        if (-not $vol.Size -or $vol.Size -eq 0) { continue }

        $topDirs = @(Get-ChildItem "$($vol.DeviceID)\" -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -notin @("System Volume Information","$RECYCLE.BIN","Recovery") })

        $dirSizes = @()
        foreach ($dir in $topDirs) {
            if ($sync.DiskCancelled -or $scanSw.Elapsed.TotalSeconds -gt 30) { break }
            try {
                $sz = (Get-ChildItem $dir.FullName -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
                       Measure-Object Length -Sum).Sum
                if ($sz -gt 0) { $dirSizes += [PSCustomObject]@{ Name=$dir.Name; Path=$dir.FullName; Size=$sz } }
            } catch { }
        }

        $top = $dirSizes | Sort-Object Size -Descending | Select-Object -First 8
        if ($top.Count -gt 0) {
            Disk-Log "$($vol.DeviceID)\ - top folders" "" "Section"
            foreach ($d in $top) {
                $bar = "#" * [int]([math]::Min(($d.Size / $vol.Size) * 20, 20))
                Disk-Log "  $($d.Name)" "$(Format-Size $d.Size)  $bar" "Info"
            }
        }
    }

    # ── 5. Disk-Related Event Log Errors ─────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Checking disk-related event logs..."
    Disk-Section "Disk Event Log Errors (last 48 h)"

    $since  = (Get-Date).AddHours(-48)
    $diskEvtSources = @("disk","Ntfs","volmgr","partmgr","stornvme","msahci",
                        "iaStorAVC","iaStorV","storahci","cdrom")
    # Critical disk event IDs: 7/11 (device error), 51 (IO warning), 55 (NTFS corrupt),
    # 50 (delayed write failed), 153 (IO failure warning)
    $diskEvtIds = @(7, 11, 51, 52, 55, 50, 57, 140, 153)

    $diskEvents = @()
    try {
        $diskEvents = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Level=@(1,2,3); StartTime=$since } -ErrorAction Stop |
            Where-Object {
                ($diskEvtSources -contains $_.ProviderName) -or ($diskEvtIds -contains $_.Id)
            } | Select-Object -First 20)
    } catch {}

    if ($diskEvents.Count -eq 0) {
        Disk-Log "Disk events" "No disk-related errors in the last 48 hours" "Pass"
    } else {
        $errCount  = ($diskEvents | Where-Object { $_.Level -in @(1,2) }).Count
        $warnCount = ($diskEvents | Where-Object { $_.Level -eq 3 }).Count
        $summaryLvl = if ($errCount -gt 0) { "Fail" } else { "Warn" }
        Disk-Log "Events found" "$errCount error(s), $warnCount warning(s)" $summaryLvl
        if ($summaryLvl -eq "Fail" -and $overallWorst -ne "fail") { $overallWorst = "fail" }
        elseif ($summaryLvl -eq "Warn" -and $overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }

        foreach ($ev in ($diskEvents | Select-Object -First 10)) {
            $evLvl  = if ($ev.Level -in @(1,2)) { "Fail" } else { "Warn" }
            $evTime = $ev.TimeCreated.ToString("MM/dd HH:mm")
            $evMsg  = ($ev.Message -split "`n")[0].Trim()
            if ($evMsg.Length -gt 100) { $evMsg = $evMsg.Substring(0,97) + "..." }
            Disk-Log "  $evTime  ID $($ev.Id)  $($ev.ProviderName)" $evMsg $evLvl
        }
        if ($diskEvents.Count -gt 10) {
            Disk-Log "  (and $($diskEvents.Count - 10) more)" "Open Event Logs tab for full list" "Gray"
        }
        Disk-Log "  >> Action" "Disk errors detected - check cables, run chkdsk, or replace suspect drive" "Fail"
        $sync.Cards["DiskVol_$($osDrive -replace ':','')"] = @{ Value = "$errCount disk error(s) - $cardFreeGB GB free"; Status = $overallWorst }
    }

    $diskStatusVal = switch ($overallWorst) { "fail"{"Issues detected"} "warn"{"Warnings found"} default{"Healthy"} }
    $sync.Cards["DiskStatus"] = @{ Value=$diskStatusVal; Status=$overallWorst }

    $sync.DiskStep = "Complete"; $sync.DiskRunning=$false; $sync.DiskComplete=$true
}


# ---------- Disk timer ------------------------------------------------------
$diskTimer = New-Object System.Windows.Forms.Timer; $diskTimer.Interval = 300
$diskTimer.Add_Tick({
    $diskItem = $null
    while ($sync.DiskQueue.TryDequeue([ref]$diskItem)) {
        Add-LogRow $dgvDiskLog $diskItem.Label $diskItem.Result $diskItem.L
    }
    foreach ($key in $diskCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $diskCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $diskCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.DiskRunning) {
        $script:diskSpinIdx=($script:diskSpinIdx+1)%4
        $lblDiskStatus.ForeColor=$ColAccent
        $lblDiskStatus.Text=" $(@('|','/','-','\')[$script:diskSpinIdx])  $($sync.DiskStep)"
    }
    if ($sync.DiskComplete -and -not $sync.DiskRunning) {
        $diskTimer.Stop(); $btnDiskCancel.Visible=$false
        $btnDiskRun.Enabled=$true; $btnDiskRun.Text=[char]0x25B6+"  Check System Health"
        $lblDiskStatus.ForeColor=$ColMuted; $lblDiskStatus.Text="  $($sync.DiskStep)"
    }
})


# ---- System & Disk Health Panel --------------------------------------------
$pnlDisk = New-Object System.Windows.Forms.Panel
$pnlDisk.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlDisk.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlDisk.BackColor = $ColBg; $pnlDisk.Visible = $false; $pnlDisk.Anchor = $AnchorTLRB
$form.Controls.Add($pnlDisk)
$lblDiskTitle = New-Object System.Windows.Forms.Label; $lblDiskTitle.Text = "System & Disk Health"
$lblDiskTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblDiskTitle.ForeColor = $ColText
$lblDiskTitle.UseMnemonic = $false
$lblDiskTitle.Location = New-Object System.Drawing.Point(10,16); $lblDiskTitle.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskTitle)
$lblDiskSub = New-Object System.Windows.Forms.Label
$lblDiskSub.Text = "Physical drive health, volume free space, Pixellot storage paths, top space consumers, and disk event log errors."
$lblDiskSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblDiskSub.ForeColor = $ColMuted
$lblDiskSub.Location = New-Object System.Drawing.Point(10,42); $lblDiskSub.Size = New-Object System.Drawing.Size(1240,18)
$pnlDisk.Controls.Add($lblDiskSub)
$diskVolumes = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
$diskCardDefs = @(); $diskXPos = 10
foreach ($diskVol in $diskVolumes) {
    $drvKey = "DiskVol_$($diskVol.DeviceID -replace ':','')"
    $diskCardDefs += @{ Key=$drvKey; Title="$($diskVol.DeviceID) Space"; Sub="$($diskVol.DeviceID) free space"; X=$diskXPos; Icon=[char]0xEDA2; W=250 }
    $diskXPos += 260
}
if ($diskCardDefs.Count -eq 0) {
    $diskCardDefs = @( @{ Key="DiskVol_C"; Title="C: Space"; Sub="C: free space"; X=10; Icon=[char]0xEDA2; W=250 } )
}
$diskCards = @{}
foreach ($cd in $diskCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $diskCards[$cd.Key] = $c; $pnlDisk.Controls.Add($c.Panel)
}
$btnDiskRun = New-Object System.Windows.Forms.Button; $btnDiskRun.Text = [char]0x25B6 + "  Check System Health"
$btnDiskRun.Size = New-Object System.Drawing.Size(240,40); $btnDiskRun.Location = New-Object System.Drawing.Point(10,170)
$btnDiskRun.BackColor = $ColAccent; $btnDiskRun.ForeColor = [System.Drawing.Color]::White
$btnDiskRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDiskRun.FlatAppearance.BorderSize = 0
$btnDiskRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnDiskRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnDiskRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlDisk.Controls.Add($btnDiskRun)
$btnDiskRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,240,40)),6))
$btnDiskCancel = New-Object System.Windows.Forms.Button; $btnDiskCancel.Text = "Cancel"
$btnDiskCancel.Size = New-Object System.Drawing.Size(100,40); $btnDiskCancel.Location = New-Object System.Drawing.Point(258,170)
$btnDiskCancel.BackColor = $ColRed; $btnDiskCancel.ForeColor = [System.Drawing.Color]::White
$btnDiskCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDiskCancel.FlatAppearance.BorderSize = 0
$btnDiskCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnDiskCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnDiskCancel.Visible = $false
$pnlDisk.Controls.Add($btnDiskCancel)
$btnDiskCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))

$lblDiskEta = New-Object System.Windows.Forms.Label; $lblDiskEta.Text = "est. ~30 sec"
$lblDiskEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblDiskEta.ForeColor = $ColMuted
$lblDiskEta.Location = New-Object System.Drawing.Point(368,180); $lblDiskEta.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskEta)
$lblDiskStatus = New-Object System.Windows.Forms.Label; $lblDiskStatus.Text = ""
$lblDiskStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblDiskStatus.ForeColor = $ColMuted
$lblDiskStatus.Location = New-Object System.Drawing.Point(10,218); $lblDiskStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlDisk.Controls.Add($lblDiskStatus)
$lblDiskLogHdr = New-Object System.Windows.Forms.Label; $lblDiskLogHdr.Text = "Health Report"
$lblDiskLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblDiskLogHdr.ForeColor = $ColText
$lblDiskLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblDiskLogHdr.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskLogHdr)
$dgvDiskLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlDisk.Controls.Add($dgvDiskLog)
$script:diskRunspace = $null; $script:diskPs = $null; $script:diskSpinIdx = 0


function Start-DiskDiagnostic {
    if ($sync.DiskRunning) { return }
    $sync.DiskCancelled = $false
    foreach ($key in $diskCards.Keys) {
        $sync.Cards[$key] = @{ Value="--"; Status="neutral" }
        Update-CardStatus -Card $diskCards[$key] -Value "--" -Status "neutral"
    }
    $dgvDiskLog.Rows.Clear(); $btnDiskRun.Enabled=$false; $btnDiskRun.Text="  Running..."
    $btnDiskCancel.Visible=$true; $script:diskSpinIdx=0
    $lblDiskStatus.ForeColor=$ColAccent; $lblDiskStatus.Text=" |  Starting..."
    if ($script:diskRunspace) { try { $script:diskRunspace.Close() } catch { } }
    if ($script:diskPs) { try { $script:diskPs.Dispose() } catch { }; $script:diskPs = $null }
    $script:diskRunspace = [runspacefactory]::CreateRunspace()
    $script:diskRunspace.ApartmentState="STA"; $script:diskRunspace.ThreadOptions="ReuseThread"; $script:diskRunspace.Open()
    $script:diskPs = [powershell]::Create(); $script:diskPs.Runspace=$script:diskRunspace
    $script:diskPs.AddScript($DiskScript) | Out-Null
    $script:diskPs.AddParameters(@{ sync=$sync }) | Out-Null
    $script:diskPs.BeginInvoke() | Out-Null; $diskTimer.Start()
}

$btnDiskRun.Add_Click({ Start-DiskDiagnostic })
$btnDiskCancel.Add_Click({ $sync.DiskCancelled=$true; $btnDiskCancel.Visible=$false })

# =============================================================================
#  EventLogs.psm1  -  Event Logs panel
# =============================================================================

# ---------- Event Viewer background script -----------------------------------
$EvtScript = {
    param($sync, [int]$EvtHours=24)
    $sync.EvtRunning = $true; $sync.EvtComplete = $false; $sync.EvtCancelled = $false
    $item = $null; while ($sync.EvtQueue.TryDequeue([ref]$item)) { }
    function Evt-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.EvtQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Evt-Section { param([string]$Title)
        $sync.EvtQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    $since = (Get-Date).AddHours(-$EvtHours)
    $totalErrors = 0; $totalWarns = 0

    foreach ($logName in @("System","Application")) {
        if ($sync.EvtCancelled) { break }
        $sync.EvtStep = "Reading $logName events..."
        Evt-Section $logName
        try {
            $evts = @(Get-WinEvent -FilterHashtable @{ LogName=$logName; Level=@(1,2,3); StartTime=$since } -MaxEvents 100 -ErrorAction Stop)
            $errs = @($evts | Where-Object { $_.Level -in @(1,2) })
            $wrns = @($evts | Where-Object { $_.Level -eq 3 })
            $totalErrors += $errs.Count; $totalWarns += $wrns.Count
            if ($evts.Count -eq 0) {
                Evt-Log "Last ${EvtHours}h" "No errors or warnings" "Pass"
            } else {
                Evt-Log "Errors (last ${EvtHours}h)"   "$($errs.Count)" $(if($errs.Count-gt0){"Fail"}else{"Pass"})
                Evt-Log "Warnings (last ${EvtHours}h)" "$($wrns.Count)" $(if($wrns.Count-gt0){"Warn"}else{"Info"})
                foreach ($ev in ($errs | Select-Object -First 20)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 72) { $msg = $msg.Substring(0,69)+"..." }
                    Evt-Log "$($ev.TimeCreated.ToString('MM/dd HH:mm'))  $($ev.ProviderName)" $msg "Fail"
                }
                foreach ($ev in ($wrns | Select-Object -First 10)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 72) { $msg = $msg.Substring(0,69)+"..." }
                    Evt-Log "$($ev.TimeCreated.ToString('MM/dd HH:mm'))  $($ev.ProviderName)" $msg "Warn"
                }
            }
        } catch { Evt-Log $logName "Error reading event log" "Warn" }
    }

    $sync.Cards["EvtStatus"] = @{
        Value  = if($totalErrors-gt0){"$totalErrors errors"}elseif($totalWarns-gt0){"$totalWarns warns"}else{"Clean"}
        Status = if($totalErrors-gt0){"fail"}elseif($totalWarns-gt0){"warn"}else{"ok"}
    }
    $sync.EvtStep = "Complete"; $sync.EvtRunning=$false; $sync.EvtComplete=$true
}


# ---------- Event Viewer timer -----------------------------------------------
$evtTimer = New-Object System.Windows.Forms.Timer; $evtTimer.Interval = 300
$evtTimer.Add_Tick({
    $evtItem = $null
    while ($sync.EvtQueue.TryDequeue([ref]$evtItem)) {
        Add-LogRow $dgvEvtLog $evtItem.Label $evtItem.Result $evtItem.L
    }
    foreach ($key in $evtCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $evtCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $evtCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.EvtRunning) {
        $script:evtSpinIdx=($script:evtSpinIdx+1)%4
        $lblEvtStatus.ForeColor=$ColAccent
        $lblEvtStatus.Text=" $(@('|','/','-','\')[$script:evtSpinIdx])  $($sync.EvtStep)"
    }
    if ($sync.EvtComplete -and -not $sync.EvtRunning) {
        $evtTimer.Stop(); $btnEvtCancel.Visible=$false
        $btnEvtRun.Enabled=$true; $btnEvtRun.Text=[char]0x25B6+"  Check Event Log"
        $lblEvtStatus.ForeColor=$ColMuted; $lblEvtStatus.Text="  $($sync.EvtStep)"
    }
})


# ---- Event Viewer Panel ----------------------------------------------------
$pnlEvents = New-Object System.Windows.Forms.Panel
$pnlEvents.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlEvents.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlEvents.BackColor = $ColBg; $pnlEvents.Visible = $false; $pnlEvents.Anchor = $AnchorTLRB
$form.Controls.Add($pnlEvents)
$lblEvtTitle = New-Object System.Windows.Forms.Label; $lblEvtTitle.Text = "OS Event Logs"
$lblEvtTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblEvtTitle.ForeColor = $ColText
$lblEvtTitle.Location = New-Object System.Drawing.Point(10,16); $lblEvtTitle.AutoSize = $true
$pnlEvents.Controls.Add($lblEvtTitle)
$lblEvtSub = New-Object System.Windows.Forms.Label
$lblEvtSub.Text = "Recent errors and warnings from the System and Application Windows event logs (last 24 hours)."
$lblEvtSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblEvtSub.ForeColor = $ColMuted
$lblEvtSub.Location = New-Object System.Drawing.Point(10,42); $lblEvtSub.Size = New-Object System.Drawing.Size(1240,18)
$pnlEvents.Controls.Add($lblEvtSub)
$evtCardDefs = @(
    @{ Key="EvtStatus"; Title="Event Status"; Sub="Errors / warnings (24h)"; X=10; Icon=[char]0xE7BA; W=280 }
)
$evtCards = @{}
foreach ($cd in $evtCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $evtCards[$cd.Key] = $c; $pnlEvents.Controls.Add($c.Panel)
}
$btnEvtRun = New-Object System.Windows.Forms.Button; $btnEvtRun.Text = [char]0x25B6 + "  Check Event Log"
$btnEvtRun.Size = New-Object System.Drawing.Size(220,40); $btnEvtRun.Location = New-Object System.Drawing.Point(10,170)
$btnEvtRun.BackColor = $ColAccent; $btnEvtRun.ForeColor = [System.Drawing.Color]::White
$btnEvtRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnEvtRun.FlatAppearance.BorderSize = 0
$btnEvtRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnEvtRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnEvtRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlEvents.Controls.Add($btnEvtRun)
$btnEvtRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,220,40)),6))
$btnEvtCancel = New-Object System.Windows.Forms.Button; $btnEvtCancel.Text = "Cancel"
$btnEvtCancel.Size = New-Object System.Drawing.Size(100,40); $btnEvtCancel.Location = New-Object System.Drawing.Point(238,170)
$btnEvtCancel.BackColor = $ColRed; $btnEvtCancel.ForeColor = [System.Drawing.Color]::White
$btnEvtCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnEvtCancel.FlatAppearance.BorderSize = 0
$btnEvtCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnEvtCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnEvtCancel.Visible = $false
$pnlEvents.Controls.Add($btnEvtCancel)
$btnEvtCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))

$lblEvtEta = New-Object System.Windows.Forms.Label; $lblEvtEta.Text = "est. ~5 sec"
$lblEvtEta.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblEvtEta.ForeColor = $ColMuted
$lblEvtEta.Location = New-Object System.Drawing.Point(348,180); $lblEvtEta.AutoSize = $true
$pnlEvents.Controls.Add($lblEvtEta)
$lblEvtStatus = New-Object System.Windows.Forms.Label; $lblEvtStatus.Text = ""
$lblEvtStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblEvtStatus.ForeColor = $ColMuted
$lblEvtStatus.Location = New-Object System.Drawing.Point(10,218); $lblEvtStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlEvents.Controls.Add($lblEvtStatus)
$lblEvtLogHdr = New-Object System.Windows.Forms.Label; $lblEvtLogHdr.Text = "Event Log"
$lblEvtLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblEvtLogHdr.ForeColor = $ColText
$lblEvtLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblEvtLogHdr.AutoSize = $true
$pnlEvents.Controls.Add($lblEvtLogHdr)
$dgvEvtLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlEvents.Controls.Add($dgvEvtLog)
$script:evtRunspace = $null; $script:evtPs = $null; $script:evtSpinIdx = 0


function Start-EvtDiagnostic {
    if ($sync.EvtRunning) { return }
    $sync.EvtCancelled = $false
    $sync.Cards["EvtStatus"] = @{ Value="--"; Status="neutral" }
    foreach ($key in $evtCards.Keys) { Update-CardStatus -Card $evtCards[$key] -Value "--" -Status "neutral" }
    $dgvEvtLog.Rows.Clear(); $btnEvtRun.Enabled=$false; $btnEvtRun.Text="  Running..."
    $btnEvtCancel.Visible=$true; $script:evtSpinIdx=0
    $lblEvtStatus.ForeColor=$ColAccent; $lblEvtStatus.Text=" |  Starting..."
    if ($script:evtRunspace) { try { $script:evtRunspace.Close() } catch { } }
    if ($script:evtPs) { try { $script:evtPs.Dispose() } catch { }; $script:evtPs = $null }
    $script:evtRunspace = [runspacefactory]::CreateRunspace()
    $script:evtRunspace.ApartmentState="STA"; $script:evtRunspace.ThreadOptions="ReuseThread"; $script:evtRunspace.Open()
    $script:evtPs = [powershell]::Create(); $script:evtPs.Runspace=$script:evtRunspace
    $script:evtPs.AddScript($EvtScript) | Out-Null
    $script:evtPs.AddParameters(@{ sync=$sync; EvtHours=24 }) | Out-Null
    $script:evtPs.BeginInvoke() | Out-Null; $evtTimer.Start()
}

$btnEvtRun.Add_Click({ Start-EvtDiagnostic })
$btnEvtCancel.Add_Click({ $sync.EvtCancelled=$true; $btnEvtCancel.Visible=$false })

# =============================================================================
#  SystemInformation.psm1  -  System Information panel
#  Collects OS, CPU, RAM, GPU, disk and NIC details via CIM in a background
#  runspace and streams them into a DataGridView log.
# =============================================================================

$SysInfoScript = {
    param($sync)
    $sync.SysInfoRunning = $true; $sync.SysInfoComplete = $false
    $item = $null; while ($sync.SysInfoQueue.TryDequeue([ref]$item)) { }

    function Si-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.SysInfoQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Si-Section { param([string]$Title)
        $sync.SysInfoQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    # -- Pixellot Software -------------------------------------------------------
    $sync.SysInfoStep = "Querying Pixellot software..."
    Si-Section "Pixellot Software"
    try {
        $pxReg  = Get-ItemProperty -Path "HKLM:\SOFTWARE\Pixellot" -ErrorAction Stop
        $pxVer  = if ($pxReg.PSObject.Properties['Version']      -and $pxReg.Version)      { $pxReg.Version }      else { "Not found" }
        $pxImg  = if ($pxReg.PSObject.Properties['ImageVersion'] -and $pxReg.ImageVersion) { $pxReg.ImageVersion } else { "Not found" }
        $pxDeps = if ($pxReg.PSObject.Properties['Dependencies'] -and $pxReg.Dependencies) { $pxReg.Dependencies } else { "Not found" }
        Si-Log "Software Version"    $pxVer  "Info"
        Si-Log "Image Version"       $pxImg  "Info"
        Si-Log "Dependency Version"  $pxDeps "Info"
    } catch { Si-Log "Pixellot" "Registry key not found (HKLM:\SOFTWARE\Pixellot)" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Operating System --------------------------------------------------------
    $sync.SysInfoStep = "Querying operating system..."
    Si-Section "Operating System"
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        Si-Log "Edition"       $os.Caption                                                         "Info"
        Si-Log "Version"       $os.Version                                                         "Info"
        Si-Log "Build"         ([string]$os.BuildNumber)                                           "Info"
        Si-Log "Architecture"  $os.OSArchitecture                                                  "Info"
        Si-Log "Install Date"  $os.InstallDate.ToString("yyyy-MM-dd")                             "Info"
        $up = (Get-Date) - $os.LastBootUpTime
        Si-Log "Uptime"        "$([int][Math]::Floor($up.TotalDays))d $($up.Hours)h $($up.Minutes)m"  "Info"
    } catch { Si-Log "OS" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- System ------------------------------------------------------------------
    $sync.SysInfoStep = "Querying system info..."
    Si-Section "System"
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        Si-Log "Computer Name" $cs.Name                                                             "Info"
        Si-Log "Manufacturer"  $cs.Manufacturer                                                     "Info"
        Si-Log "Model"         $cs.Model                                                            "Info"
        $dom = if ($cs.PartOfDomain) { "Domain: $($cs.Domain)" } else { "Workgroup: $($cs.Workgroup)" }
        Si-Log "Network"       $dom                                                                 "Info"
        Si-Log "System Type"   $cs.SystemType                                                       "Info"
    } catch { Si-Log "System" "Query failed" "Warn" }
    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        Si-Log "BIOS"  "$($bios.SMBIOSBIOSVersion)  ($($bios.ReleaseDate.ToString('yyyy-MM-dd')))"  "Info"
        $ser = $bios.SerialNumber
        if ($ser -and $ser.Trim() -notin @("","System Serial Number","To Be Filled By O.E.M.","Default string")) {
            Si-Log "Serial Number" $ser.Trim()                                                      "Gray"
        }
    } catch { }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Processor ---------------------------------------------------------------
    $sync.SysInfoStep = "Querying processor..."
    Si-Section "Processor"
    $fdCpuShort = "Unknown CPU"
    try {
        $cpus = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        foreach ($cpu in $cpus) {
            Si-Log "Name"         $cpu.Name.Trim()                                                          "Info"
            Si-Log "Manufacturer" $cpu.Manufacturer                                                         "Info"
            Si-Log "Max Speed"    ("{0:F2} GHz" -f ($cpu.MaxClockSpeed / 1000.0))                           "Info"
            Si-Log "Cores"        "$($cpu.NumberOfCores) physical / $($cpu.NumberOfLogicalProcessors) logical"  "Info"
            if ($cpu.SocketDesignation) { Si-Log "Socket" $cpu.SocketDesignation                            "Info" }
        }
        if ($cpus.Count -gt 0) {
            $fdCpuShort = $cpus[0].Name.Trim() -replace 'Intel\(R\) Core\(TM\) ','Core ' -replace '\(R\)|\(TM\)','' -replace '\s+@\s.*','' -replace '\s+',' '
        }
    } catch { Si-Log "CPU" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Memory ------------------------------------------------------------------
    $sync.SysInfoStep = "Querying memory..."
    Si-Section "Memory"
    $fdRamGB = 0
    try {
        $os2 = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $fdRamGB = [int]([double]$os2.TotalVisibleMemorySize / 1048576.0 + 0.5)
        Si-Log "Total RAM"  ("{0:F1} GB" -f ([double]$os2.TotalVisibleMemorySize / 1048576.0))     "Info"
        Si-Log "Available"  ("{0:F1} GB" -f ([double]$os2.FreePhysicalMemory     / 1048576.0))     "Info"
        $slots = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        $n = 1
        foreach ($s in $slots) {
            $sGB     = "{0} GB" -f [int]($s.Capacity / 1073741824)
            $memType = switch ([int]$s.SMBIOSMemoryType) { 24{"DDR3"} 26{"DDR4"} 34{"DDR5"} default{"DDR"} }
            $spd     = if ($s.Speed) { "$($s.Speed) MHz" } else { "" }
            $mfr     = $s.Manufacturer
            $mfrStr  = if ($mfr -and $mfr -notlike "*Unknown*" -and $mfr -notlike "*To Be*" -and $mfr.Trim() -ne "") { "  ($($mfr.Trim()))" } else { "" }
            Si-Log "Slot $n" "$sGB $memType $spd$mfrStr" "Info"
            $n++
        }
    } catch { Si-Log "Memory" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Graphics ----------------------------------------------------------------
    $sync.SysInfoStep = "Querying graphics..."
    Si-Section "Graphics"
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
                  Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" })
        $discrete = @($gpus | Where-Object { $_.Name -notlike "*Intel*" -and $_.Name -notlike "*Microsoft*" })
        if ($discrete.Count -gt 0) { $gpus = $discrete }
        if ($gpus.Count -eq 0) { Si-Log "GPU" "None detected" "Warn" }
        foreach ($gpu in $gpus) {
            Si-Log "Name"   $gpu.Name                                                               "Info"
            if ($gpu.AdapterRAM -gt 0) {
                $vMB = [int]($gpu.AdapterRAM / 1048576)
                $vStr = if ($vMB -ge 1024) { "{0} GB" -f [int]($vMB / 1024) } else { "$vMB MB" }
                Si-Log "VRAM"   $vStr                                                               "Info"
            }
            if ($gpu.DriverVersion) { Si-Log "Driver" $gpu.DriverVersion                           "Gray" }
        }
    } catch { Si-Log "GPU" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Storage -----------------------------------------------------------------
    $sync.SysInfoStep = "Querying storage..."
    Si-Section "Storage"
    try {
        $disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Sort-Object Index)
        if ($disks.Count -eq 0) { Si-Log "Disks" "None detected" "Warn" }
        foreach ($d in $disks) {
            $sizeGB = "{0:F0} GB" -f ([double]$d.Size / 1073741824.0)
            Si-Log "Disk $($d.Index) - $($d.Model)" "$sizeGB  [$($d.InterfaceType)]"               "Info"
            if ($d.SerialNumber -and $d.SerialNumber.Trim()) {
                Si-Log "  Serial" $d.SerialNumber.Trim()                                            "Gray"
            }
        }
    } catch { Si-Log "Storage" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Network Adapters --------------------------------------------------------
    $sync.SysInfoStep = "Querying network adapters..."
    Si-Section "Network Adapters"
    try {
        $nics = @(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
                  Where-Object { $_.PhysicalAdapter -eq $true } | Sort-Object Index)
        if ($nics.Count -eq 0) { Si-Log "NICs" "None detected" "Warn" }
        foreach ($nic in $nics) {
            $mac = if ($nic.MACAddress) { $nic.MACAddress } else { "-" }
            Si-Log $nic.Name $mac "Info"
            if ($nic.Speed -and [long]$nic.Speed -gt 0) {
                $spd = [long]$nic.Speed
                $spdStr = if ($spd -ge 1000000000) { "{0} Gbps" -f [int]($spd/1000000000) } `
                          elseif ($spd -ge 1000000)  { "{0} Mbps" -f [int]($spd/1000000) } `
                          else { "$spd bps" }
                Si-Log "  Speed"  $spdStr "Info"
            }
            $connStatus = [int]$nic.NetConnectionStatus
            $connStr = switch ($connStatus) { 2{"Connected"} 7{"Media disconnected"} default{"Not connected"} }
            $connLvl = if ($connStatus -eq 2) { "Pass" } else { "Gray" }
            Si-Log "  Status" $connStr $connLvl
        }
    } catch { Si-Log "NICs" "Query failed" "Warn" }

    $ramStr = if ($fdRamGB -gt 0) { "$fdRamGB GB RAM" } else { "RAM unknown" }
    $sync.Cards["SysInfo"] = @{ Value = "$fdCpuShort   |   $ramStr"; Status = "ok" }
    $sync.SysInfoRunning = $false
    $sync.SysInfoComplete = $true
}

# ---------- Panel -----------------------------------------------------------
$pnlSysInfo = New-Object System.Windows.Forms.Panel
$pnlSysInfo.Size      = New-Object System.Drawing.Size($ContentW, $ContentH)
$pnlSysInfo.Location  = New-Object System.Drawing.Point(0, $ContentY)
$pnlSysInfo.BackColor = $ColBg
$pnlSysInfo.Anchor    = $AnchorTLRB
$pnlSysInfo.Visible   = $false
$form.Controls.Add($pnlSysInfo)
$script:allNavPanels += $pnlSysInfo

$lblSiTitle = New-Object System.Windows.Forms.Label
$lblSiTitle.Text      = "System Information"
$lblSiTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
$lblSiTitle.ForeColor = $ColText
$lblSiTitle.Location  = New-Object System.Drawing.Point(30, 24)
$lblSiTitle.Size      = New-Object System.Drawing.Size(700, 28)
$pnlSysInfo.Controls.Add($lblSiTitle)

$lblSiSub = New-Object System.Windows.Forms.Label
$lblSiSub.Text      = "Hardware and operating system details for this VPU."
$lblSiSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSiSub.ForeColor = $ColMuted
$lblSiSub.Location  = New-Object System.Drawing.Point(30, 56)
$lblSiSub.Size      = New-Object System.Drawing.Size(800, 18)
$pnlSysInfo.Controls.Add($lblSiSub)

$btnSiRefresh = New-Object System.Windows.Forms.Button
$btnSiRefresh.Text      = [char]0xE72C + "  Refresh"
$btnSiRefresh.Size      = New-Object System.Drawing.Size(120, 32)
$btnSiRefresh.Location  = New-Object System.Drawing.Point(30, 86)
$btnSiRefresh.BackColor = $ColCard
$btnSiRefresh.ForeColor = $ColText
$btnSiRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSiRefresh.FlatAppearance.BorderSize = 0
$btnSiRefresh.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnSiRefresh.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSiRefresh.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 120, 32)), 6))
$pnlSysInfo.Controls.Add($btnSiRefresh)

$lblSiStatus = New-Object System.Windows.Forms.Label
$lblSiStatus.Text      = "Ready"
$lblSiStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSiStatus.ForeColor = $ColMuted
$lblSiStatus.Location  = New-Object System.Drawing.Point(162, 94)
$lblSiStatus.Size      = New-Object System.Drawing.Size(400, 18)
$pnlSysInfo.Controls.Add($lblSiStatus)

$siGrid = New-LogGrid -X 30 -Y 130 -W ($ContentW - 60) -H ($ContentH - 140) -LabelColW 240
$pnlSysInfo.Controls.Add($siGrid)

# ---------- Timer -----------------------------------------------------------
$sysInfoTimer = New-Object System.Windows.Forms.Timer
$sysInfoTimer.Interval = 150
$sysInfoTimer.Add_Tick({
    $item = $null
    while ($sync.SysInfoQueue.TryDequeue([ref]$item)) {
        Add-LogRow $siGrid $item.Label $item.Result $item.L
    }
    if ($sync.SysInfoComplete) {
        $sysInfoTimer.Stop()
        $btnSiRefresh.Enabled = $true
        $lblSiStatus.Text = "Collected at $(Get-Date -Format 'h:mm:ss tt')"
    } else {
        $lblSiStatus.Text = $sync.SysInfoStep
    }
})

# ---------- Collection function ---------------------------------------------
function Start-SysInfoCollection {
    if ($sync.SysInfoRunning) { return }
    $siGrid.Rows.Clear()
    $btnSiRefresh.Enabled  = $false
    $lblSiStatus.Text      = "Collecting..."
    $sync.SysInfoComplete  = $false
    $sync.SysInfoCancelled = $false
    $sync.SysInfoStep      = "Starting..."
    if ($script:sysInfoRunspace) {
        try { $script:sysInfoRunspace.Close(); $script:sysInfoRunspace.Dispose() } catch { }
    }
    $script:sysInfoRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:sysInfoRunspace.ApartmentState = "STA"
    $script:sysInfoRunspace.ThreadOptions  = "ReuseThread"
    $script:sysInfoRunspace.Open()
    $script:sysInfoRunspace.SessionStateProxy.SetVariable("sync", $sync)
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $script:sysInfoRunspace
    $ps.AddScript($SysInfoScript).AddArgument($sync) | Out-Null
    $ps.BeginInvoke() | Out-Null
    $sysInfoTimer.Start()
}

$btnSiRefresh.Add_Click({ Start-SysInfoCollection })

$pnlSysInfo.Add_VisibleChanged({
    if ($this.Visible -and -not $sync.SysInfoRunning -and -not $sync.SysInfoComplete) {
        Start-SysInfoCollection
    }
})
# =============================================================================
#  FullDiagnostic.psm1  -  Orchestrates all module diagnostics and shows a
#  one-page summary on the Home panel.
#
#  Severity levels: Critical (fail) / Warning (warn) / Healthy (ok) / Complete (neutral)
# =============================================================================

# --- Module definitions -------------------------------------------------------
# RunFn: returns a Button reference for Invoke-ButtonClick, or the string "SysInfo".
# This enables both full and partial (failed-only) re-runs.
$fdModuleDefs = @(
    @{ Name="System Overview";       Icon=0xE80F; NavBtn={$navSysInfo};   RunFn={Start-SysInfoCollection};    CompleteFn={$sync.SysInfoComplete}; RunningFn={$sync.SysInfoRunning}; CardKeys=@("SysInfo") }
    @{ Name="Network Configuration"; Icon=0xE701; NavBtn={$navNetConfig}; RunFn={Start-NetDiagnostic};        CompleteFn={$sync.NetComplete};     RunningFn={$sync.NetRunning};     CardKeys=@("NetInternet","NetPorts","NetDomains") }
    @{ Name="Camera Connectivity";   Icon=0xE722; NavBtn={$navCamera};    RunFn={Start-CameraConnDiagnostic}; CompleteFn={$sync.Complete};        RunningFn={$sync.Running};        CardKeys=@("SmartSpeed","PingCHU","ChuDetect","PoEBudget") }
    @{ Name="Pixellot Services";     Icon=0xE9F5; NavBtn={$navServices};  RunFn={Start-SvcDiagnostic};        CompleteFn={$sync.SvcComplete};     RunningFn={$sync.SvcRunning};     CardKeys=@("SvcStatus") }
    @{ Name="VPU Hardware";          Icon=0xE7E8; NavBtn={$navPoE};       RunFn={Start-HwDiagnostic};         CompleteFn={$sync.HwComplete};      RunningFn={$sync.HwRunning};      CardKeys=@("HwGpu","HwMonitor","HwMmk") }
    @{ Name="Disk & System Health";  Icon=0xEDA2; NavBtn={$navDisk};      RunFn={Start-DiskDiagnostic};       CompleteFn={$sync.DiskComplete};    RunningFn={$sync.DiskRunning};    CardKeys=@("DiskStatus") }
    @{ Name="Event Viewer";          Icon=0xE7BA; NavBtn={$navEvents};    RunFn={Start-EvtDiagnostic};        CompleteFn={$sync.EvtComplete};     RunningFn={$sync.EvtRunning};     CardKeys=@("EvtStatus") }
)

# Indices being re-run in a partial run; empty means all modules.
$script:fdRerunIndices = @()

# --- Status helpers -----------------------------------------------------------
function Get-WorstCardStatus {
    param([string[]]$Keys)
    $pri = @{ fail=3; warn=2; ok=1; neutral=0 }
    $worst = "neutral"
    foreach ($k in $Keys) {
        if ($sync.Cards.ContainsKey($k)) {
            $s = $sync.Cards[$k].Status
            if ($pri.ContainsKey($s) -and $pri[$s] -gt $pri[$worst]) { $worst = $s }
        }
    }
    return $worst
}

function Get-ModuleSummaryText {
    param([string[]]$Keys)
    $parts = @()
    foreach ($k in $Keys) {
        if ($sync.Cards.ContainsKey($k)) {
            $v = $sync.Cards[$k].Value
            if ($v -and $v -ne "--") { $parts += $v }
        }
    }
    return ($parts -join "   |   ")
}

# Per-module human-readable summary (replaces raw card-value concatenation).
function Get-FdModuleSummary {
    param([int]$Idx, [string]$Worst)
    switch ($Idx) {
        0 { # System Overview
            $v = if ($sync.Cards.ContainsKey("SysInfo")) { $sync.Cards["SysInfo"].Value } else { "" }
            return if ($v -and $v -ne "--") { $v } else { "Hardware details collected" }
        }
        1 { # Network Configuration
            if ($Worst -eq "ok") { return "Internet connected - all ports and domains reachable" }
            $parts = @()
            foreach ($k in @("NetInternet","NetPorts","NetDomains")) {
                if ($sync.Cards.ContainsKey($k)) {
                    $c = $sync.Cards[$k]
                    if ($c.Status -ne "ok" -and $c.Value -and $c.Value -ne "--") { $parts += $c.Value }
                }
            }
            return if ($parts) { $parts -join "   |   " } else { Get-ModuleSummaryText @("NetInternet","NetPorts","NetDomains") }
        }
        2 { # Camera Connectivity
            if ($Worst -eq "ok") { return "All cameras online and responding normally" }
            return Get-ModuleSummaryText @("SmartSpeed","PingCHU","ChuDetect","PoEBudget")
        }
        3 { # Pixellot Services
            $v = if ($sync.Cards.ContainsKey("SvcStatus")) { $sync.Cards["SvcStatus"].Value } else { "" }
            if ($Worst -eq "ok") { return "All Pixellot services running" }
            if ($v -eq "None found") { return "No Pixellot services detected on this VPU" }
            return if ($v -and $v -ne "--") { $v } else { "Service check complete" }
        }
        4 { # VPU Hardware
            return Get-ModuleSummaryText @("HwGpu","HwMonitor","HwMmk")
        }
        5 { # Disk & System Health
            return Get-ModuleSummaryText @("DiskStatus","MemStatus")
        }
        6 { # Event Viewer
            $v = if ($sync.Cards.ContainsKey("EvtStatus")) { $sync.Cards["EvtStatus"].Value } else { "" }
            if (-not $v -or $v -eq "--") { return "No critical errors found in recent logs" }
            if ($Worst -eq "ok")         { return "No critical errors found in recent logs" }
            if ($v -match "^(\d+)\s+error") { return "$($Matches[1]) system errors in recent logs - click View to review" }
            return $v
        }
    }
    return Get-ModuleSummaryText $fdModuleDefs[$Idx].CardKeys
}

# Per-module next-step recommendation (shown only for Warning / Critical).
function Get-FdActionText {
    param([int]$Idx, [string]$Worst)
    if ($Worst -notin @("fail","warn")) { return "" }
    switch ($Idx) {
        0 { return "Verify hardware meets minimum VPU specifications" }
        1 { return "Check network cable, router, and firewall - ensure Pixellot ports are open" }
        2 { return "Inspect camera cable connections for damage or loose RJ45 connectors" }
        3 {
            $v = if ($sync.Cards.ContainsKey("SvcStatus")) { $sync.Cards["SvcStatus"].Value } else { "" }
            if ($v -like "*not running*") { return "Restart the missing process(es) from the Services tab or reboot the VPU" }
            if ($v -like "*Scoreconnect*") { return "Restart the Scoreconnect service from the Services tab" }
            return "Open the Services tab to review process and service status"
        }
        4 { return "Reconnect monitor, keyboard, or mouse - check USB and display cable connections" }
        5 { return "Free disk space if critically low - run chkdsk for drive errors" }
        6 { return "Open Event Logs to investigate hardware or driver-related errors" }
    }
    return ""
}

# Fire a module's diagnostic by calling its named Start-* function directly.
function Invoke-FdModule {
    param([hashtable]$Mod)
    & $Mod.RunFn
}

# --- Panel -------------------------------------------------------------------
$pnlFullDiag = New-Object System.Windows.Forms.Panel
$pnlFullDiag.Size      = New-Object System.Drawing.Size($ContentW, $ContentH)
$pnlFullDiag.Location  = New-Object System.Drawing.Point(0, $ContentY)
$pnlFullDiag.BackColor = $ColBg
$pnlFullDiag.Anchor    = $AnchorTLRB
$pnlFullDiag.Visible   = $false
$form.Controls.Add($pnlFullDiag)
$script:allNavPanels += $pnlFullDiag

$lblFdTitle = New-Object System.Windows.Forms.Label
$lblFdTitle.Text      = "Full Diagnostic"
$lblFdTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 14)
$lblFdTitle.ForeColor = $ColText
$lblFdTitle.Location  = New-Object System.Drawing.Point(30, 20)
$lblFdTitle.AutoSize  = $true
$pnlFullDiag.Controls.Add($lblFdTitle)

$lblFdSub = New-Object System.Windows.Forms.Label
$lblFdSub.Text      = "Runs all checks and summarises results."
$lblFdSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFdSub.ForeColor = $ColMuted
$lblFdSub.Location  = New-Object System.Drawing.Point(30, 56)
$lblFdSub.AutoSize  = $true
$pnlFullDiag.Controls.Add($lblFdSub)

# --- Status banner (2-line: headline + module detail) ------------------------
$pnlFdBanner = New-Object System.Windows.Forms.Panel
$pnlFdBanner.Size      = New-Object System.Drawing.Size(1220, 54)
$pnlFdBanner.Location  = New-Object System.Drawing.Point(30, 84)
$pnlFdBanner.BackColor = $ColCard
$pnlFdBanner.Visible   = $false
$pnlFdBanner.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 1220, 54)), 6))
$pnlFullDiag.Controls.Add($pnlFdBanner)

$lblFdBannerIcon = New-Object System.Windows.Forms.Label
$lblFdBannerIcon.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 14)
$lblFdBannerIcon.ForeColor = $ColGreen
$lblFdBannerIcon.Location  = New-Object System.Drawing.Point(14, 10)
$lblFdBannerIcon.AutoSize  = $true
$lblFdBannerIcon.BackColor = [System.Drawing.Color]::Transparent
$pnlFdBanner.Controls.Add($lblFdBannerIcon)

# Line 1 - bold summary ("2 critical, 1 warning detected")
$lblFdBannerText = New-Object System.Windows.Forms.Label
$lblFdBannerText.Font        = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblFdBannerText.ForeColor   = $ColGreen
$lblFdBannerText.Location    = New-Object System.Drawing.Point(50, 7)
$lblFdBannerText.AutoSize    = $true
$lblFdBannerText.BackColor   = [System.Drawing.Color]::Transparent
$lblFdBannerText.UseMnemonic = $false
$pnlFdBanner.Controls.Add($lblFdBannerText)

# Line 2 - muted detail ("Camera Connectivity (Critical)   |   Event Viewer (Warning)")
$lblFdBannerDetail = New-Object System.Windows.Forms.Label
$lblFdBannerDetail.Font        = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFdBannerDetail.ForeColor   = $ColMuted
$lblFdBannerDetail.Location    = New-Object System.Drawing.Point(50, 30)
$lblFdBannerDetail.Size        = New-Object System.Drawing.Size(1140, 18)
$lblFdBannerDetail.BackColor   = [System.Drawing.Color]::Transparent
$lblFdBannerDetail.UseMnemonic = $false
$pnlFdBanner.Controls.Add($lblFdBannerDetail)

# --- Module rows (one per module) --------------------------------------------
$fdRows        = @()
$script:fdRowY = 150     # first row top (banner bottom = 84+54=138, gap=12)
$fdRowH        = 54
$fdRowGap      = 6

foreach ($mod in $fdModuleDefs) {
    $rPnl = New-Object System.Windows.Forms.Panel
    $rPnl.Size      = New-Object System.Drawing.Size(1220, $fdRowH)
    $rPnl.Location  = New-Object System.Drawing.Point(30, $script:fdRowY)
    $rPnl.BackColor = $ColCard
    $rPnl.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 1220, $fdRowH)), 6))
    $pnlFullDiag.Controls.Add($rPnl)

    # MDL2 icon
    $iLbl = New-Object System.Windows.Forms.Label
    $iLbl.Text      = [char]$mod.Icon
    $iLbl.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 14)
    $iLbl.ForeColor = $ColAccent
    $iLbl.Location  = New-Object System.Drawing.Point(14, 13)
    $iLbl.Size      = New-Object System.Drawing.Size(28, 28)
    $iLbl.BackColor = [System.Drawing.Color]::Transparent
    $rPnl.Controls.Add($iLbl)

    # Module name (top line)
    $nLbl = New-Object System.Windows.Forms.Label
    $nLbl.Text        = $mod.Name
    $nLbl.Font        = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $nLbl.ForeColor   = $ColText
    $nLbl.Location    = New-Object System.Drawing.Point(50, 9)
    $nLbl.Size        = New-Object System.Drawing.Size(210, 20)
    $nLbl.BackColor   = [System.Drawing.Color]::Transparent
    $nLbl.UseMnemonic = $false
    $rPnl.Controls.Add($nLbl)

    # Status dot
    $sDot = New-Object System.Windows.Forms.Panel
    $sDot.Size      = New-Object System.Drawing.Size(10, 10)
    $sDot.Location  = New-Object System.Drawing.Point(270, 14)
    $sDot.BackColor = $ColMuted
    $sDot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 10, 10)), 5))
    $rPnl.Controls.Add($sDot)

    # Severity label (top line) - "Waiting" / "Running" / "Healthy" / "Warning" / "Critical"
    $sLbl = New-Object System.Windows.Forms.Label
    $sLbl.Text      = "Waiting"
    $sLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
    $sLbl.ForeColor = $ColMuted
    $sLbl.Location  = New-Object System.Drawing.Point(288, 9)
    $sLbl.Size      = New-Object System.Drawing.Size(108, 18)
    $sLbl.BackColor = [System.Drawing.Color]::Transparent
    $rPnl.Controls.Add($sLbl)

    # Human-readable summary (top line)
    $vLbl = New-Object System.Windows.Forms.Label
    $vLbl.Text        = ""
    $vLbl.Font        = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $vLbl.ForeColor   = $ColMuted
    $vLbl.Location    = New-Object System.Drawing.Point(406, 9)
    $vLbl.Size        = New-Object System.Drawing.Size(686, 18)
    $vLbl.BackColor   = [System.Drawing.Color]::Transparent
    $vLbl.UseMnemonic = $false
    $rPnl.Controls.Add($vLbl)

    # Suggested action (bottom line - hidden for passing modules)
    $aLbl = New-Object System.Windows.Forms.Label
    $aLbl.Text        = ""
    $aLbl.Font        = New-Object System.Drawing.Font("Segoe UI", 8)
    $aLbl.ForeColor   = $ColYellow
    $aLbl.Location    = New-Object System.Drawing.Point(406, 31)
    $aLbl.Size        = New-Object System.Drawing.Size(686, 17)
    $aLbl.BackColor   = [System.Drawing.Color]::Transparent
    $aLbl.Visible     = $false
    $aLbl.UseMnemonic = $false
    $rPnl.Controls.Add($aLbl)

    # View button - neutral until complete, accented for issues
    $vBtn = New-Object System.Windows.Forms.Button
    $vBtn.Text      = "View  >"
    $vBtn.Size      = New-Object System.Drawing.Size(96, 30)
    $vBtn.Location  = New-Object System.Drawing.Point(1110, 12)
    $vBtn.BackColor = $ColNavHover
    $vBtn.ForeColor = $ColText
    $vBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $vBtn.FlatAppearance.BorderSize = 0
    $vBtn.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $vBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $vBtn.Enabled   = $false
    $vBtn.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 96, 30)), 5))
    $capturedNav = $mod.NavBtn
    $vBtn.Add_Click({ (& $capturedNav).PerformClick() }.GetNewClosure())
    $rPnl.Controls.Add($vBtn)

    $fdRows += @{
        Panel     = $rPnl
        Dot       = $sDot
        StatusLbl = $sLbl
        ValueLbl  = $vLbl
        ActionLbl = $aLbl
        ViewBtn   = $vBtn
        LastWorst = "neutral"
    }
    $script:fdRowY += $fdRowH + $fdRowGap
}

# --- Bottom buttons (Re-run All | Re-run Failed | Back to Home) --------------
# Rows end at 150 + 7*(54+6) = 570.  Buttons at 582.
$btnFdRerun = New-Object System.Windows.Forms.Button
$btnFdRerun.Text      = [char]0x25B6 + "  Re-run All"
$btnFdRerun.Size      = New-Object System.Drawing.Size(172, 40)
$btnFdRerun.Location  = New-Object System.Drawing.Point(30, 582)
$btnFdRerun.BackColor = $ColAccent
$btnFdRerun.ForeColor = [System.Drawing.Color]::White
$btnFdRerun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFdRerun.FlatAppearance.BorderSize = 0
$btnFdRerun.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$btnFdRerun.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFdRerun.Enabled   = $false
$btnFdRerun.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 172, 40)), 6))
$pnlFullDiag.Controls.Add($btnFdRerun)

$btnFdRerunFailed = New-Object System.Windows.Forms.Button
$btnFdRerunFailed.Text      = "Re-run Failed Only"
$btnFdRerunFailed.Size      = New-Object System.Drawing.Size(190, 40)
$btnFdRerunFailed.Location  = New-Object System.Drawing.Point(214, 582)
$btnFdRerunFailed.BackColor = $ColNavHover
$btnFdRerunFailed.ForeColor = $ColYellow
$btnFdRerunFailed.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFdRerunFailed.FlatAppearance.BorderSize = 0
$btnFdRerunFailed.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnFdRerunFailed.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFdRerunFailed.Enabled   = $false
$btnFdRerunFailed.Visible   = $false
$btnFdRerunFailed.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 190, 40)), 6))
$pnlFullDiag.Controls.Add($btnFdRerunFailed)

$btnFdBack = New-Object System.Windows.Forms.Button
$btnFdBack.Text      = "<  Back to Home"
$btnFdBack.Size      = New-Object System.Drawing.Size(160, 40)
$btnFdBack.Location  = New-Object System.Drawing.Point(418, 582)
$btnFdBack.BackColor = $ColNavHover
$btnFdBack.ForeColor = $ColText
$btnFdBack.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFdBack.FlatAppearance.BorderSize = 0
$btnFdBack.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnFdBack.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFdBack.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 160, 40)), 6))
$btnFdBack.Add_Click({ $navSysOverview.PerformClick() })
$pnlFullDiag.Controls.Add($btnFdBack)

# --- Poll timer (300 ms) ------------------------------------------------------
$timerFullDiag          = New-Object System.Windows.Forms.Timer
$timerFullDiag.Interval = 300
$script:fdSpinIdx       = 0
$script:fdStartTime     = $null
$script:fdSpinChars     = @('|','/','-','\')

$timerFullDiag.Add_Tick({
    $script:fdSpinIdx = ($script:fdSpinIdx + 1) % 4
    $spin      = $script:fdSpinChars[$script:fdSpinIdx]
    $allDone   = $true
    $critCount = 0
    $warnCount = 0
    $critNames = @()
    $warnNames = @()

    for ($i = 0; $i -lt $fdModuleDefs.Count; $i++) {
        $mod      = $fdModuleDefs[$i]
        $row      = $fdRows[$i]
        $complete = & $mod.CompleteFn
        $running  = & $mod.RunningFn

        # ---- Module not part of this run (partial re-run) --------------------
        if ($script:fdRerunIndices.Count -gt 0 -and $i -notin $script:fdRerunIndices) {
            # Include its prior result in the overall count, then skip it.
            $w = $row.LastWorst
            if ($w -eq "fail") { $critCount++; $critNames += $mod.Name }
            elseif ($w -eq "warn") { $warnCount++; $warnNames += $mod.Name }
            continue
        }

        # ---- Module in this run - not yet done --------------------------------
        if (-not $complete) {
            $allDone = $false
            if ($running) {
                $row.Dot.BackColor       = $ColAccent
                $row.StatusLbl.Text      = "$spin  Running..."
                $row.StatusLbl.ForeColor = $ColAccent
            }
            continue
        }

        # ---- Module complete - accumulate counts ------------------------------
        $worst         = Get-WorstCardStatus $mod.CardKeys
        $row.LastWorst = $worst

        if ($worst -eq "fail") { $critCount++; $critNames += $mod.Name }
        elseif ($worst -eq "warn") { $warnCount++; $warnNames += $mod.Name }

        # Paint the row only once (ViewBtn.Enabled flips false -> true as the guard).
        if (-not $row.ViewBtn.Enabled) {
            $dotColor  = switch ($worst) { "fail"{$ColRed} "warn"{$ColYellow} "ok"{$ColGreen} default{$ColMuted} }
            $severityT = switch ($worst) { "fail"{"Critical"} "warn"{"Warning"} "ok"{"Healthy"} default{"Complete"} }

            $row.Dot.BackColor       = $dotColor
            $row.StatusLbl.Text      = $severityT
            $row.StatusLbl.ForeColor = $dotColor

            $row.ValueLbl.Text       = Get-FdModuleSummary $i $worst
            $row.ValueLbl.ForeColor  = if ($worst -in @("fail","warn")) { $ColText } else { $ColMuted }

            # Suggested action - shown only for Warning / Critical
            $action = Get-FdActionText $i $worst
            if ($action) {
                $row.ActionLbl.Text      = ">> " + $action
                $row.ActionLbl.ForeColor = if ($worst -eq "fail") { $ColRed } else { $ColYellow }
                $row.ActionLbl.Visible   = $true
            }

            # Background tint for issue rows
            if ($worst -eq "fail") {
                $row.Panel.BackColor = $ColFailBg
            } elseif ($worst -eq "warn") {
                $row.Panel.BackColor = $ColWarnBg
            }

            # Accent the View button for anything that needs attention
            if ($worst -in @("fail","warn")) {
                $row.ViewBtn.BackColor = $ColAccent
                $row.ViewBtn.ForeColor = [System.Drawing.Color]::White
            }

            $row.ViewBtn.Enabled = $true
        }
    }

    # ---- All modules done - show banner & enable buttons ---------------------
    if (-not $allDone) { return }

    $timerFullDiag.Stop()
    $elapsed = [int]((Get-Date) - $script:fdStartTime).TotalSeconds
    $lblFdSub.Text = "Completed in ${elapsed}s   |   $(Get-Date -Format 'M/d h:mm tt')"

    $totalIssues = $critCount + $warnCount
    if ($totalIssues -gt 0) {
        # --- Issues found banner ---
        $pnlFdBanner.BackColor = $ColFailBg

        $lblFdBannerIcon.Text      = [char]0xE783   # warning circle
        $lblFdBannerIcon.ForeColor = $ColRed

        # Headline: "2 critical, 1 warning detected"
        $parts = @()
        if ($critCount -gt 0) { $parts += "$critCount critical" }
        if ($warnCount -gt 0) { $parts += "$warnCount warning$(if($warnCount -ne 1){'s'})" }
        $lblFdBannerText.Text      = ($parts -join ", ") + " detected - review highlighted modules below"
        $lblFdBannerText.ForeColor = $ColRed

        # Detail line: module names + severity
        $nameList = @()
        $nameList += $critNames | ForEach-Object { "$_ (Critical)" }
        $nameList += $warnNames | ForEach-Object { "$_ (Warning)" }
        $lblFdBannerDetail.Text      = $nameList -join "   |   "
        $lblFdBannerDetail.ForeColor = [System.Drawing.Color]::FromArgb(210, 140, 140)

    } else {
        # --- All clear banner ---
        $pnlFdBanner.BackColor = $ColOkBg

        $lblFdBannerIcon.Text      = [char]0xE73E   # checkmark
        $lblFdBannerIcon.ForeColor = $ColGreen

        $lblFdBannerText.Text      = "All $($fdModuleDefs.Count) checks passed - no issues detected"
        $lblFdBannerText.ForeColor = $ColGreen

        $lblFdBannerDetail.Text      = "No action required. This VPU appears healthy."
        $lblFdBannerDetail.ForeColor = [System.Drawing.Color]::FromArgb(100, 185, 130)
    }

    $pnlFdBanner.Visible      = $true
    $btnFdRerun.Enabled       = $true
    $btnFdRerunFailed.Visible = ($totalIssues -gt 0)
    $btnFdRerunFailed.Enabled = ($totalIssues -gt 0)
})

$btnFdRerun.Add_Click({ Start-FullDiagnostic })
$btnFdRerunFailed.Add_Click({ Start-FailedDiagnostic })

# --- Partial re-run (failed / warning modules only) --------------------------
function Start-FailedDiagnostic {
    $toRerun = @()
    for ($i = 0; $i -lt $fdModuleDefs.Count; $i++) {
        if ($fdRows[$i].LastWorst -in @("fail","warn")) { $toRerun += $i }
    }
    if ($toRerun.Count -eq 0) { return }

    $script:fdRerunIndices    = $toRerun
    $pnlFdBanner.Visible      = $false
    $btnFdRerun.Enabled       = $false
    $btnFdRerunFailed.Enabled = $false
    $script:fdStartTime       = Get-Date

    # Reset only the modules being re-run
    foreach ($i in $toRerun) {
        $row = $fdRows[$i]
        $row.Dot.BackColor       = $ColMuted
        $row.StatusLbl.Text      = "Waiting"
        $row.StatusLbl.ForeColor = $ColMuted
        $row.ValueLbl.Text       = ""
        $row.ActionLbl.Text      = ""
        $row.ActionLbl.Visible   = $false
        $row.Panel.BackColor     = $ColCard
        $row.ViewBtn.Enabled     = $false
        $row.ViewBtn.BackColor   = $ColNavHover
        $row.ViewBtn.ForeColor   = $ColText
        $row.LastWorst           = "neutral"
    }

    foreach ($i in $toRerun) { Invoke-FdModule $fdModuleDefs[$i] }

    if (-not $timerFullDiag.Enabled) { $timerFullDiag.Start() }
}

# --- Full diagnostic entry point ---------------------------------------------
function Start-FullDiagnostic {
    Show-Panel $pnlFullDiag
    Set-ActiveNav $navSysOverview

    $script:fdRerunIndices    = @()
    $pnlFdBanner.Visible      = $false
    $btnFdRerun.Enabled       = $false
    $btnFdRerunFailed.Visible = $false
    $btnFdRerunFailed.Enabled = $false
    $script:fdStartTime       = Get-Date
    $script:fdSpinIdx         = 0
    $lblFdSub.Text            = "Running all checks - this takes about 60 seconds..."

    foreach ($row in $fdRows) {
        $row.Dot.BackColor       = $ColMuted
        $row.StatusLbl.Text      = "Waiting"
        $row.StatusLbl.ForeColor = $ColMuted
        $row.ValueLbl.Text       = ""
        $row.ActionLbl.Text      = ""
        $row.ActionLbl.Visible   = $false
        $row.Panel.BackColor     = $ColCard
        $row.ViewBtn.Enabled     = $false
        $row.ViewBtn.BackColor   = $ColNavHover
        $row.ViewBtn.ForeColor   = $ColText
        $row.LastWorst           = "neutral"
    }

    foreach ($mod in $fdModuleDefs) { Invoke-FdModule $mod }

    $timerFullDiag.Start()
}
$pnlReports  = New-StubPanel "Reports"  "Generate and manage diagnostic reports."
$pnlSettings = New-Object System.Windows.Forms.Panel
$pnlSettings.Size     = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlSettings.Location = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlSettings.BackColor = $ColBg; $pnlSettings.Visible = $false; $pnlSettings.Anchor = $AnchorTLRB
$form.Controls.Add($pnlSettings)

$lblSetTitle = New-Object System.Windows.Forms.Label; $lblSetTitle.Text = "Settings"
$lblSetTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblSetTitle.ForeColor = $ColText
$lblSetTitle.Location = New-Object System.Drawing.Point(10,16); $lblSetTitle.AutoSize = $true
$pnlSettings.Controls.Add($lblSetTitle)

$lblSetSub = New-Object System.Windows.Forms.Label
$lblSetSub.Text = "Configure tool options."
$lblSetSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblSetSub.ForeColor = $ColMuted
$lblSetSub.Location = New-Object System.Drawing.Point(10,42); $lblSetSub.AutoSize = $true
$pnlSettings.Controls.Add($lblSetSub)

$sepSetTop = New-Object System.Windows.Forms.Panel
$sepSetTop.Size = New-Object System.Drawing.Size(1240,1); $sepSetTop.Location = New-Object System.Drawing.Point(10,68)
$sepSetTop.BackColor = $ColBorder; $pnlSettings.Controls.Add($sepSetTop)

$lblSetAppearance = New-Object System.Windows.Forms.Label; $lblSetAppearance.Text = "Appearance"
$lblSetAppearance.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblSetAppearance.ForeColor = $ColText
$lblSetAppearance.Location = New-Object System.Drawing.Point(10,82); $lblSetAppearance.AutoSize = $true
$pnlSettings.Controls.Add($lblSetAppearance)

$lblSetThemeName = New-Object System.Windows.Forms.Label; $lblSetThemeName.Text = "Theme"
$lblSetThemeName.Font = New-Object System.Drawing.Font("Segoe UI",9); $lblSetThemeName.ForeColor = $ColText
$lblSetThemeName.Location = New-Object System.Drawing.Point(10,112); $lblSetThemeName.AutoSize = $true
$pnlSettings.Controls.Add($lblSetThemeName)

$lblSetThemeDesc = New-Object System.Windows.Forms.Label
$lblSetThemeDesc.Text = "Current: $(if($VpuTheme -eq 'light'){'Light'}else{'Dark'}) Mode.  Switching restarts the application."
$lblSetThemeDesc.Font = New-Object System.Drawing.Font("Segoe UI",8); $lblSetThemeDesc.ForeColor = $ColMuted
$lblSetThemeDesc.Location = New-Object System.Drawing.Point(10,132); $lblSetThemeDesc.AutoSize = $true
$pnlSettings.Controls.Add($lblSetThemeDesc)

$btnSetTheme = New-Object System.Windows.Forms.Button
$btnSetTheme.Text = if ($VpuTheme -eq "light") { "  Switch to Dark Mode" } else { "  Switch to Light Mode" }
$btnSetTheme.Size = New-Object System.Drawing.Size(200,40); $btnSetTheme.Location = New-Object System.Drawing.Point(10,162)
$btnSetTheme.BackColor = $ColAccent; $btnSetTheme.ForeColor = [System.Drawing.Color]::White
$btnSetTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnSetTheme.FlatAppearance.BorderSize = 0
$btnSetTheme.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $btnSetTheme.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnSetTheme.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,200,40)),6))
$pnlSettings.Controls.Add($btnSetTheme)
$btnSetTheme.Add_Click({
    $newTheme = if ($VpuTheme -eq "dark") { "light" } else { "dark" }
    try { [System.IO.File]::WriteAllText($SettingsPath, "{`"Theme`":`"$newTheme`"}") } catch { }
    $runScript = if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $PSCommandPath } else { Join-Path $PSScriptRoot "Run.ps1" }
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`""
    $form.Close()
})

# ---- Completion Toast -------------------------------------------------------
# Floating notification anchored top-right; shown by the watcher timer below.
$pnlToast = New-Object System.Windows.Forms.Panel
$pnlToast.Size      = New-Object System.Drawing.Size(430, 62)
$pnlToast.Location  = New-Object System.Drawing.Point(840, ([int]$ContentY + 10))
$pnlToast.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 46)
$pnlToast.Visible   = $false
$pnlToast.Anchor    = $AnchorTR
$form.Controls.Add($pnlToast)
$pnlToast.BringToFront()

$pnlToast.Add_Paint({
    $g = $args[1].Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $bp  = [GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ([int]$this.Width - 1), ([int]$this.Height - 1))), 8)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(51, 65, 85), 1)
    $g.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
})

$pnlToastAccent = New-Object System.Windows.Forms.Panel
$pnlToastAccent.Size      = New-Object System.Drawing.Size(5, 62)
$pnlToastAccent.Location  = New-Object System.Drawing.Point(0, 0)
$pnlToastAccent.BackColor = $ColGreen
$pnlToast.Controls.Add($pnlToastAccent)

$lblToastIcon = New-Object System.Windows.Forms.Label
$lblToastIcon.Text      = [char]0xE73E
$lblToastIcon.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 18)
$lblToastIcon.ForeColor = $ColGreen
$lblToastIcon.Location  = New-Object System.Drawing.Point(16, 12)
$lblToastIcon.Size      = New-Object System.Drawing.Size(36, 36)
$lblToastIcon.BackColor = [System.Drawing.Color]::Transparent
$pnlToast.Controls.Add($lblToastIcon)

$lblToastText = New-Object System.Windows.Forms.Label
$lblToastText.Text      = ""
$lblToastText.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
$lblToastText.ForeColor = $ColGreen
$lblToastText.Location  = New-Object System.Drawing.Point(60, 9)
$lblToastText.Size      = New-Object System.Drawing.Size(330, 24)
$lblToastText.BackColor = [System.Drawing.Color]::Transparent
$pnlToast.Controls.Add($lblToastText)

$lblToastSub = New-Object System.Windows.Forms.Label
$lblToastSub.Text      = ""
$lblToastSub.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblToastSub.ForeColor = $ColMuted
$lblToastSub.Location  = New-Object System.Drawing.Point(60, 34)
$lblToastSub.Size      = New-Object System.Drawing.Size(330, 16)
$lblToastSub.BackColor = [System.Drawing.Color]::Transparent
$pnlToast.Controls.Add($lblToastSub)

$btnToastDismiss = New-Object System.Windows.Forms.Button
$btnToastDismiss.Text      = [char]0xE711  # MDL2 Cancel/X glyph
$btnToastDismiss.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 8)
$btnToastDismiss.ForeColor = $ColMuted
$btnToastDismiss.BackColor = [System.Drawing.Color]::Transparent
$btnToastDismiss.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnToastDismiss.FlatAppearance.BorderSize = 0
$btnToastDismiss.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(44, 59, 80)
$btnToastDismiss.Size      = New-Object System.Drawing.Size(24, 24)
$btnToastDismiss.Location  = New-Object System.Drawing.Point(398, 4)
$btnToastDismiss.Cursor    = [System.Windows.Forms.Cursors]::Hand
$pnlToast.Controls.Add($btnToastDismiss)
$btnToastDismiss.Add_Click({ $pnlToast.Visible = $false })

# Watcher timer - fires every 400ms, shows toast when any module completes
$toastPrevState = @{
    Complete=0; NetComplete=0; SvcComplete=0; DiskComplete=0
    EvtComplete=0; HwComplete=0; SysInfoComplete=0
}
$toastModuleMeta = @{
    Complete        = @{ Name="Camera Connectivity";    AllClearKey="AllClear";    CardKeys=@() }
    NetComplete     = @{ Name="Network Configuration";  AllClearKey="NetAllClear"; CardKeys=@() }
    SvcComplete     = @{ Name="Pixellot Services";      AllClearKey=$null;         CardKeys=@("SvcStatus") }
    DiskComplete    = @{ Name="Disk Health";            AllClearKey=$null;         CardKeys=@("DiskStatus","MemStatus") }
    EvtComplete     = @{ Name="Event Logs";             AllClearKey=$null;         CardKeys=@("EvtStatus") }
    HwComplete      = @{ Name="VPU Hardware";           AllClearKey=$null;         CardKeys=@("HwGpu","HwMonitor","HwMmk") }
    SysInfoComplete = @{ Name="System Information";     AllClearKey=$null;         CardKeys=@() }
}

$timerToast = New-Object System.Windows.Forms.Timer
$timerToast.Interval = 400
$timerToast.Add_Tick({
    # Auto-hide when any new run starts
    $anyRunning = $sync.Running -or $sync.NetRunning -or $sync.SvcRunning -or
                  $sync.DiskRunning -or $sync.EvtRunning -or $sync.HwRunning -or $sync.SysInfoRunning
    if ($anyRunning -and $pnlToast.Visible) { $pnlToast.Visible = $false }

    foreach ($key in $toastModuleMeta.Keys) {
        $nowDone = $sync[$key] -eq $true
        if ($nowDone -and ($toastPrevState[$key] -eq 0)) {
            $toastPrevState[$key] = 1
            $meta = $toastModuleMeta[$key]

            # Determine pass/warn/fail
            $isOk = $true; $isWarn = $false
            if ($meta.AllClearKey) {
                $isOk = $sync[$meta.AllClearKey] -eq $true
            } elseif ($meta.CardKeys.Count -gt 0) {
                $anyFail = @($meta.CardKeys | Where-Object { $sync.Cards[$_].Status -eq "fail" })
                $anyWarn = @($meta.CardKeys | Where-Object { $sync.Cards[$_].Status -eq "warn" })
                $isOk    = $anyFail.Count -eq 0
                $isWarn  = $isOk -and $anyWarn.Count -gt 0
            }

            $clr  = if ($isOk -and -not $isWarn) { $ColGreen } elseif ($isWarn) { $ColYellow } else { $ColRed }
            $icon = if ($isOk -and -not $isWarn) { [char]0xE73E } elseif ($isWarn) { [char]0xE7BA } else { [char]0xEA39 }
            $msg  = "$($meta.Name)  -  " + $(if ($isOk -and -not $isWarn) { "All Clear" } elseif ($isWarn) { "Warning" } else { "Issues Found" })
            $sub  = "Completed $(Get-Date -Format 'h:mm:ss tt')   |   Click X to dismiss"

            $pnlToastAccent.BackColor = $clr
            $lblToastIcon.Text        = $icon
            $lblToastIcon.ForeColor   = $clr
            $lblToastText.Text        = $msg
            $lblToastText.ForeColor   = $clr
            $lblToastSub.Text         = $sub
            $pnlToast.Visible         = $true
            $pnlToast.BringToFront()
        }
        # Reset state when module resets (new run)
        if (-not $sync[$key] -and ($toastPrevState[$key] -eq 1)) {
            $toastPrevState[$key] = 0
        }
    }
})
$timerToast.Start()

# ---------- Nav panel registry (must be after all panels created) ------------
$script:allNavPanels = @(
    $pnlSysOverview,$center,$pnlGuide,$pnlHistory,$pnlHelp,$pnlNetwork,
    $pnlPoE,$pnlServices,$pnlDisk,$pnlEvents,$pnlReports,$pnlSettings,$pnlSysInfo,
    $pnlFullDiag
)

# ---------- Nav click handlers -----------------------------------------------
$navSysOverview.Add_Click({ Show-Panel $pnlSysOverview; Set-ActiveNav $navSysOverview })
$navSysInfo.Add_Click({     Show-Panel $pnlSysInfo;     Set-ActiveNav $navSysInfo })
$navNetConfig.Add_Click({   Show-Panel $pnlNetwork;     Set-ActiveNav $navNetConfig })
$navCamera.Add_Click({      Show-Panel $center $true;   Set-ActiveNav $navCamera; Show-OverviewSteps })
$navPoE.Add_Click({         Show-Panel $pnlPoE;         Set-ActiveNav $navPoE })
$navServices.Add_Click({    Show-Panel $pnlServices;    Set-ActiveNav $navServices })
$navDisk.Add_Click({        Show-Panel $pnlDisk;        Set-ActiveNav $navDisk })
$navEvents.Add_Click({      Show-Panel $pnlEvents;      Set-ActiveNav $navEvents })
$navReports.Add_Click({     Show-Panel $pnlHistory;     Set-ActiveNav $navReports; Update-HistoryList })
$navSettings.Add_Click({    Show-Panel $pnlSettings;    Set-ActiveNav $navSettings })
$navAbout.Add_Click({       Show-Panel $pnlHelp;        Set-ActiveNav $navAbout })
$navOverview.Add_Click({    $navCamera.PerformClick() })
$navHistory.Add_Click({     $navReports.PerformClick() })
$navHelp.Add_Click({        $navAbout.PerformClick() })
$btnTabFullDiag.Add_Click({ Start-FullDiagnostic })

# ---------- Form Load -------------------------------------------------------
$form.Add_Load({
    $cboNic.Items.Add("All Ports") | Out-Null
    try {
        foreach ($n in $script:detectedNics) {
            $short = $n.InterfaceDescription -replace 'Intel\(R\) 82574L Gigabit Network Connection','CHU NIC'
            $short = $short -replace 'Intel\(R\) I210 Gigabit Network Connection','CHU NIC'
            $cboNic.Items.Add("$($n.Name)  ($short)") | Out-Null
            $cboGuidePortA.Items.Add($n.Name) | Out-Null
        }
        $script:nicCardInfo = Get-AdlinkCardInfo $script:detectedNics
        $lblNicCardVal.Text = $script:nicCardInfo.Label
    } catch { }
    if ($cboNic.Items.Count -gt 0) { $cboNic.SelectedIndex = 0 }
    if ($cboGuidePortA.Items.Count -gt 0) { $cboGuidePortA.SelectedIndex = 0 }
    Update-GuideStepDots -ActivePhase 1
    Set-ActiveNav $navSysOverview

    try {
        $osCaption = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        if ($osCaption) { $lblVpuVal.Text = "$($env:COMPUTERNAME)  .  $($osCaption -replace 'Microsoft Windows ','Win ')" }
    } catch { }

    # Async update check - compares remote $ScriptVersion to current; shows notice if newer
    try {
        $wc = New-Object System.Net.WebClient
        if ($env:VPU_DEPLOY_TOKEN) { $wc.Headers.Add("Authorization", "Bearer $env:VPU_DEPLOY_TOKEN") }
        Register-ObjectEvent -InputObject $wc -EventName DownloadStringCompleted `
            -MessageData @{ Sync = $sync; CurVer = $ScriptVersion } -Action {
            try {
                $data = $Event.MessageData
                if (-not $EventArgs.Error -and
                    $EventArgs.Result -match '\$ScriptVersion\s*=\s*"(\d+\.\d+\.\d+)"') {
                    if ([version]$Matches[1] -gt [version]$data.CurVer) {
                        $data.Sync.UpdateAvailable = $Matches[1]
                    }
                }
            } catch { }
        } | Out-Null
        $rawUrl = "https://raw.githubusercontent.com/ianmoore-playon/vpu-diagnostic-tools/refs/heads/main/Pulse.ps1"
        $wc.DownloadStringAsync([uri]$rawUrl)
    } catch { }
})

$form.Add_FormClosing({
    $timer.Stop(); $netTimer.Stop(); $svcTimer.Stop(); $diskTimer.Stop(); $evtTimer.Stop(); $hwTimer.Stop(); $sysInfoTimer.Stop(); $timerToast.Stop()
    $sync.Cancelled=$true; $sync.NetCancelled=$true; $sync.SvcCancelled=$true; $sync.DiskCancelled=$true; $sync.EvtCancelled=$true; $sync.HwCancelled=$true; $sync.SysInfoCancelled=$true
    try { if ($script:runspace)    { $script:runspace.Close();    $script:runspace.Dispose()    } } catch { }
    try { if ($script:netRunspace) { $script:netRunspace.Close(); $script:netRunspace.Dispose() } } catch { }
    try { if ($script:svcRunspace) { $script:svcRunspace.Close(); $script:svcRunspace.Dispose() } } catch { }
    try { if ($script:diskRunspace){ $script:diskRunspace.Close();$script:diskRunspace.Dispose()} } catch { }
    try { if ($script:evtRunspace) { $script:evtRunspace.Close(); $script:evtRunspace.Dispose() } } catch { }
    try { if ($script:hwRunspace)      { $script:hwRunspace.Close();      $script:hwRunspace.Dispose()      } } catch { }
    try { if ($script:sysInfoRunspace) { $script:sysInfoRunspace.Close(); $script:sysInfoRunspace.Dispose() } } catch { }
})

[System.Windows.Forms.Application]::Run($form)
try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
