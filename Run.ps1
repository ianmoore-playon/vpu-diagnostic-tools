# =============================================================================
#  Pulse.ps1  -  Pulse - Pixellot Unified Live System Evaluator
#  Loads modules from .\Modules\ and runs the GUI.
#
#  HOW TO RUN: double-click "Pulse.bat"  (handles elevation automatically)
# =============================================================================

$ScriptVersion = "1.0.53"

# ---------- Self-elevation ---------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevArgs = "-NoProfile -ExecutionPolicy Bypass"
    if ($PSCommandPath) {
        Start-Process PowerShell -Verb RunAs -ArgumentList "$elevArgs -File `"$PSCommandPath`""
    }
    exit
}

# ---------- Network defaults -------------------------------------------------
# Force TLS 1.2 (preserve any higher protocols already enabled). Older VPU images
# default to TLS 1.0/1.1 which GitHub no longer accepts, breaking update checks.
[System.Net.ServicePointManager]::SecurityProtocol = `
    [System.Net.SecurityProtocolType]::Tls12 -bor `
    [System.Net.ServicePointManager]::SecurityProtocol

# Self-update download URL — used by the CameraConnectivity Update Now button.
$global:ScriptUrl = "https://raw.githubusercontent.com/ianmoore-playon/vpu-diagnostic-tools/refs/heads/main/Run.ps1"

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

# ---------- Pixellot camera role lookup --------------------------------------
# The authoritative source for "which IP / MAC is which role" is Pixellot's
# own configuration files in C:\Pixellot\Data\configuration. The agent reads
# these on startup and pushes the resolved cameraInfo to its backend, so the
# data here always matches what Pixellot's own HW Info screen shows.
#
# File format is NOT standard INI — it's:
#     [SECTION]
#     KEY_NAME, type, value      // optional inline comment
#
# We care about these sections:
#     cameras.cfg  [CAMERA_0..N]            UID = rtsp:////<IP>/h264
#     cameras.cfg  [ADDITIONAL_ANGLE_0..N]  UID = rtsp:////<IP>/h264
#     pip.cfg      [PIP]                    CAMERA_URL = rtsp:////<IP>/h264
$PixellotConfigDir = "C:\Pixellot\Data\configuration"

function Read-PixellotCfg {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return $result }
    $section = $null
    foreach ($raw in (Get-Content $Path -ErrorAction SilentlyContinue)) {
        $line = $raw.Trim()
        if (-not $line) { continue }
        # Strip full-line comments first.
        if ($line.StartsWith('//')) { continue }
        # Strip trailing inline comments. We can't bare-match '//' because
        # values like `rtsp:////169.254.16.50/h264` contain `//` inside the
        # URL; in Pixellot's .cfg format actual comments are always preceded
        # by whitespace, so we look for ` //` (or tab + //) and split there.
        $m = [regex]::Match($line, '\s+//')
        if ($m.Success) { $line = $line.Substring(0, $m.Index).Trim() }
        if (-not $line) { continue }
        if ($line -match '^\[(.+)\]$') {
            $section = $matches[1].Trim()
            if (-not $result.ContainsKey($section)) { $result[$section] = @{} }
            continue
        }
        if (-not $section) { continue }
        # KEY, type, value  — split into max 3 parts so values can contain commas.
        $parts = $line -split ',', 3
        if ($parts.Count -ge 3) {
            $key = $parts[0].Trim()
            $val = $parts[2].Trim().Trim('"')
            if ($key) { $result[$section][$key] = $val }
        }
    }
    return $result
}

function Get-PixellotIpFromRtsp {
    param([string]$Url)
    if (-not $Url) { return $null }
    # rtsp://host/path  or  rtsp:////host/path  (Pixellot uses 4 slashes)
    if ($Url -match 'rtsp:/+([^/:]+)') {
        $h = $matches[1]
        if ($h -match '^\d+\.\d+\.\d+\.\d+$') { return $h }
    }
    return $null
}

# Build a hashtable mapping IP → role string by parsing cameras.cfg + pip.cfg.
# Returns @{} when the config dir doesn't exist (non-Pixellot machine, or
# install path differs) — callers fall back to OUI-based heuristics.
function Get-PixellotCameraRoles {
    $roles = @{}
    $camsCfg = Read-PixellotCfg (Join-Path $PixellotConfigDir "cameras.cfg")
    foreach ($section in $camsCfg.Keys) {
        if ($section -match '^CAMERA_(\d+)$') {
            $idx = [int]$matches[1]
            $ip  = Get-PixellotIpFromRtsp $camsCfg[$section]['UID']
            if ($ip) { $roles[$ip] = "Main Camera $($idx + 1)" }
        } elseif ($section -match '^ADDITIONAL_ANGLE_(\d+)$') {
            $idx = [int]$matches[1]
            $ip  = Get-PixellotIpFromRtsp $camsCfg[$section]['UID']
            if ($ip) { $roles[$ip] = "Additional Angle $($idx + 1)" }
        } elseif ($section -eq 'PIP') {
            # Some Pixellot installs put the PIP section in cameras.cfg
            $ip = Get-PixellotIpFromRtsp $camsCfg[$section]['CAMERA_URL']
            if ($ip) { $roles[$ip] = "OCR / Scoreboard" }
        }
    }
    # Standard location for the PIP section
    $pipCfg = Read-PixellotCfg (Join-Path $PixellotConfigDir "pip.cfg")
    if ($pipCfg.ContainsKey('PIP')) {
        $ip = Get-PixellotIpFromRtsp $pipCfg['PIP']['CAMERA_URL']
        if ($ip) { $roles[$ip] = "OCR / Scoreboard" }
    }
    return $roles
}

# Initialised once at startup; refreshed when the Camera Connectivity panel
# becomes visible so role changes (e.g. tech swaps a camera and the agent
# rewrites cameras.cfg) are picked up without restarting Pulse.
$script:PixCameraRoles = Get-PixellotCameraRoles

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
        [string]$PrimaryText = "Run Test"
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
        SiModel     = @{ Value = "--"; Status = "neutral" }
        SiOs        = @{ Value = "--"; Status = "neutral" }
        SiUptime    = @{ Value = "--"; Status = "neutral" }
        SiCpu       = @{ Value = "--"; Status = "neutral" }
        SiRam       = @{ Value = "--"; Status = "neutral" }
        SiStorage   = @{ Value = "--"; Status = "neutral" }
        DiskSmart   = @{ Value = "--"; Status = "neutral" }
        DiskErrors  = @{ Value = "--"; Status = "neutral" }
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
# v1.0.42 redesign: 1500x800 to accommodate the 220-wide left sidebar without
# shrinking the content area (was 1280x760 with 0-wide sidebar + top tab bar).
# v1.0.49: bumped to 1600 wide so the Camera Connectivity diagram + status row
# has breathing room next to the right-anchored NIC Info / Legend sidebar.
# v1.0.52: clamp to the screen working area at startup so VPUs with
# 1366x768 / 1440x900 monitors don't open with the right edge off-screen.
# AutoScrollMinSize keeps the *layout* at the design size; if the form is
# smaller than that, scrollbars appear so every panel stays reachable.
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$desiredW = [Math]::Min(1600, [Math]::Max(1280, $wa.Width  - 16))
$desiredH = [Math]::Min(900,  [Math]::Max(720,  $wa.Height - 32))
$form.ClientSize  = New-Object System.Drawing.Size($desiredW, $desiredH)
# MinimumSize is the *outer* size including chrome (~16px borders + ~40px caption).
$form.MinimumSize = New-Object System.Drawing.Size(1296, 760)
$form.AutoScroll        = $true
$form.AutoScrollMinSize = New-Object System.Drawing.Size(1600, 800)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $ColBg
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
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

# Layout constants - v1.0.42 redesign uses left sidebar instead of top tab bar.
# $HdrH and $TabH are kept at 0 for backwards compat with existing modules that
# computed $ContentY = $HdrH + $TabH; new value is just 0.
[int]$HdrH     = 0
[int]$TabH     = 0
[int]$SbarH    = 32
[int]$SideW    = 220                            # left sidebar width
[int]$ContentX = $SideW
[int]$ContentY = 0
[int]$ContentH = 800 - $SbarH                   # 768
[int]$ContentW = 1600 - $SideW                  # 1380 (v1.0.49: form widened from 1500 to 1600)
[int]$WideW    = $ContentW
[int]$NarrowW  = $ContentW
[int]$RightX   = $ContentW
[int]$RightW   = 0

# ---- Left Sidebar (v1.0.42 redesign) ---------------------------------------
# Replaces the old top header + tab bar combo. All nav lives here, plus the
# product brand at the top and Settings/About pinned to the bottom.
$pnlSidebar = New-Object System.Windows.Forms.Panel
$pnlSidebar.Size      = New-Object System.Drawing.Size($SideW, ($form.ClientSize.Height - $SbarH))
$pnlSidebar.Location  = New-Object System.Drawing.Point(0, 0)
$pnlSidebar.BackColor = $ColSidebar
$pnlSidebar.Anchor    = $AnchorTLB
$form.Controls.Add($pnlSidebar)

# Right-edge separator between sidebar and content
$sepSidebar = New-Object System.Windows.Forms.Panel
$sepSidebar.Size      = New-Object System.Drawing.Size(1, ($form.ClientSize.Height - $SbarH))
$sepSidebar.Location  = New-Object System.Drawing.Point(($SideW - 1), 0)
$sepSidebar.BackColor = $ColBorder
$sepSidebar.Anchor    = $AnchorTLB
$form.Controls.Add($sepSidebar)

# Brand block at top of sidebar — icon + "Pulse" + product tagline
$lblSbIcon = New-Object System.Windows.Forms.Label
$lblSbIcon.Text      = [char]0xF785
$lblSbIcon.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 18)
$lblSbIcon.ForeColor = $ColAccent
$lblSbIcon.Location  = New-Object System.Drawing.Point(16, 18)
$lblSbIcon.Size      = New-Object System.Drawing.Size(32, 32)
$pnlSidebar.Controls.Add($lblSbIcon)

$lblSbBrand = New-Object System.Windows.Forms.Label
$lblSbBrand.Text      = "Pulse"
$lblSbBrand.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
$lblSbBrand.ForeColor = [System.Drawing.Color]::White
$lblSbBrand.Location  = New-Object System.Drawing.Point(54, 19)
$lblSbBrand.Size      = New-Object System.Drawing.Size(140, 22)
$pnlSidebar.Controls.Add($lblSbBrand)

$lblSbBrandSub = New-Object System.Windows.Forms.Label
$lblSbBrandSub.Text      = "VPU Diagnostics"
$lblSbBrandSub.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblSbBrandSub.ForeColor = [System.Drawing.Color]::FromArgb(110, 128, 155)
$lblSbBrandSub.Location  = New-Object System.Drawing.Point(54, 41)
$lblSbBrandSub.Size      = New-Object System.Drawing.Size(140, 14)
$pnlSidebar.Controls.Add($lblSbBrandSub)

# Divider under the brand block
$sepBrand = New-Object System.Windows.Forms.Panel
$sepBrand.Size      = New-Object System.Drawing.Size(($SideW - 24), 1)
$sepBrand.Location  = New-Object System.Drawing.Point(12, 70)
$sepBrand.BackColor = $ColBorder
$pnlSidebar.Controls.Add($sepBrand)

# Build nav buttons. Each row: icon + label, full sidebar width, with active state
# (left blue accent + slightly lighter background) drawn in a custom Paint.
$script:sbNavButtons = @()
function New-SidebarNavButton {
    param([string]$Label, [int]$IconCode, [int]$Y)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Size      = New-Object System.Drawing.Size($SideW, 40)
    $btn.Location  = New-Object System.Drawing.Point(0, $Y)
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
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $tag = $s.Tag
        # Active accent strip on the left
        if ($tag.Active) {
            $accentBrush = New-Object System.Drawing.SolidBrush($ColAccent)
            $g.FillRectangle($accentBrush, 0, 0, 3, $s.Height)
            $accentBrush.Dispose()
        }
        # Icon
        $iconColor = if ($tag.Active) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(148,163,184) }
        $iconFont  = New-Object System.Drawing.Font("Segoe MDL2 Assets", 11.5)
        $iconBrush = New-Object System.Drawing.SolidBrush($iconColor)
        $g.DrawString($tag.Icon, $iconFont, $iconBrush, 18, 11)
        $iconFont.Dispose(); $iconBrush.Dispose()
        # Label
        $textColor = if ($tag.Active) { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(180,195,215) }
        $labelFont = if ($tag.Active) { New-Object System.Drawing.Font("Segoe UI Semibold", 9.5) } else { New-Object System.Drawing.Font("Segoe UI", 9.5) }
        $labelBrush = New-Object System.Drawing.SolidBrush($textColor)
        $g.DrawString($tag.Label, $labelFont, $labelBrush, 46, 12)
        $labelFont.Dispose(); $labelBrush.Dispose()
    })
    $script:sbNavButtons += $btn
    return $btn
}

$sbNavY = 86
$navSysOverview = New-SidebarNavButton "System Overview"        0xE80F $sbNavY; $sbNavY += 42
$navNetConfig   = New-SidebarNavButton "Network Configuration"  0xE701 $sbNavY; $sbNavY += 42
$navCamera      = New-SidebarNavButton "Camera Connectivity"    0xE722 $sbNavY; $sbNavY += 42
$navPoE         = New-SidebarNavButton "Hardware & Peripherals" 0xE7E8 $sbNavY; $sbNavY += 42
$navServices    = New-SidebarNavButton "Pixellot Services"      0xE9F5 $sbNavY; $sbNavY += 42
$navDisk        = New-SidebarNavButton "Disk & System Health"   0xEDA2 $sbNavY; $sbNavY += 42
$navSysInfo     = New-SidebarNavButton "System Information"     0xE9A0 $sbNavY; $sbNavY += 42
$navEvents      = New-SidebarNavButton "Event Viewer"           0xE7BA $sbNavY; $sbNavY += 42
$navReports     = New-SidebarNavButton "Reports"                0xE7C3 $sbNavY; $sbNavY += 42

# Settings + About pinned near the bottom of the sidebar
$navSettings    = New-SidebarNavButton "Settings"               0xE713 ($form.ClientSize.Height - $SbarH - 96)
$navAbout       = New-SidebarNavButton "About"                  0xE946 ($form.ClientSize.Height - $SbarH - 54)
$navSettings.Anchor = $AnchorBL
$navAbout.Anchor    = $AnchorBL

# Hidden compat buttons — older module code (CameraConnectivity, etc.) still calls
# $navOverview / $navTests / $navHistory / $navHelp by name and adds its own Click
# handlers. Aliasing these to the visible nav buttons would cause infinite recursion
# (the handler on the alias calls PerformClick() on the same physical button it's
# attached to). So they're separate hidden buttons whose Click forwards to the real
# nav buttons.
$navOverview = New-Object System.Windows.Forms.Button; $navOverview.Visible = $false; $navOverview.Size = New-Object System.Drawing.Size(0, 0)
$navTests    = New-Object System.Windows.Forms.Button; $navTests.Visible    = $false; $navTests.Size    = New-Object System.Drawing.Size(0, 0)
$navHistory  = New-Object System.Windows.Forms.Button; $navHistory.Visible  = $false; $navHistory.Size  = New-Object System.Drawing.Size(0, 0)
$navHelp     = New-Object System.Windows.Forms.Button; $navHelp.Visible     = $false; $navHelp.Size     = New-Object System.Drawing.Size(0, 0)
$form.Controls.AddRange(@($navOverview, $navTests, $navHistory, $navHelp))

$pnlSidebar.Controls.AddRange($script:sbNavButtons)

# ---- Tab hover tooltips ----------------------------------------------------
$tabTip = New-Object System.Windows.Forms.ToolTip
$tabTip.AutoPopDelay = 8000
$tabTip.InitialDelay = 550
$tabTip.ReshowDelay  = 300
$tabTip.ShowAlways   = $true
$tabTip.SetToolTip($navSysOverview, "Home dashboard with all module tiles and Run Full Diagnostic")
$tabTip.SetToolTip($navSysInfo,     "CPU, RAM, GPU, storage, and network adapter inventory")
$tabTip.SetToolTip($navNetConfig,   "Internet access, required port connectivity, and DNS resolution for Pixellot services")
$tabTip.SetToolTip($navCamera,      "Camera NIC link speeds, cable-fault detection, ping/RTSP checks, and PoE power budget")
$tabTip.SetToolTip($navServices,    "Running status of Pixellot agent, encoder, and support services")
$tabTip.SetToolTip($navPoE,         "GPU, monitor, input devices, PoE budget, and NIC link uptime (NIC port layout lives on Camera Connectivity)")
$tabTip.SetToolTip($navDisk,        "Drive free space, disk health, and system memory availability")
$tabTip.SetToolTip($navEvents,      "Recent OS system errors filtered for hardware and service-related issues")
$tabTip.SetToolTip($navReports,     "View, copy, or export previously saved diagnostic reports")
$tabTip.SetToolTip($navSettings,    "Theme and application settings")
$tabTip.SetToolTip($navAbout,       "Help and version information")

# Tab-bar Run Diagnostic button removed — primary action is now per-panel.
# Define a hidden compat button so $btnTabFullDiag.Add_Click in module wiring still works.
$btnTabFullDiag = New-Object System.Windows.Forms.Button
$btnTabFullDiag.Visible = $false
$btnTabFullDiag.Size    = New-Object System.Drawing.Size(0, 0)
$form.Controls.Add($btnTabFullDiag)

# ---- Bottom Status Bar -----------------------------------------------------
$pnlStatusBar = New-Object System.Windows.Forms.Panel
$pnlStatusBar.Size      = New-Object System.Drawing.Size(1500, $SbarH)
$pnlStatusBar.Location  = New-Object System.Drawing.Point(0, ($form.ClientSize.Height - $SbarH))
$pnlStatusBar.BackColor = [System.Drawing.Color]::FromArgb(15, 22, 36)
$pnlStatusBar.Anchor    = $AnchorBLR
$form.Controls.Add($pnlStatusBar)

# Top border on the status bar for separation
$sepSbar = New-Object System.Windows.Forms.Panel
$sepSbar.Size      = New-Object System.Drawing.Size(1500, 1)
$sepSbar.Location  = New-Object System.Drawing.Point(0, 0)
$sepSbar.BackColor = $ColBorder
$sepSbar.Anchor    = $AnchorTLR
$pnlStatusBar.Controls.Add($sepSbar)

$pnlSbarDot = New-Object System.Windows.Forms.Panel
$pnlSbarDot.Size      = New-Object System.Drawing.Size(8, 8)
$pnlSbarDot.Location  = New-Object System.Drawing.Point(14, ($SbarH / 2 - 4))
$pnlSbarDot.BackColor = $ColGreen
$pnlSbarDot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
$pnlStatusBar.Controls.Add($pnlSbarDot)

$lblSbarStatus = New-Object System.Windows.Forms.Label
$lblSbarStatus.Text      = "Status: Ready"
$lblSbarStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSbarStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 195, 215)
$lblSbarStatus.Location  = New-Object System.Drawing.Point(28, 0)
$lblSbarStatus.Size      = New-Object System.Drawing.Size(220, $SbarH)
$lblSbarStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlStatusBar.Controls.Add($lblSbarStatus)

$lblSbarLastRun = New-Object System.Windows.Forms.Label
$lblSbarLastRun.Text      = "Last Run: Never"
$lblSbarLastRun.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSbarLastRun.ForeColor = [System.Drawing.Color]::FromArgb(120, 138, 165)
$lblSbarLastRun.Location  = New-Object System.Drawing.Point(260, 0)
$lblSbarLastRun.Size      = New-Object System.Drawing.Size(420, $SbarH)
$lblSbarLastRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$pnlStatusBar.Controls.Add($lblSbarLastRun)

$lblHdrVer = New-Object System.Windows.Forms.Label
$lblHdrVer.Text      = "Tool Version: $ScriptVersion"
$lblHdrVer.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblHdrVer.ForeColor = [System.Drawing.Color]::FromArgb(120, 138, 165)
$lblHdrVer.Size      = New-Object System.Drawing.Size(180, $SbarH)
$lblHdrVer.Location  = New-Object System.Drawing.Point(1304, 0)
$lblHdrVer.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblHdrVer.Anchor    = $AnchorTR
$pnlStatusBar.Controls.Add($lblHdrVer)

# Stub for legacy $pnlHeader / $pnlBadge references so module code that pokes them
# (e.g. update-banner buttons) doesn't crash. Both are off-screen and zero-sized.
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Size = New-Object System.Drawing.Size(0, 0); $pnlHeader.Visible = $false
$form.Controls.Add($pnlHeader)
$pnlBadge      = New-Object System.Windows.Forms.Panel; $pnlBadge.Visible = $false; $pnlBadge.Size = New-Object System.Drawing.Size(0,0)
$pnlBadgeDot   = New-Object System.Windows.Forms.Panel; $pnlBadgeDot.Visible = $false; $pnlBadgeDot.Size = New-Object System.Drawing.Size(0,0)
$lblBadge      = New-Object System.Windows.Forms.Label; $lblBadge.Visible = $false
$lblHdrTitle   = New-Object System.Windows.Forms.Label; $lblHdrTitle.Visible = $false
$lblHdrSub     = New-Object System.Windows.Forms.Label; $lblHdrSub.Visible = $false
$lblHdrIcon    = New-Object System.Windows.Forms.Label; $lblHdrIcon.Visible = $false

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
    $tLbl.AutoEllipsis = $true
    $pnl.Controls.Add($tLbl)

    $dLbl = New-Object System.Windows.Forms.Label
    $dLbl.Text      = $Desc
    $dLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $dLbl.ForeColor = $ColMuted
    $dLbl.Location  = New-Object System.Drawing.Point(20, 122)
    $dLbl.Size      = New-Object System.Drawing.Size(([int]$W - 28), 56)
    $dLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($dLbl)

    # Stash inner-label refs on the panel Tag so Update-HubTileLayout can
    # resize them when the tile width changes. Without this, the labels
    # stay at their initial (W-28) = 72px width and titles like
    # "Hardware & Peripherals" get truncated to "Hardwar".
    $pnl.Tag | Add-Member -NotePropertyName TitleLbl -NotePropertyValue $tLbl -Force
    $pnl.Tag | Add-Member -NotePropertyName DescLbl  -NotePropertyValue $dLbl -Force

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
    @{ Nav="navPoE";        Title="Hardware & Peripherals"; Desc="GPU, monitor, input devices, PoE budget, and NIC link uptime";       Icon=0xE7E8; Color=$emerald;    R=1; C=0 }
    @{ Nav="navDisk";       Title="System & Disk Health";   Desc="Free space, SMART health, and disk-related event log errors";        Icon=0xEDA2; Color=$amber;      R=1; C=1 }
    @{ Nav="navEvents";     Title="Event Viewer";           Desc="Recent OS errors filtered to VPU-relevant providers";                Icon=0xE7BA; Color=$rose;       R=1; C=2 }
    @{ Nav="navReports";    Title="Reports";                Desc="View, copy, and export saved diagnostic reports";                    Icon=0xE7C3; Color=$indigo;     R=1; C=3 }
)

# Tile geometry — derived from panel width (resizes responsively).
# ContentArea: $WideW = 1280, margin 28 each side, gap 16, 4 cols ⇒ tile ≈ 290 wide.
# IMPORTANT: layout is index-based ($i % cols, $i / cols) — the R/C fields in
# $hubCardDefs are documentation only; do NOT rely on them at runtime, otherwise
# any drift in the foreach order silently dislocates tiles.
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

# Build tiles at (0,0); a single deterministic Update-HubTileLayout pass below
# places them. Reading $pnlSysOverview.Width at this point can return the
# pre-handle-create design-time value, which is why earlier versions
# occasionally rendered tiles 3/6/7 in the wrong row.
$script:hubTiles = @()
$tileIdx = 0
foreach ($hc in $hubCardDefs) {
    $cp = New-HubTile -Title $hc.Title -Desc $hc.Desc -IconCode $hc.Icon `
                      -X 0 -Y 0 -W 100 -H $hCH -IconColor $hc.Color
    $cp.Tag | Add-Member -NotePropertyName HubIndex -NotePropertyValue $tileIdx -Force
    $pnlSysOverview.Controls.Add($cp)
    $script:hubTiles += $cp

    $navBtn = $hubNavLookup[$hc.Nav]
    $clickBlock = { $navBtn.PerformClick() }.GetNewClosure()
    $cp.Add_Click($clickBlock)
    foreach ($ctrl in @($cp.Controls)) { $ctrl.Add_Click($clickBlock); $ctrl.Cursor = [System.Windows.Forms.Cursors]::Hand }
    $tileIdx++
}

# ---- Resize handling -------------------------------------------------------
# Single source of truth for tile positions. Always uses index-based math
# (no R/C fields), with a fixed-width fallback for the initial pass before
# the form has a window handle.
function Update-HubTileLayout {
    if (-not $script:hubTiles -or $script:hubTiles.Count -eq 0) { return }
    $pw = $pnlSysOverview.ClientSize.Width
    if ($pw -le 0) { $pw = $pnlSysOverview.Width }
    if ($pw -le 0) { $pw = $ContentW }   # final fallback (1280)
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
        # Resize inner labels so titles/descriptions don't get truncated to
        # the placeholder W=100 they were created with.
        if ($tile.Tag -and $tile.Tag.TitleLbl) {
            $tile.Tag.TitleLbl.Size = New-Object System.Drawing.Size(([int]$hCW - 28), 24)
        }
        if ($tile.Tag -and $tile.Tag.DescLbl) {
            $tile.Tag.DescLbl.Size  = New-Object System.Drawing.Size(([int]$hCW - 28), 56)
        }
    }
    if ($pnlHubActions) {
        $pnlHubActions.Location = New-Object System.Drawing.Point($hMargin, (110 + $hRows*($hCH+$hGap) + 12))
        $newActW = $pw - 2*$hMargin
        if ($newActW -gt 100) { $pnlHubActions.Width = $newActW }
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

# Re-layout once the handle exists (real ClientSize available) and again any
# time the user navigates back to Home — guards against the rare race where
# the initial pass ran before the form was sized.
$pnlSysOverview.Add_HandleCreated({ Update-HubTileLayout })
$pnlSysOverview.Add_VisibleChanged({ if ($pnlSysOverview.Visible) { Update-HubTileLayout } })

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
        $tcp = $null
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $c   = $tcp.BeginConnect($IP, $Port, $null, $null)
            $ok  = $c.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            # Without the inner try/catch, an EndConnect failure (host unreachable, RST)
            # bubbles to the outer catch and the function returns $false correctly — but
            # without it AsyncWaitHandle returning $true on a refused connection caused
            # closed ports to be reported as open. Mirrors NetworkDiagnostics.psm1.
            if ($ok) { try { $tcp.EndConnect($c) } catch { $ok = $false } }
            return $ok
        } catch { return $false }
        finally { if ($tcp) { try { $tcp.Close() } catch { } } }
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
            $isPixellot = ($nb.LinkLayerAddress -like "$OcrMacOui-*")
            $is100M = ($linkSpeed -match '^\s*100\s*Mbps')
            $is1G   = ($linkSpeed -match '\b\d+\s*Gbps\b' -or $linkSpeed -match '^\s*1000\s*Mbps')
            $label = if ($roleLabel)         { $roleLabel } `
                     elseif ($isPixellot -and $is100M) { "OCR Camera" } `
                     elseif ($isPixellot -and $is1G)   { "Main Camera (probable)" } `
                     elseif ($isPixellot)              { "Pixellot Camera" } `
                     else                              { "Unknown device" }
            $isOcr = ($roleLabel -and $roleLabel -match 'OCR|Scoreboard') -or
                     ($label -eq 'OCR Camera')
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
        Set-Card "PoEBudget" "N/A" "neutral"
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
$lblNicCardVal.Text      = "Detecting..."
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
$script:detectedNics = @(Get-NetAdapter | Where-Object {
    $d = $_.InterfaceDescription
    ($NicDriverPatterns | Where-Object { $d -like $_ }).Count -gt 0
} | Sort-Object {
    try { (Get-NetAdapterHardwareInfo -Name $_.Name -ErrorAction Stop).Function } catch { 999 }
}, Name)

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

    if ($script:runspace) { try { $script:runspace.Close() } catch { } }
    if ($script:diagPs) { try { $script:diagPs.Dispose() } catch { }; $script:diagPs = $null }
    $script:runspace = [runspacefactory]::CreateRunspace()
    $script:runspace.ApartmentState = "STA"
    $script:runspace.ThreadOptions  = "ReuseThread"
    $script:runspace.Open()

    $script:diagPs = [powershell]::Create()
    $script:diagPs.Runspace = $script:runspace
    $script:diagPs.AddScript($DiagScript) | Out-Null
    $filterNicVal = if ($cboNic.SelectedIndex -gt 0) { Get-NicNameFromCbo ($cboNic.SelectedItem -as [string]) } else { "" }
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
        PixCameraRoles     = $script:PixCameraRoles
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
            $liveColor    = if ($ntpLive -match "Local CMOS|^$") { $ColYellow } else { $ColGreen }
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

# v1.0.43 redesign — section header + report list + action bar
$histHeader = New-SectionHeader -Parent $pnlHistory `
    -Title    "Reports" `
    -Subtitle "Generate and manage diagnostic reports. Double-click any row to open the full report."

# Report list inside a card panel
$histListCard = New-Object System.Windows.Forms.Panel
$histListCard.Size      = New-Object System.Drawing.Size(($pnlHistory.Width - 56), 580)
$histListCard.Location  = New-Object System.Drawing.Point(28, 110)
$histListCard.BackColor = $ColCard
$histListCard.Anchor    = $AnchorTLRB
$histListCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ($pnlHistory.Width - 56), 580)), 8))
$pnlHistory.Controls.Add($histListCard)

$lblHistListHdr = New-Object System.Windows.Forms.Label
$lblHistListHdr.Text      = "Past Diagnostic Runs"
$lblHistListHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblHistListHdr.ForeColor = $ColText
$lblHistListHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblHistListHdr.AutoSize  = $true
$histListCard.Controls.Add($lblHistListHdr)

$lvHistory = New-Object System.Windows.Forms.ListView
$lvHistory.Size = New-Object System.Drawing.Size(($histListCard.Width - 16), ($histListCard.Height - 50))
$lvHistory.Location = New-Object System.Drawing.Point(8, 38); $lvHistory.Anchor = $AnchorTLRB
$lvHistory.View = [System.Windows.Forms.View]::Details
$lvHistory.FullRowSelect = $true
$lvHistory.GridLines = $false
$lvHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lvHistory.BackColor = $ColCard
$lvHistory.ForeColor = $ColText
$lvHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lvHistory.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
$lvHistory.UseCompatibleStateImageBehavior = $false
$histListCard.Controls.Add($lvHistory)
$lvHistory.Columns.Add("Date / Time",   142) | Out-Null
$lvHistory.Columns.Add("Result",         92) | Out-Null
$lvHistory.Columns.Add("Summary",       948) | Out-Null
$lvHistory.Columns.Add("Size",           58) | Out-Null

# Action bar — Refresh + Open Reports Folder
$histActions = New-ActionBar -Parent $pnlHistory -Y 700 -ExportText "Open Reports Folder" -PrimaryText ([char]0xE72C + "  Refresh")
$btnHistRefresh = $histActions.PrimaryBtn
$btnHistOpenFolder = $histActions.ExportBtn
$btnHistRefresh.Add_Click({ Update-HistoryList })
$btnHistOpenFolder.Add_Click({
    if (Test-Path $OutputDir) { Start-Process explorer.exe $OutputDir }
})

# Stub for legacy reference
$lnkHistRefresh = New-Object System.Windows.Forms.LinkLabel; $lnkHistRefresh.Visible = $false
$pnlHistory.Controls.Add($lnkHistRefresh)

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

# v1.0.43 redesign — section header + guide content
# v1.0.53 — feedback form removed; user feedback goes through Slack / email.
$helpHeader = New-SectionHeader -Parent $pnlHelp `
    -Title    "About & Help" `
    -Subtitle "How to use Pulse and answers to common questions."
Set-SectionPill $helpHeader "ok" "Pulse $ScriptVersion"

# Help content — fills the panel below the section header.
$rtbHelp = New-Object System.Windows.Forms.RichTextBox
$rtbHelp.Size = New-Object System.Drawing.Size(($pnlHelp.Width - 56), ($ContentH - 130))
$rtbHelp.Location = New-Object System.Drawing.Point(28, 110)
$rtbHelp.Anchor = $AnchorTLRB
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
    @{ H="Camera Fault Isolator"; B="The Camera tab includes a guided fault-isolation wizard accessible via the Open Fault Isolator button. The wizard walks through a four-phase swap test to identify whether a degraded port is caused by the NIC, the cable, or the camera itself.`n`nPhase 1 captures the baseline link speed for the suspect port. Phase 2 swaps the cable to a known-good port to test if the fault follows the NIC port. Phase 3 swaps the cable to test if the fault follows the cable. Phase 4 swaps the camera to test if the fault follows the camera.`n`nEach phase produces a plain-language verdict, and the wizard concludes with a Run Full Diagnostic action to confirm the fix." }
    @{ H="System Information sections"; B="The System Information tab surfaces hardware specs and configuration details:`n`n- Pixellot Software: registry-derived App Version, System Image Version, and Package Dependencies.`n- Operating System / System: edition, build, manufacturer, model, BIOS, serial number.`n- Time & Locale: timezone, NTP server, W32Time service status. Flags UTC default as a likely misconfiguration.`n- Pixellot Calibrations: scans known calibration paths and lists files with last-modified times.`n- Installed Software: counts installed apps and flags known-conflicting software (other AV, OBS, BitTorrent, etc.)." }
    @{ H="Frequently asked questions"; B="Q: VPU.exe shows Not streaming - is that a problem?`nA: No. VPU.exe only runs when cameras are actively streaming. It is normal for it to be absent between games.`n`nQ: A NIC port shows No link - is that a fault?`nA: No link is normal for ports that do not have a camera connected. Only ports with a camera attached that show 100 Mbps are faults.`n`nQ: Network tests fail for pixellot.stream - is that a problem?`nA: pixellot.stream is no longer probed directly. Reliable port tests now hit Pixellot's prod-echo.pixellot.tv echo server, and the pixellot.stream domain shows an INFO row in the domain test (it is a stream-only destination).`n`nQ: The tool says it cannot read the event log - what does that mean?`nA: This can happen if the Windows Event Log service is stopped or the account running the tool lacks permission. Restart the service via services.msc." }
    @{ H="About Pulse"; B="Pulse — Pixellot Unified Live System Evaluator`nVersion: see the header bar`nRepository: https://github.com/ianmoore-playon/vpu-diagnostic-tools`nLicense: Internal use within PlayOn Sports / NFHS Network. Not for external distribution.`n`nFeedback and bug reports: please share directly with the tools team over Slack or email." }
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
        $btnHwRun.Enabled=$true; $btnHwRun.Text=[char]0x25B6+"  Run Test"
        $lblHwStatus.ForeColor=$ColMuted; $lblHwStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"
        # NIC port diagram now lives on Camera Connectivity (v1.0.47); ask it to refresh.
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

# v1.0.47 — Hardware tab now focuses on peripherals (GPU, monitor, input devices,
# PoE budget, NIC link uptime). The NIC port layout diagram moved to Camera
# Connectivity, where it lives alongside the per-port diagnostic results.
$hwHeader = New-SectionHeader -Parent $pnlPoE `
    -Title    "Hardware & Peripherals" `
    -Subtitle "GPU, monitor, input devices, PoE budget, and NIC link uptime."

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

# NIC Port Layout (canvas + port detail boxes + NIC Info + Legend) was relocated
# to the Camera Connectivity tab in v1.0.47 — physical port state belongs with
# the camera diagnostics, not generic hardware. The Hardware tab now focuses on
# GPU, monitor, peripherals, and PoE budget. Update-HwPortDiagram lives in
# CameraConnectivity.psm1.

# Hardware Details log card — left column. Summary panel sits right column.
# Both sized to fill the area freed up by relocating the NIC Port Layout.
$hwLogCard = New-Object System.Windows.Forms.Panel
$hwLogCard.Size      = New-Object System.Drawing.Size(740, 460)
$hwLogCard.Location  = New-Object System.Drawing.Point(28, 220)
$hwLogCard.BackColor = $ColCard
$hwLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 740, 460)), 8))
$pnlPoE.Controls.Add($hwLogCard)

$lblHwLogHdr = New-Object System.Windows.Forms.Label
$lblHwLogHdr.Text      = "Hardware Details"
$lblHwLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblHwLogHdr.ForeColor = $ColText
$lblHwLogHdr.Location  = New-Object System.Drawing.Point(16, 10)
$lblHwLogHdr.AutoSize  = $true
$hwLogCard.Controls.Add($lblHwLogHdr)

$dgvHwLog = New-LogGrid -X 8 -Y 32 -W 724 -H 420
$hwLogCard.Controls.Add($dgvHwLog)

$hwSummary = New-SummaryPanel -Parent $pnlPoE -X 784 -Y 220 -W 480 -H 460 -Title "Summary"
Set-SummaryItems $hwSummary @(@{ Status="neutral"; Text="Run Test to populate the summary" })

# Bottom action bar
$hwActions = New-ActionBar -Parent $pnlPoE -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
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
            $sync.Cards["SvcVpu"] = @{ Value = "Not streaming"; Status = "neutral" }
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
        $btnSvcRun.Enabled=$true; $btnSvcRun.Text=[char]0x25B6+"  Run Test"
        $lblSvcStatus.ForeColor=$ColMuted; $lblSvcStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"

        # Update Overall Status pill from worst card status (v1.0.43)
        $svcWorst = "ok"
        $pri = @{ fail=3; warn=2; ok=1; neutral=0 }
        foreach ($k in @("SvcAgent","SvcKeepAgentUp","SvcCoordinator","SvcLogMeIn","SvcVpu","SvcScoreconnect","SvcStatus")) {
            if ($sync.Cards.ContainsKey($k)) {
                $s = $sync.Cards[$k].Status
                if ($s -and $pri[$s] -gt $pri[$svcWorst]) { $svcWorst = $s }
            }
        }
        Set-SectionPill $svcHeader $svcWorst

        # Build Summary bullets
        $sumItems = @()
        $statusVal = $sync.Cards["SvcStatus"].Value
        $statusSt  = $sync.Cards["SvcStatus"].Status
        if ($statusVal -and $statusVal -ne "--") {
            $sumItems += @{ Status=$statusSt; Text=$statusVal }
        }
        foreach ($k in @("SvcAgent","SvcKeepAgentUp","SvcCoordinator")) {
            $c = $sync.Cards[$k]
            if ($c -and $c.Value -and $c.Value -ne "--") {
                $label = switch ($k) { "SvcAgent"{"Agent"} "SvcKeepAgentUp"{"Watchdog (KeepAgentUp)"} "SvcCoordinator"{"Coordinator"} }
                if ($c.Status -eq "ok") { $sumItems += @{ Status="ok"; Text="$label is running" } }
                else { $sumItems += @{ Status=$c.Status; Text="$label - $($c.Value)" } }
            }
        }
        $vpuC = $sync.Cards["SvcVpu"]
        if ($vpuC -and $vpuC.Value -eq "Active") { $sumItems += @{ Status="ok"; Text="VPU.exe is encoding (cameras active)" } }
        elseif ($vpuC) { $sumItems += @{ Status="neutral"; Text="VPU.exe is not running (normal between streams)" } }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No service data collected" }) }
        Set-SummaryItems $svcSummary $sumItems
    }
})


# ---- Pixellot Services Panel -----------------------------------------------
$pnlServices = New-Object System.Windows.Forms.Panel
$pnlServices.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlServices.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlServices.BackColor = $ColBg; $pnlServices.Visible = $false; $pnlServices.Anchor = $AnchorTLRB
$form.Controls.Add($pnlServices)

# v1.0.43 redesign: section header + 6 service cards + log/summary split + action bar
$svcHeader = New-SectionHeader -Parent $pnlServices `
    -Title    "Pixellot Services" `
    -Subtitle "Running status of core Pixellot processes, remote access, and Scoreconnect service."

# 6 service cards in a row at Y=110
$svcCardDefs = @(
    @{ Key="SvcAgent";        Title="Agent";        Sub="Core process";                     Icon=[char]0xE7B8 }  # network/server icon
    @{ Key="SvcKeepAgentUp";  Title="KeepAgentUp";  Sub="Watchdog";                         Icon=[char]0xE945 }  # lightning / watchdog
    @{ Key="SvcCoordinator";  Title="Coordinator";  Sub="Core process";                     Icon=[char]0xE9D9 }  # gear stack
    @{ Key="SvcLogMeIn";      Title="LogMeIn";      Sub="Remote access";                    Icon=[char]0xE839 }  # remote desktop
    @{ Key="SvcVpu";          Title="VPU";          Sub="Only runs during active streams";  Icon=[char]0xE714 }  # video camera / stream
    @{ Key="SvcScoreconnect"; Title="Scoreconnect"; Sub="Score overlay";                    Icon=[char]0xE71D }  # scoreboard / clipboard
)
$svcCards = @{}
$svcCardW = 200; $svcCardGap = 12; $svcCardX = 28
foreach ($cd in $svcCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $svcCardX -Y 110 -Icon $cd.Icon -Sub $cd.Sub -CardW $svcCardW -CardH 90
    $svcCards[$cd.Key] = $c
    $pnlServices.Controls.Add($c.Panel)
    $svcCardX += $svcCardW + $svcCardGap
}

# Log card (left) + Summary panel (right) — two-column body
$svcLogCard = New-Object System.Windows.Forms.Panel
$svcLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$svcLogCard.Location  = New-Object System.Drawing.Point(28, 220)
$svcLogCard.BackColor = $ColCard
$svcLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlServices.Controls.Add($svcLogCard)

$lblSvcLogHdr = New-Object System.Windows.Forms.Label
$lblSvcLogHdr.Text      = "Service Details"
$lblSvcLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblSvcLogHdr.ForeColor = $ColText
$lblSvcLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblSvcLogHdr.AutoSize  = $true
$svcLogCard.Controls.Add($lblSvcLogHdr)

$dgvSvcLog = New-LogGrid -X 8 -Y 38 -W 784 -H 414
$svcLogCard.Controls.Add($dgvSvcLog)

$svcSummary = New-SummaryPanel -Parent $pnlServices -X 844 -Y 220 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $svcSummary @(@{ Status="neutral"; Text="Run Test to populate the summary" })

# Bottom action bar
$svcActions = New-ActionBar -Parent $pnlServices -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
$btnSvcRun    = $svcActions.PrimaryBtn
$btnSvcExport = $svcActions.ExportBtn

$btnSvcCancel = New-Object System.Windows.Forms.Button
$btnSvcCancel.Text      = "Cancel"
$btnSvcCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnSvcCancel.Location  = New-Object System.Drawing.Point(168, 10)
$btnSvcCancel.BackColor = $ColRed
$btnSvcCancel.ForeColor = [System.Drawing.Color]::White
$btnSvcCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSvcCancel.FlatAppearance.BorderSize = 0
$btnSvcCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnSvcCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSvcCancel.Visible   = $false
$btnSvcCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$svcActions.Bar.Controls.Add($btnSvcCancel)

$lblSvcStatus = New-Object System.Windows.Forms.Label
$lblSvcStatus.Text      = ""
$lblSvcStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblSvcStatus.ForeColor = $ColMuted
$lblSvcStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblSvcStatus.Size      = New-Object System.Drawing.Size(($pnlServices.Width - 56), 16)
$lblSvcStatus.Anchor    = $AnchorBLR
$pnlServices.Controls.Add($lblSvcStatus)

$lblSvcEta = New-Object System.Windows.Forms.Label
$lblSvcEta.Visible = $false  # ETA is implicit from the action button now
$pnlServices.Controls.Add($lblSvcEta)
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
    # Per-card aggregates surfaced as DiskSmart (#8) and DiskErrors (#9)
    $smartFailCount = 0
    $smartTotal     = 0

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
        if ($healthLvl -in @("Warn","Fail")) {
            $overallWorst = if ($healthLvl -eq "Fail") { "fail" } elseif ($overallWorst -ne "fail") { "warn" } else { $overallWorst }
            $smartFailCount++
        }
        $smartTotal++

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
        # Global 30s budget across all volumes — previously the inner break only exited
        # the directory loop, so a 4-volume system could spend 120s scanning.
        if ($scanSw.Elapsed.TotalSeconds -gt 30) {
            Disk-Log "Top folder scan" "Stopped after 30s budget — partial results above" "Gray"
            break
        }
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

    # SMART summary card (#8) — counts unhealthy/predict-failure drives among physical disks
    $smartVal = if ($smartTotal -eq 0) { "No disks detected" } `
                elseif ($smartFailCount -eq 0) { "All $smartTotal healthy" } `
                else { "$smartFailCount of $smartTotal unhealthy" }
    $smartStatus = if ($smartTotal -eq 0) { "neutral" } `
                   elseif ($smartFailCount -eq 0) { "ok" } `
                   else { "fail" }
    $sync.Cards["DiskSmart"] = @{ Value=$smartVal; Status=$smartStatus }

    # Disk errors card (#9) — count from the disk-related event log scan above
    $diskErrCount = ($diskEvents | Where-Object { $_.Level -in @(1,2) }).Count
    $diskWarnCount = ($diskEvents | Where-Object { $_.Level -eq 3 }).Count
    $errVal = if ($diskErrCount -eq 0 -and $diskWarnCount -eq 0) { "Clean (48 h)" } `
              elseif ($diskErrCount -gt 0) { "$diskErrCount error(s)" } `
              else { "$diskWarnCount warning(s)" }
    $errStatus = if ($diskErrCount -gt 0) { "fail" } `
                 elseif ($diskWarnCount -gt 0) { "warn" } `
                 else { "ok" }
    $sync.Cards["DiskErrors"] = @{ Value=$errVal; Status=$errStatus }

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
        $btnDiskRun.Enabled=$true; $btnDiskRun.Text=[char]0x25B6+"  Run Test"
        $lblDiskStatus.ForeColor=$ColMuted; $lblDiskStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"

        # Update Overall Status pill
        $diskWorst = "ok"
        $pri = @{ fail=3; warn=2; ok=1; neutral=0 }
        foreach ($k in $diskCards.Keys) {
            if ($sync.Cards.ContainsKey($k)) {
                $s = $sync.Cards[$k].Status
                if ($s -and $pri[$s] -gt $pri[$diskWorst]) { $diskWorst = $s }
            }
        }
        Set-SectionPill $diskHeader $diskWorst

        # Build Summary
        $sumItems = @()
        $smartC = $sync.Cards["DiskSmart"]
        if ($smartC) { $sumItems += @{ Status=$smartC.Status; Text="SMART: $($smartC.Value)" } }
        $errC   = $sync.Cards["DiskErrors"]
        if ($errC -and $errC.Value -ne "--") {
            if ($errC.Status -eq "ok") { $sumItems += @{ Status="ok"; Text="No disk-related event log errors in the last 48 h" } }
            else { $sumItems += @{ Status=$errC.Status; Text="Disk event log: $($errC.Value)" } }
        }
        foreach ($k in $diskCards.Keys) {
            if ($k -notlike "DiskVol_*") { continue }
            $vc = $sync.Cards[$k]
            if ($vc -and $vc.Value -ne "--") {
                $drv = $k -replace 'DiskVol_',''
                $sumItems += @{ Status=$vc.Status; Text="$($drv): $($vc.Value)" }
            }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No disk data collected" }) }
        Set-SummaryItems $diskSummary $sumItems
    }
})


# ---- System & Disk Health Panel --------------------------------------------
$pnlDisk = New-Object System.Windows.Forms.Panel
$pnlDisk.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlDisk.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlDisk.BackColor = $ColBg; $pnlDisk.Visible = $false; $pnlDisk.Anchor = $AnchorTLRB
$form.Controls.Add($pnlDisk)
# v1.0.43 redesign — section header + cards row + log/summary split + action bar
$diskHeader = New-SectionHeader -Parent $pnlDisk `
    -Title    "System & Disk Health" `
    -Subtitle "Physical drive health, free space, Pixellot storage paths, and disk-related event log errors."

$diskVolumes = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
$diskCardDefs = @(
    @{ Key="DiskSmart";  Title="SMART Health";  Sub="Per-drive predictive failure" ;Icon=[char]0xE9D9 }
    @{ Key="DiskErrors"; Title="Disk Errors";   Sub="System log, last 48 h"        ;Icon=[char]0xE7BA }
)
foreach ($diskVol in $diskVolumes) {
    $drvKey = "DiskVol_$($diskVol.DeviceID -replace ':','')"
    $diskCardDefs += @{ Key=$drvKey; Title="$($diskVol.DeviceID) Space"; Sub="$($diskVol.DeviceID) free space"; Icon=[char]0xEDA2 }
}
if ($diskVolumes.Count -eq 0) {
    $diskCardDefs += @{ Key="DiskVol_C"; Title="C: Space"; Sub="C: free space"; Icon=[char]0xEDA2 }
}

$diskCards = @{}
$diskCardW = 240; $diskCardGap = 12; $diskCardX = 28
foreach ($cd in $diskCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $diskCardX -Y 110 -Icon $cd.Icon -Sub $cd.Sub -CardW $diskCardW -CardH 90
    $diskCards[$cd.Key] = $c
    $pnlDisk.Controls.Add($c.Panel)
    $diskCardX += $diskCardW + $diskCardGap
}

# Log card (left) + Summary panel (right)
$diskLogCard = New-Object System.Windows.Forms.Panel
$diskLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$diskLogCard.Location  = New-Object System.Drawing.Point(28, 220)
$diskLogCard.BackColor = $ColCard
$diskLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlDisk.Controls.Add($diskLogCard)

$lblDiskLogHdr = New-Object System.Windows.Forms.Label
$lblDiskLogHdr.Text      = "Health Report"
$lblDiskLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblDiskLogHdr.ForeColor = $ColText
$lblDiskLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblDiskLogHdr.AutoSize  = $true
$diskLogCard.Controls.Add($lblDiskLogHdr)

$dgvDiskLog = New-LogGrid -X 8 -Y 38 -W 784 -H 414
$diskLogCard.Controls.Add($dgvDiskLog)

$diskSummary = New-SummaryPanel -Parent $pnlDisk -X 844 -Y 220 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $diskSummary @(@{ Status="neutral"; Text="Run Test to populate the summary" })

# Bottom action bar
$diskActions = New-ActionBar -Parent $pnlDisk -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
$btnDiskRun    = $diskActions.PrimaryBtn
$btnDiskExport = $diskActions.ExportBtn

$btnDiskCancel = New-Object System.Windows.Forms.Button
$btnDiskCancel.Text      = "Cancel"
$btnDiskCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnDiskCancel.Location  = New-Object System.Drawing.Point(168, 10)
$btnDiskCancel.BackColor = $ColRed
$btnDiskCancel.ForeColor = [System.Drawing.Color]::White
$btnDiskCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiskCancel.FlatAppearance.BorderSize = 0
$btnDiskCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnDiskCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnDiskCancel.Visible   = $false
$btnDiskCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$diskActions.Bar.Controls.Add($btnDiskCancel)

$lblDiskStatus = New-Object System.Windows.Forms.Label
$lblDiskStatus.Text      = ""
$lblDiskStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblDiskStatus.ForeColor = $ColMuted
$lblDiskStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblDiskStatus.Size      = New-Object System.Drawing.Size(($pnlDisk.Width - 56), 16)
$lblDiskStatus.Anchor    = $AnchorBLR
$pnlDisk.Controls.Add($lblDiskStatus)

$lblDiskEta = New-Object System.Windows.Forms.Label
$lblDiskEta.Visible = $false
$pnlDisk.Controls.Add($lblDiskEta)
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

    # Provider-name → category map. Used to classify event sources into actionable
    # buckets so agents can tell at a glance whether errors are hardware (Disk/Driver)
    # vs software (Service/App). The wildcard match is on the ProviderName from the
    # Windows event log (e.g. "Microsoft-Windows-DistributedCOM", "disk", "Service Control Manager").
    function Get-EvtCategory {
        param([string]$ProviderName)
        $p = $ProviderName.ToLower()
        if ($p -match '^(disk|ntfs|volsnap|volmgr|partmgr|storahci|storport|storvsc|fvevol|hidserv|usbstor)') { return "Disk" }
        if ($p -match '(driver|wudfrd|cdrom|usb|hid|netbt|tcpip|bowser|netio|smb|kernel)') { return "Driver" }
        if ($p -match '(service control manager|wininit|usermodepowerservice|securitycenter|workstation|server|browser|w32time|spooler)') { return "Service" }
        if ($p -match '(application|application error|\.net|wer|sidebyside|esent|user profile|appx|search|setup|distributedcom|wmi)') { return "App" }
        if ($p -match '(network|tcpip|netbt|dhcp|dnsapi|netio|nlasvc|wlan|wifi)') { return "Network" }
        return "Other"
    }

    $since = (Get-Date).AddHours(-$EvtHours)
    $totalErrors = 0; $totalWarns = 0
    # Per-category error/warn tallies for the card label
    $catTotals = @{ Disk = 0; Driver = 0; Service = 0; App = 0; Network = 0; Other = 0 }

    foreach ($logName in @("System","Application")) {
        if ($sync.EvtCancelled) { break }
        $sync.EvtStep = "Reading $logName events..."
        Evt-Section $logName
        try {
            $evts = @(Get-WinEvent -FilterHashtable @{ LogName=$logName; Level=@(1,2,3); StartTime=$since } -MaxEvents 100 -ErrorAction Stop)
            $errs = @($evts | Where-Object { $_.Level -in @(1,2) })
            $wrns = @($evts | Where-Object { $_.Level -eq 3 })
            $totalErrors += $errs.Count; $totalWarns += $wrns.Count

            # Tally by category for the summary card
            foreach ($e in $errs) {
                $cat = Get-EvtCategory -ProviderName $e.ProviderName
                $catTotals[$cat] = $catTotals[$cat] + 1
            }

            if ($evts.Count -eq 0) {
                Evt-Log "Last ${EvtHours}h" "No errors or warnings" "Pass"
            } else {
                Evt-Log "Errors (last ${EvtHours}h)"   "$($errs.Count)" $(if($errs.Count -gt 0){"Fail"}else{"Pass"})
                Evt-Log "Warnings (last ${EvtHours}h)" "$($wrns.Count)" $(if($wrns.Count -gt 0){"Warn"}else{"Info"})
                foreach ($ev in ($errs | Select-Object -First 20)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 64) { $msg = $msg.Substring(0,61)+"..." }
                    $cat = Get-EvtCategory -ProviderName $ev.ProviderName
                    Evt-Log "$($ev.TimeCreated.ToString('MM/dd HH:mm'))  [$cat] $($ev.ProviderName)" $msg "Fail"
                }
                foreach ($ev in ($wrns | Select-Object -First 10)) {
                    if ($sync.EvtCancelled) { break }
                    $msg = (($ev.Message -split "`n")[0] -replace '\s+',' ').Trim()
                    if ($msg.Length -gt 64) { $msg = $msg.Substring(0,61)+"..." }
                    $cat = Get-EvtCategory -ProviderName $ev.ProviderName
                    Evt-Log "$($ev.TimeCreated.ToString('MM/dd HH:mm'))  [$cat] $($ev.ProviderName)" $msg "Warn"
                }
            }
        } catch { Evt-Log $logName "Error reading event log" "Warn" }
    }

    # Build a category breakdown for the card label — only show non-zero categories,
    # ordered by severity-of-implication (Disk → Driver → Service → Network → App → Other)
    $catOrder = @("Disk","Driver","Service","Network","App","Other")
    $catParts = @()
    foreach ($c in $catOrder) {
        if ($catTotals[$c] -gt 0) { $catParts += "$($catTotals[$c]) $($c.ToLower())" }
    }
    $cardValue = if ($totalErrors -gt 0) {
        if ($catParts.Count -gt 0) { ($catParts -join " / ") } else { "$totalErrors errors" }
    } elseif ($totalWarns -gt 0) {
        "$totalWarns warns"
    } else {
        "Clean"
    }
    $sync.Cards["EvtStatus"] = @{
        Value  = $cardValue
        Status = if($totalErrors -gt 0){"fail"}elseif($totalWarns -gt 0){"warn"}else{"ok"}
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
        $btnEvtRun.Enabled=$true; $btnEvtRun.Text=[char]0x25B6+"  Run Test"
        $lblEvtStatus.ForeColor=$ColMuted; $lblEvtStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"

        $evtC = $sync.Cards["EvtStatus"]
        $evtSt = if ($evtC) { $evtC.Status } else { "neutral" }
        Set-SectionPill $evtHeader $evtSt
        $sumItems = @()
        if ($evtC -and $evtC.Value -ne "--") {
            if ($evtSt -eq "ok") { $sumItems += @{ Status="ok"; Text="No critical errors found in recent logs" } }
            else { $sumItems += @{ Status=$evtSt; Text="Event log: $($evtC.Value)" } }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No event log data collected" }) }
        Set-SummaryItems $evtSummary $sumItems
    }
})


# ---- Event Viewer Panel ----------------------------------------------------
$pnlEvents = New-Object System.Windows.Forms.Panel
$pnlEvents.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlEvents.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlEvents.BackColor = $ColBg; $pnlEvents.Visible = $false; $pnlEvents.Anchor = $AnchorTLRB
$form.Controls.Add($pnlEvents)
# v1.0.43 redesign — section header + status card + log/summary split + action bar
$evtHeader = New-SectionHeader -Parent $pnlEvents `
    -Title    "Event Viewer" `
    -Subtitle "Recent errors and warnings from the System and Application logs, categorised by source type."

$evtCardDefs = @(
    @{ Key="EvtStatus"; Title="Event Status"; Sub="Errors / warnings (24h)"; Icon=[char]0xE7BA }
)
$evtCards = @{}
$evtCardX = 28
foreach ($cd in $evtCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $evtCardX -Y 110 -Icon $cd.Icon -Sub $cd.Sub -CardW 320 -CardH 90
    $evtCards[$cd.Key] = $c
    $pnlEvents.Controls.Add($c.Panel)
    $evtCardX += 332
}

$evtLogCard = New-Object System.Windows.Forms.Panel
$evtLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$evtLogCard.Location  = New-Object System.Drawing.Point(28, 220)
$evtLogCard.BackColor = $ColCard
$evtLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlEvents.Controls.Add($evtLogCard)

$lblEvtLogHdr = New-Object System.Windows.Forms.Label
$lblEvtLogHdr.Text      = "Event Log"
$lblEvtLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblEvtLogHdr.ForeColor = $ColText
$lblEvtLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblEvtLogHdr.AutoSize  = $true
$evtLogCard.Controls.Add($lblEvtLogHdr)

$dgvEvtLog = New-LogGrid -X 8 -Y 38 -W 784 -H 414
$evtLogCard.Controls.Add($dgvEvtLog)

$evtSummary = New-SummaryPanel -Parent $pnlEvents -X 844 -Y 220 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $evtSummary @(@{ Status="neutral"; Text="Run Test to populate the summary" })

$evtActions = New-ActionBar -Parent $pnlEvents -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
$btnEvtRun    = $evtActions.PrimaryBtn
$btnEvtExport = $evtActions.ExportBtn

$btnEvtCancel = New-Object System.Windows.Forms.Button
$btnEvtCancel.Text      = "Cancel"
$btnEvtCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnEvtCancel.Location  = New-Object System.Drawing.Point(168, 10)
$btnEvtCancel.BackColor = $ColRed
$btnEvtCancel.ForeColor = [System.Drawing.Color]::White
$btnEvtCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnEvtCancel.FlatAppearance.BorderSize = 0
$btnEvtCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnEvtCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnEvtCancel.Visible   = $false
$btnEvtCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$evtActions.Bar.Controls.Add($btnEvtCancel)

$lblEvtStatus = New-Object System.Windows.Forms.Label
$lblEvtStatus.Text      = ""
$lblEvtStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblEvtStatus.ForeColor = $ColMuted
$lblEvtStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblEvtStatus.Size      = New-Object System.Drawing.Size(($pnlEvents.Width - 56), 16)
$lblEvtStatus.Anchor    = $AnchorBLR
$pnlEvents.Controls.Add($lblEvtStatus)

$lblEvtEta = New-Object System.Windows.Forms.Label
$lblEvtEta.Visible = $false
$pnlEvents.Controls.Add($lblEvtEta)
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
        Si-Log "App Version"           $pxVer  "Info"
        Si-Log "System Image Version"  $pxImg  "Info"
        Si-Log "Package Dependencies"  $pxDeps "Info"
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
        $upStr = "$([int][Math]::Floor($up.TotalDays))d $($up.Hours)h $($up.Minutes)m"
        Si-Log "Uptime"        $upStr  "Info"
        # Cards (#5): OS edition (short) + uptime
        $osShort = ($os.Caption -replace '^Microsoft\s+','' -replace 'Windows\s+','Win ')
        $sync.Cards["SiOs"]     = @{ Value = "$osShort  ($($os.BuildNumber))"; Status="ok" }
        $sync.Cards["SiUptime"] = @{ Value = $upStr; Status = if ($up.TotalDays -gt 30) { "warn" } else { "ok" } }
    } catch { Si-Log "OS" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Time & Locale -----------------------------------------------------------
    # Surface timezone, NTP source, and auto-time setting. VPUs deployed across
    # regions sometimes inherit a UTC default which throws off scheduled events
    # and timestamped logs.
    $sync.SysInfoStep = "Querying time settings..."
    Si-Section "Time & Locale"
    try {
        $tz = Get-CimInstance Win32_TimeZone -ErrorAction Stop
        Si-Log "Timezone"       "$($tz.Caption)" "Info"
        Si-Log "System Time"    ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) "Info"

        # NTP server registry (W32Time service)
        try {
            $ntpServer = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ErrorAction Stop).NtpServer
            if ($ntpServer) { Si-Log "NTP Server" $ntpServer "Info" }
        } catch { }

        # "Set time automatically" — controlled by W32Time service start type + NtpClient SpecialPollInterval
        $w32Svc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($w32Svc) {
            if ($w32Svc.Status -eq "Running") {
                Si-Log "Time Sync" "W32Time service running" "Info"
            } else {
                Si-Log "Time Sync" "W32Time service NOT running — automatic time sync disabled" "Warn"
            }
        }

        # Suspicious-default warning: UTC is rarely the right choice for a deployed VPU
        if ($tz.StandardName -match "^UTC$" -or $tz.Caption -match "^\(UTC\)\s*Coordinated") {
            Si-Log "Timezone Check" "System is set to UTC — confirm this matches the venue's local timezone" "Warn"
        }
    } catch { Si-Log "Time & Locale" "Query failed" "Warn" }

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
        # Card (#5): manufacturer + model trimmed
        $modelStr = if ($cs.Manufacturer -and $cs.Model) { "$($cs.Manufacturer)  $($cs.Model)" } `
                    elseif ($cs.Model) { $cs.Model } else { "Unknown" }
        if ($modelStr.Length -gt 32) { $modelStr = $modelStr.Substring(0,29) + "..." }
        $sync.Cards["SiModel"] = @{ Value = $modelStr; Status="neutral" }
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
        # Card (#5)
        $cpuCardVal = if ($fdCpuShort.Length -gt 32) { $fdCpuShort.Substring(0,29) + "..." } else { $fdCpuShort }
        $sync.Cards["SiCpu"] = @{ Value = $cpuCardVal; Status="neutral" }
    } catch { Si-Log "CPU" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Memory ------------------------------------------------------------------
    $sync.SysInfoStep = "Querying memory..."
    Si-Section "Memory"
    $fdRamGB = 0
    try {
        $os2 = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $fdRamGB = [int]([double]$os2.TotalVisibleMemorySize / 1048576.0 + 0.5)
        $fdRamFreeGB = [double]$os2.FreePhysicalMemory / 1048576.0
        Si-Log "Total RAM"  ("{0:F1} GB" -f ([double]$os2.TotalVisibleMemorySize / 1048576.0))     "Info"
        Si-Log "Available"  ("{0:F1} GB" -f $fdRamFreeGB)                                          "Info"
        # Card (#5): total + free
        $sync.Cards["SiRam"] = @{ Value = ("{0} GB total / {1:F1} GB free" -f $fdRamGB, $fdRamFreeGB); Status="ok" }
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
        # Card (#5): system drive free space
        $sysDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
        if ($sysDrive) {
            $freeGB  = [math]::Round($sysDrive.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($sysDrive.Size      / 1GB, 1)
            $usedPct = [math]::Round((1 - $sysDrive.FreeSpace/$sysDrive.Size) * 100)
            $stStatus = if ($freeGB -lt 5) { "fail" } elseif ($freeGB -lt 15) { "warn" } else { "ok" }
            $sync.Cards["SiStorage"] = @{ Value = "$freeGB GB free  ($usedPct% used)"; Status=$stStatus }
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

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Pixellot Calibrations ---------------------------------------------------
    # Surface known calibration directories and per-camera calibration files.
    # Helps field techs confirm a calibration was applied and which file is active.
    $sync.SysInfoStep = "Querying camera calibrations..."
    Si-Section "Pixellot Calibrations"
    $calibPaths = @(
        "C:\Pixellot\calibration"
        "C:\Pixellot\Calibration"
        "C:\Pixellot\Data\Calibration"
        "C:\Program Files\Pixellot\calibration"
        "C:\ProgramData\Pixellot\calibration"
    )
    $calibFound = $false
    foreach ($cp in $calibPaths) {
        if (Test-Path $cp) {
            $calibFound = $true
            Si-Log "Calibration Path" $cp "Info"
            try {
                $files = @(Get-ChildItem -Path $cp -File -ErrorAction SilentlyContinue |
                           Sort-Object LastWriteTime -Descending | Select-Object -First 12)
                if ($files.Count -eq 0) {
                    Si-Log "  Files" "Directory exists but is empty" "Warn"
                } else {
                    foreach ($f in $files) {
                        $age = (Get-Date) - $f.LastWriteTime
                        $ageStr = if ($age.TotalDays -ge 1) { "$([int]$age.TotalDays)d ago" } `
                                  elseif ($age.TotalHours -ge 1) { "$([int]$age.TotalHours)h ago" } `
                                  else { "$([int]$age.TotalMinutes)m ago" }
                        Si-Log "  $($f.Name)" "$ageStr   ($('{0:F0}' -f ($f.Length / 1024)) KB)" "Gray"
                    }
                }
            } catch { Si-Log "  Files" "Read failed" "Warn" }
        }
    }
    if (-not $calibFound) {
        Si-Log "Calibrations" "No calibration directory found in standard locations" "Gray"
    }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Installed Software ------------------------------------------------------
    # Scan registry uninstall keys (faster than Win32_Product, which triggers MSI re-validation).
    # Flag anything matching the unwanted-app patterns; surface counts only to keep the log readable.
    $sync.SysInfoStep = "Scanning installed software..."
    Si-Section "Installed Software"
    try {
        $unwantedPatterns = @(
            "OBS Studio", "vMix", "Wirecast", "XSplit",
            "Norton", "McAfee", "Avast", "AVG", "Bitdefender", "Kaspersky",
            "Bonjour", "iTunes", "QuickTime",
            "Yahoo", "Ask Toolbar", "Coupon", "WebDiscover",
            "Steam", "Epic Games", "Origin", "Battle.net",
            "BitTorrent", "uTorrent", "qBittorrent"
        )
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $apps = @(
            foreach ($p in $regPaths) {
                Get-ItemProperty $p -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
                    Select-Object DisplayName, Publisher, DisplayVersion, InstallDate
            }
        ) | Sort-Object DisplayName -Unique
        Si-Log "Total Installed" "$($apps.Count) applications" "Info"

        $flagged = @($apps | Where-Object {
            $name = $_.DisplayName
            $unwantedPatterns | Where-Object { $name -like "*$_*" } | Select-Object -First 1
        })
        if ($flagged.Count -gt 0) {
            Si-Log "Flagged Apps" "$($flagged.Count) potentially-conflicting applications detected" "Warn"
            foreach ($app in $flagged) {
                Si-Log "  $($app.DisplayName)" "$($app.Publisher) — confirm this is intentional" "Warn"
            }
        } else {
            Si-Log "Flagged Apps" "None — no known-conflicting software detected" "Pass"
        }
    } catch { Si-Log "Installed Software" "Scan failed" "Warn" }

    $ramStr = if ($fdRamGB -gt 0) { "$fdRamGB GB RAM" } else { "RAM unknown" }
    $sync.Cards["SysInfo"] = @{ Value = "$fdCpuShort   |   $ramStr"; Status = "ok" }
    $sync.SysInfoRunning = $false
    $sync.SysInfoComplete = $true
}

# ---------- Panel (v1.0.43 redesign) ---------------------------------------
$pnlSysInfo = New-Object System.Windows.Forms.Panel
$pnlSysInfo.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlSysInfo.Location  = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlSysInfo.BackColor = $ColBg
$pnlSysInfo.Anchor    = $AnchorTLRB
$pnlSysInfo.Visible   = $false
$form.Controls.Add($pnlSysInfo)
$script:allNavPanels += $pnlSysInfo

$siHeader = New-SectionHeader -Parent $pnlSysInfo `
    -Title    "System Information" `
    -Subtitle "Hardware specs, OS version, uptime, time/locale, and Pixellot software inventory."

# Summary cards — Model / OS / Uptime / CPU / RAM / Storage
$siCardDefs = @(
    @{ Key="SiModel";   Title="Model";    Sub="Manufacturer + product";    Icon=[char]0xE7F8 }
    @{ Key="SiOs";      Title="OS";       Sub="Edition + build";           Icon=[char]0xE770 }
    @{ Key="SiUptime";  Title="Uptime";   Sub="Since last boot";           Icon=[char]0xE823 }
    @{ Key="SiCpu";     Title="CPU";      Sub="Processor";                 Icon=[char]0xE950 }
    @{ Key="SiRam";     Title="RAM";      Sub="Installed memory";          Icon=[char]0xEDA2 }
    @{ Key="SiStorage"; Title="Storage";  Sub="System drive free space";   Icon=[char]0xE8B7 }
)
$siCards = @{}
$siCardW = 200; $siCardGap = 10; $siCardX = 28
foreach ($scd in $siCardDefs) {
    $sc = New-StatusCard -Title $scd.Title -X $siCardX -Y 110 -Icon $scd.Icon -Sub $scd.Sub -CardW $siCardW -CardH 80
    $siCards[$scd.Key] = $sc
    $pnlSysInfo.Controls.Add($sc.Panel)
    $siCardX += $siCardW + $siCardGap
}

# Detail log card (left) + Summary panel (right)
$siLogCard = New-Object System.Windows.Forms.Panel
$siLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$siLogCard.Location  = New-Object System.Drawing.Point(28, 210)
$siLogCard.BackColor = $ColCard
$siLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlSysInfo.Controls.Add($siLogCard)

$lblSiLogHdr = New-Object System.Windows.Forms.Label
$lblSiLogHdr.Text      = "System Inventory"
$lblSiLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblSiLogHdr.ForeColor = $ColText
$lblSiLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblSiLogHdr.AutoSize  = $true
$siLogCard.Controls.Add($lblSiLogHdr)

$siGrid = New-LogGrid -X 8 -Y 38 -W 784 -H 414 -LabelColW 200
$siLogCard.Controls.Add($siGrid)

$siSummary = New-SummaryPanel -Parent $pnlSysInfo -X 844 -Y 210 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $siSummary @(@{ Status="neutral"; Text="Refresh to populate the summary" })

# Action bar — System Info uses Refresh (per-tab) since the engine is fast
$siActions = New-ActionBar -Parent $pnlSysInfo -Y 698 -ExportText "Export Report" -PrimaryText ([char]0xE72C + "  Refresh")
$btnSiRefresh = $siActions.PrimaryBtn
$btnSiExport  = $siActions.ExportBtn

$lblSiStatus = New-Object System.Windows.Forms.Label
$lblSiStatus.Text      = "Ready"
$lblSiStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSiStatus.ForeColor = $ColMuted
$lblSiStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblSiStatus.Size      = New-Object System.Drawing.Size(($pnlSysInfo.Width - 56), 16)
$lblSiStatus.Anchor    = $AnchorBLR
$pnlSysInfo.Controls.Add($lblSiStatus)

# ---------- Timer -----------------------------------------------------------
$sysInfoTimer = New-Object System.Windows.Forms.Timer
$sysInfoTimer.Interval = 150
$sysInfoTimer.Add_Tick({
    $item = $null
    while ($sync.SysInfoQueue.TryDequeue([ref]$item)) {
        Add-LogRow $siGrid $item.Label $item.Result $item.L
    }
    # Refresh the summary cards from $sync.Cards (#5)
    foreach ($key in $siCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $siCards[$key].ValueLabel.Text -ne $sc.Value) {
            Update-CardStatus -Card $siCards[$key] -Value $sc.Value -Status $sc.Status
        }
    }
    if ($sync.SysInfoComplete) {
        $sysInfoTimer.Stop()
        $btnSiRefresh.Enabled = $true
        $btnSiRefresh.Text    = [char]0xE72C + "  Refresh"
        $lblSiStatus.Text     = "Collected at $(Get-Date -Format 'h:mm:ss tt')"
        Set-SectionPill $siHeader "ok"
        $sumItems = @()
        foreach ($k in @("SiModel","SiOs","SiUptime","SiCpu","SiRam","SiStorage")) {
            $c = $sync.Cards[$k]
            if ($c -and $c.Value -ne "--") {
                $label = switch ($k) { "SiModel"{"Model"} "SiOs"{"OS"} "SiUptime"{"Uptime"} "SiCpu"{"CPU"} "SiRam"{"RAM"} "SiStorage"{"Storage"} }
                $st = if ($c.Status -in @("ok","warn","fail")) { $c.Status } else { "ok" }
                $sumItems += @{ Status=$st; Text="$($label): $($c.Value)" }
            }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No data collected" }) }
        Set-SummaryItems $siSummary $sumItems
    } else {
        $lblSiStatus.Text = $sync.SysInfoStep
    }
})

# ---------- Collection function ---------------------------------------------
function Start-SysInfoCollection {
    if ($sync.SysInfoRunning) { return }
    $siGrid.Rows.Clear()
    # Reset the summary cards on refresh (#5)
    foreach ($key in $siCards.Keys) {
        $sync.Cards[$key] = @{ Value="--"; Status="neutral" }
        Update-CardStatus -Card $siCards[$key] -Value "--" -Status "neutral"
    }
    $btnSiRefresh.Enabled  = $false
    $lblSiStatus.Text      = "Collecting..."
    $sync.SysInfoComplete  = $false
    $sync.SysInfoCancelled = $false
    $sync.SysInfoStep      = "Starting..."
    if ($script:sysInfoRunspace) {
        try { $script:sysInfoRunspace.Close(); $script:sysInfoRunspace.Dispose() } catch { }
    }
    if ($script:sysInfoPs) {
        try { $script:sysInfoPs.Dispose() } catch { }; $script:sysInfoPs = $null
    }
    $script:sysInfoRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:sysInfoRunspace.ApartmentState = "STA"
    $script:sysInfoRunspace.ThreadOptions  = "ReuseThread"
    $script:sysInfoRunspace.Open()
    # Pass $sync to the runspace via AddArgument only — using SessionStateProxy.SetVariable
    # AND AddArgument both was wasted work and made the contract ambiguous.
    $script:sysInfoPs = [System.Management.Automation.PowerShell]::Create()
    $script:sysInfoPs.Runspace = $script:sysInfoRunspace
    $script:sysInfoPs.AddScript($SysInfoScript).AddArgument($sync) | Out-Null
    $script:sysInfoPs.BeginInvoke() | Out-Null
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
        # Prefer the synchronized _ncs_* key when present — these are written directly
        # to the synchronized $sync hashtable from background runspaces and have
        # guaranteed cross-thread visibility. Falls back to $sync.Cards[$k].Status
        # for modules that don't use the _ncs_ pattern. Same fix as v1.0.26 — the
        # nested $sync.Cards hashtable is unsynchronized and writes from inside
        # functions called from background runspaces don't reliably propagate (#60).
        $s = $sync["_ncs_$k"]
        if (-not $s -and $sync.Cards.ContainsKey($k)) { $s = $sync.Cards[$k].Status }
        if ($s -and $pri.ContainsKey($s) -and $pri[$s] -gt $pri[$worst]) { $worst = $s }
    }
    return $worst
}

function Get-ModuleSummaryText {
    param([string[]]$Keys)
    $parts = @()
    foreach ($k in $Keys) {
        # Same _nc_/Cards fallback chain as Get-WorstCardStatus (#60)
        $v = $sync["_nc_$k"]
        if (-not $v -and $sync.Cards.ContainsKey($k)) { $v = $sync.Cards[$k].Value }
        if ($v -and $v -ne "--") { $parts += $v }
    }
    return ($parts -join "   |   ")
}

# Per-module human-readable summary (replaces raw card-value concatenation).
function Get-FdModuleSummary {
    param([int]$Idx, [string]$Worst)
    switch ($Idx) {
        0 { # System Overview
            $v = if ($sync.Cards.ContainsKey("SysInfo")) { $sync.Cards["SysInfo"].Value } else { "" }
            # PS 5.1: `return if (...)` is invalid (if is a statement, not expression).
            # Wrap in $() or assign first.
            if ($v -and $v -ne "--") { return $v } else { return "Hardware details collected" }
        }
        1 { # Network Configuration
            if ($Worst -eq "ok") { return "Internet connected - all ports and domains reachable" }
            $parts = @()
            foreach ($k in @("NetInternet","NetPorts","NetDomains")) {
                # Read from the synchronized _nc_/_ncs_ keys preferentially (#60)
                $val = $sync["_nc_$k"]
                $sts = $sync["_ncs_$k"]
                if (-not $val -and $sync.Cards.ContainsKey($k)) {
                    $val = $sync.Cards[$k].Value
                    $sts = $sync.Cards[$k].Status
                }
                if ($sts -ne "ok" -and $val -and $val -ne "--") { $parts += $val }
            }
            if ($parts.Count -gt 0) { return ($parts -join "   |   ") }
            return Get-ModuleSummaryText @("NetInternet","NetPorts","NetDomains")
        }
        2 { # Camera Connectivity
            if ($Worst -eq "ok") { return "All cameras online and responding normally" }
            return Get-ModuleSummaryText @("SmartSpeed","PingCHU","ChuDetect","PoEBudget")
        }
        3 { # Pixellot Services
            $v = if ($sync.Cards.ContainsKey("SvcStatus")) { $sync.Cards["SvcStatus"].Value } else { "" }
            if ($Worst -eq "ok") { return "All Pixellot services running" }
            if ($v -eq "None found") { return "No Pixellot services detected on this VPU" }
            if ($v -and $v -ne "--") { return $v } else { return "Service check complete" }
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
# AutoScroll lets the panel scroll vertically when the 7 module rows + bottom
# buttons exceed the available content height (e.g. on smaller windows or after
# the row-height bump from v1.0.33). Fix for #59.
$pnlFullDiag = New-Object System.Windows.Forms.Panel
$pnlFullDiag.Size       = New-Object System.Drawing.Size($ContentW, $ContentH)
$pnlFullDiag.Location   = New-Object System.Drawing.Point(0, $ContentY)
$pnlFullDiag.BackColor  = $ColBg
$pnlFullDiag.Anchor     = $AnchorTLRB
$pnlFullDiag.Visible    = $false
$pnlFullDiag.AutoScroll = $true
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
$lblFdSub.Text      = "Checks all modules and highlights issues with recommended actions."
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
$fdRowH        = 64
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

    # Suggested action (bottom line - hidden for passing modules; wraps to 2 lines if needed)
    $aLbl = New-Object System.Windows.Forms.Label
    $aLbl.Text        = ""
    $aLbl.Font        = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $aLbl.ForeColor   = $ColYellow
    $aLbl.Location    = New-Object System.Drawing.Point(406, 32)
    $aLbl.Size        = New-Object System.Drawing.Size(686, 28)
    $aLbl.BackColor   = [System.Drawing.Color]::Transparent
    $aLbl.Visible     = $false
    $aLbl.UseMnemonic = $false
    $rPnl.Controls.Add($aLbl)

    # View button - neutral until complete, accented for issues
    $vBtn = New-Object System.Windows.Forms.Button
    $vBtn.Text      = "View  >"
    $vBtn.Size      = New-Object System.Drawing.Size(96, 30)
    $vBtn.Location  = New-Object System.Drawing.Point(1110, 17)
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

# --- Bottom buttons (Re-run All | Re-run Issues | Back to Home) --------------
# Rows end at 150 + 7*(64+6) = 640.  Buttons at 652.
$btnFdRerun = New-Object System.Windows.Forms.Button
$btnFdRerun.Text      = [char]0x25B6 + "  Re-run All"
$btnFdRerun.Size      = New-Object System.Drawing.Size(172, 40)
$btnFdRerun.Location  = New-Object System.Drawing.Point(30, 652)
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
$btnFdRerunFailed.Text      = "Re-run Issues Only"
$btnFdRerunFailed.Size      = New-Object System.Drawing.Size(190, 40)
$btnFdRerunFailed.Location  = New-Object System.Drawing.Point(214, 652)
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
$btnFdBack.Location  = New-Object System.Drawing.Point(418, 652)
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
            $severityT = switch ($worst) { "fail"{"Critical"} "warn"{"Warning"} "ok"{"Healthy"} default{"Healthy"} }

            $row.Dot.BackColor       = $dotColor
            $row.StatusLbl.Text      = $severityT
            $row.StatusLbl.ForeColor = $dotColor

            $row.ValueLbl.Text       = Get-FdModuleSummary $i $worst
            $row.ValueLbl.ForeColor  = if ($worst -in @("fail","warn")) { $ColText } else { $ColMuted }

            # Suggested action - shown only for Warning / Critical
            $action = Get-FdActionText $i $worst
            if ($action) {
                $row.ActionLbl.Text      = $action
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

    # Hand off to toast timer for the consolidated summary toast (#57).
    # FullDiagInProgress was suppressing per-module toasts during the run.
    $sync.FullDiagSummary = @{
        TotalIssues = $totalIssues
        CritCount   = $critCount
        WarnCount   = $warnCount
        CritNames   = @($critNames)
        WarnNames   = @($warnNames)
    }
    $sync.FullDiagInProgress = $false
    $sync.FullDiagToastReady = $true
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

    # Suppress per-module toasts while Full Diagnostic is running (#57).
    # The toast timer reads this flag and fires only the consolidated summary at end.
    $sync.FullDiagInProgress = $true

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

# v1.0.43 redesign — section header + grouped settings cards + action bar
$setHeader = New-SectionHeader -Parent $pnlSettings `
    -Title    "Settings" `
    -Subtitle "Configure tool behavior and preferences."

# Card factory — a titled, bordered container that holds a labelled control row.
function _NewSetCard {
    param([int]$Y, [int]$H, [string]$Title)
    $card = New-Object System.Windows.Forms.Panel
    $card.Size      = New-Object System.Drawing.Size(620, $H)
    $card.Location  = New-Object System.Drawing.Point(28, $Y)
    $card.BackColor = $ColCard
    $card.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 620, $H)), 8))
    $pnlSettings.Controls.Add($card)
    $hdr = New-Object System.Windows.Forms.Label
    $hdr.Text      = $Title
    $hdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    $hdr.ForeColor = $ColText
    $hdr.Location  = New-Object System.Drawing.Point(16, 12)
    $hdr.Size      = New-Object System.Drawing.Size(580, 20)
    $card.Controls.Add($hdr)
    return $card
}

# General — Theme toggle (existing functionality)
$cardGeneral = _NewSetCard -Y 110 -H 130 -Title "General"

$lblSetThemeName = New-Object System.Windows.Forms.Label
$lblSetThemeName.Text      = "Theme"
$lblSetThemeName.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$lblSetThemeName.ForeColor = $ColText
$lblSetThemeName.Location  = New-Object System.Drawing.Point(16, 44)
$lblSetThemeName.AutoSize  = $true
$cardGeneral.Controls.Add($lblSetThemeName)

$lblSetThemeDesc = New-Object System.Windows.Forms.Label
$lblSetThemeDesc.Text      = "Current: $(if($VpuTheme -eq 'light'){'Light'}else{'Dark'}) Mode. Switching restarts the application."
$lblSetThemeDesc.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSetThemeDesc.ForeColor = $ColMuted
$lblSetThemeDesc.Location  = New-Object System.Drawing.Point(16, 64)
$lblSetThemeDesc.Size      = New-Object System.Drawing.Size(440, 18)
$cardGeneral.Controls.Add($lblSetThemeDesc)

$btnSetTheme = New-Object System.Windows.Forms.Button
$btnSetTheme.Text      = if ($VpuTheme -eq "light") { "Switch to Dark Mode" } else { "Switch to Light Mode" }
$btnSetTheme.Size      = New-Object System.Drawing.Size(180, 32)
$btnSetTheme.Location  = New-Object System.Drawing.Point(424, 50)
$btnSetTheme.BackColor = $ColAccent
$btnSetTheme.ForeColor = [System.Drawing.Color]::White
$btnSetTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSetTheme.FlatAppearance.BorderSize = 0
$btnSetTheme.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$btnSetTheme.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSetTheme.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 32)), 6))
$cardGeneral.Controls.Add($btnSetTheme)
$btnSetTheme.Add_Click({
    $newTheme = if ($VpuTheme -eq "dark") { "light" } else { "dark" }
    try { [System.IO.File]::WriteAllText($SettingsPath, "{`"Theme`":`"$newTheme`"}") } catch { }
    $runScript = if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $PSCommandPath } else { Join-Path $PSScriptRoot "Run.ps1" }
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`""
    $form.Close()
})

# Reports — output directory shortcut
$cardReports = _NewSetCard -Y 252 -H 110 -Title "Reports"
$lblSetDirName = New-Object System.Windows.Forms.Label
$lblSetDirName.Text      = "Output Directory"
$lblSetDirName.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$lblSetDirName.ForeColor = $ColText
$lblSetDirName.Location  = New-Object System.Drawing.Point(16, 44)
$lblSetDirName.AutoSize  = $true
$cardReports.Controls.Add($lblSetDirName)

$lblSetDirPath = New-Object System.Windows.Forms.Label
$lblSetDirPath.Text      = $OutputDir
$lblSetDirPath.Font      = New-Object System.Drawing.Font("Consolas", 8.5)
$lblSetDirPath.ForeColor = $ColMuted
$lblSetDirPath.Location  = New-Object System.Drawing.Point(16, 64)
$lblSetDirPath.Size      = New-Object System.Drawing.Size(440, 18)
$cardReports.Controls.Add($lblSetDirPath)

$btnSetOpenDir = New-Object System.Windows.Forms.Button
$btnSetOpenDir.Text      = "Open Folder"
$btnSetOpenDir.Size      = New-Object System.Drawing.Size(180, 32)
$btnSetOpenDir.Location  = New-Object System.Drawing.Point(424, 50)
$btnSetOpenDir.BackColor = $ColCard
$btnSetOpenDir.ForeColor = $ColText
$btnSetOpenDir.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSetOpenDir.FlatAppearance.BorderColor = $ColBorder
$btnSetOpenDir.FlatAppearance.BorderSize  = 1
$btnSetOpenDir.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnSetOpenDir.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSetOpenDir.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 32)), 6))
$cardReports.Controls.Add($btnSetOpenDir)
$btnSetOpenDir.Add_Click({ if (Test-Path $OutputDir) { Start-Process explorer.exe $OutputDir } })

# About card on the right column — version + license + repo link
$cardAbout = New-Object System.Windows.Forms.Panel
$cardAbout.Size      = New-Object System.Drawing.Size(580, 374)
$cardAbout.Location  = New-Object System.Drawing.Point(672, 110)
$cardAbout.BackColor = $ColCard
$cardAbout.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 580, 374)), 8))
$pnlSettings.Controls.Add($cardAbout)

$lblAbHdr = New-Object System.Windows.Forms.Label
$lblAbHdr.Text      = "About Pulse"
$lblAbHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$lblAbHdr.ForeColor = $ColText
$lblAbHdr.Location  = New-Object System.Drawing.Point(20, 18)
$lblAbHdr.AutoSize  = $true
$cardAbout.Controls.Add($lblAbHdr)

$lblAbBody = New-Object System.Windows.Forms.Label
$lblAbBody.Text      = ("Pulse — Pixellot Unified Live System Evaluator`n" +
                       "Version: $ScriptVersion`n" +
                       "Repository: github.com/ianmoore-playon/vpu-diagnostic-tools`n" +
                       "License: Internal use within PlayOn Sports / NFHS Network.`n`n" +
                       "Pulse is an in-house diagnostic tool for Pixellot VPU systems. " +
                       "It checks network connectivity, services, hardware, disks, event logs, " +
                       "and camera link state — exporting a single shareable report for IT triage.")
$lblAbBody.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblAbBody.ForeColor = $ColText
$lblAbBody.Location  = New-Object System.Drawing.Point(20, 48)
$lblAbBody.Size      = New-Object System.Drawing.Size(540, 280)
$cardAbout.Controls.Add($lblAbBody)

# Action bar — Restore Defaults + Save (placeholder for now; theme-toggle saves on its own)
$setActions = New-ActionBar -Parent $pnlSettings -Y 700 -ExportText "Restore Defaults" -PrimaryText "Save Settings"
$setActions.PrimaryBtn.Add_Click({ [System.Windows.Forms.MessageBox]::Show("Settings saved.", "Pulse Settings", "OK", "Information") | Out-Null })
$setActions.ExportBtn.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show("Restore default settings? This will reset the theme to Dark and clear customisations.", "Restore Defaults", "YesNo", "Warning")
    if ($r -eq "Yes") { try { Remove-Item $SettingsPath -ErrorAction SilentlyContinue } catch { } }
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
    if ($anyRunning -and $pnlToast.Visible) { $pnlToast.Visible = $false; $script:toastShownAt = $null }

    # Auto-dismiss all-clear toasts after 8 seconds (sticky for warnings/issues)
    if ($script:toastShownAt -and $pnlToast.Visible -and ((Get-Date) - $script:toastShownAt).TotalSeconds -ge 8) {
        $pnlToast.Visible = $false
        $script:toastShownAt = $null
    }

    # Suppress per-module toasts while a Full Diagnostic is in progress (#57).
    # The consolidated summary toast is fired below when FullDiagToastReady flips true.
    $inFullDiag = $sync.FullDiagInProgress -eq $true

    foreach ($key in $toastModuleMeta.Keys) {
        $nowDone = $sync[$key] -eq $true
        if ($nowDone -and ($toastPrevState[$key] -eq 0)) {
            $toastPrevState[$key] = 1
            # Skip the per-module toast during a Full Diagnostic — but still update
            # state so the next individual run starts from a clean transition.
            if ($inFullDiag) { continue }
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

            # Build detail + next-step hint per module (#12). Counts come from $sync;
            # next-step points to the relevant tab when issues are found.
            $detail = ""
            switch ($key) {
                "NetComplete" {
                    if ($isOk -and -not $isWarn) { $detail = "All ports and domains reachable" }
                    else {
                        $pf = [int]$sync.NetPortFail; $df = [int]$sync.NetDomainFail
                        $detail = "$pf port / $df domain failure(s) — open Network tab to inspect"
                    }
                }
                "SvcComplete" {
                    $detail = if ($isOk) { "All required services running" } else { "Service issues — open Services tab to inspect" }
                }
                "DiskComplete" {
                    $detail = if ($isOk) { "All drives healthy" } else { "Disk issues — open Disks tab to inspect" }
                }
                "EvtComplete" {
                    $ev = $sync.Cards["EvtStatus"].Value
                    $detail = if ($isOk) { "$ev — no recent OS errors" } else { "$ev — open Event Logs tab to inspect" }
                }
                "HwComplete" {
                    $detail = if ($isOk) { "GPU, monitor, and peripherals OK" } else { "Hardware issues — open Hardware tab to inspect" }
                }
                "SysInfoComplete" {
                    $detail = "System inventory collected"
                }
                default {
                    $detail = if ($isOk) { "No issues found" } else { "Open the relevant tab to inspect" }
                }
            }
            $sub  = "$detail   |   $(Get-Date -Format 'h:mm tt')"

            $pnlToastAccent.BackColor = $clr
            $lblToastIcon.Text        = $icon
            $lblToastIcon.ForeColor   = $clr
            $lblToastText.Text        = $msg
            $lblToastText.ForeColor   = $clr
            $lblToastSub.Text         = $sub
            $pnlToast.Visible         = $true
            $pnlToast.BringToFront()

            # Auto-dismiss for all-clear after 8 seconds; warnings/issues stay sticky
            # so they don't disappear before the agent has a chance to read them.
            if ($isOk -and -not $isWarn) {
                $script:toastShownAt = Get-Date
            } else {
                $script:toastShownAt = $null
            }
        }
        # Reset state when module resets (new run)
        if (-not $sync[$key] -and ($toastPrevState[$key] -eq 1)) {
            $toastPrevState[$key] = 0
        }
    }

    # Consolidated Full Diagnostic summary toast (#57). Fires once when the
    # FullDiagnostic completion handler sets FullDiagToastReady. Replaces the
    # 7 per-module toasts that were previously firing in rapid succession.
    if ($sync.FullDiagToastReady -eq $true) {
        $sync.FullDiagToastReady = $false
        $s = $sync.FullDiagSummary
        if ($s -and $s.TotalIssues -eq 0) {
            $clr  = $ColGreen
            $icon = [char]0xE73E
            $msg  = "Full Diagnostic complete  -  All Clear"
            $sub  = "All checks passed   |   $(Get-Date -Format 'h:mm tt')"
            $auto = $true
        } elseif ($s) {
            $clr  = if ($s.CritCount -gt 0) { $ColRed } else { $ColYellow }
            $icon = if ($s.CritCount -gt 0) { [char]0xEA39 } else { [char]0xE7BA }
            $issuesParts = @()
            if ($s.CritCount -gt 0) { $issuesParts += "$($s.CritCount) critical" }
            if ($s.WarnCount -gt 0) { $issuesParts += "$($s.WarnCount) warning$(if($s.WarnCount -ne 1){'s'})" }
            $msg  = "Full Diagnostic complete  -  $($issuesParts -join ', ')"
            $modList = @($s.CritNames + $s.WarnNames) | Select-Object -First 3
            $more    = if (($s.CritNames.Count + $s.WarnNames.Count) -gt 3) { ", ..." } else { "" }
            $sub  = "$($modList -join ', ')$more   |   $(Get-Date -Format 'h:mm tt')"
            $auto = $false
        } else {
            $clr=$ColMuted; $icon=[char]0xE946; $msg="Full Diagnostic complete"; $sub=Get-Date -Format 'h:mm tt'; $auto=$true
        }
        $pnlToastAccent.BackColor = $clr
        $lblToastIcon.Text        = $icon
        $lblToastIcon.ForeColor   = $clr
        $lblToastText.Text        = $msg
        $lblToastText.ForeColor   = $clr
        $lblToastSub.Text         = $sub
        $pnlToast.Visible         = $true
        $pnlToast.BringToFront()
        $script:toastShownAt = if ($auto) { Get-Date } else { $null }
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
$navCamera.Add_Click({      Show-Panel $center;         Set-ActiveNav $navCamera; Show-OverviewSteps })
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
        # Sort the detected NICs by MAC so port-1 (lowest MAC) is first — this
        # matches how Update-HwPortDiagram lays them out on the diagram, so
        # "Ethernet 24" in slot 1 of the dropdown corresponds to physical Port 1.
        $sortedDetected = @($script:detectedNics | Sort-Object MacAddress)
        $portIdx = 1
        foreach ($n in $sortedDetected) {
            # Live device probe — same logic Update-HwPortDiagram uses, so
            # the dropdown entry shows what's actually plugged into the port.
            $deviceLabel = "No device"
            try {
                $devInfo = Get-PortDevice -Adapter $n -LinkSpeed $n.LinkSpeed
                if ($devInfo -and $devInfo.Label) { $deviceLabel = $devInfo.Label }
            } catch { }
            $cboNic.Items.Add("Port $portIdx — $($n.Name) — $deviceLabel") | Out-Null
            $cboGuidePortA.Items.Add($n.Name) | Out-Null
            $portIdx++
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

    # Async update check - compares remote $ScriptVersion to current; shows notice if newer.
    # Stash $wc and the event subscription so FormClosing can clean them up.
    try {
        $script:updateWc = New-Object System.Net.WebClient
        $script:updateSub = Register-ObjectEvent -InputObject $script:updateWc -EventName DownloadStringCompleted `
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
        }
        $rawUrl = "https://raw.githubusercontent.com/ianmoore-playon/vpu-diagnostic-tools/refs/heads/main/Pulse.ps1"
        $script:updateWc.DownloadStringAsync([uri]$rawUrl)
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
    try { if ($script:sysInfoPs)       { $script:sysInfoPs.Dispose() } } catch { }
    try { if ($script:updateSub) { Unregister-Event -SubscriptionId $script:updateSub.Id -ErrorAction SilentlyContinue; $script:updateSub | Remove-Job -Force -ErrorAction SilentlyContinue } } catch { }
    try { if ($script:updateWc)  { $script:updateWc.Dispose() } } catch { }
})

[System.Windows.Forms.Application]::Run($form)
try { Stop-Transcript -ErrorAction SilentlyContinue } catch { }
