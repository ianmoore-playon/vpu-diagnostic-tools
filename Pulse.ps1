# =============================================================================
#  Pulse.ps1  -  Pulse - Pixellot Unified Live System Evaluator
#  Loads modules from .\Modules\ and runs the GUI.
#
#  HOW TO RUN: double-click "Pulse.bat"  (handles elevation automatically)
# =============================================================================

$ScriptVersion = "1.0.43"

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
. "$ModulesDir\UIHelpers.psm1"

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
$form.ClientSize = New-Object System.Drawing.Size(1500, 800)
$form.MinimumSize = $form.Size
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
[int]$ContentW = 1500 - $SideW                  # 1280 — matches old WideW
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
$navPoE         = New-SidebarNavButton "PoE / NIC Hardware"     0xE7E8 $sbNavY; $sbNavY += 42
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

# Aliases kept for click handlers from older code paths
$navOverview = $navCamera
$navTests    = $navCamera
$navHistory  = $navReports
$navHelp     = $navAbout

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
$tabTip.SetToolTip($navPoE,         "PoE card power budget, per-port voltage and current, GPU and peripheral status")
$tabTip.SetToolTip($navDisk,        "Drive free space, disk health, and system memory availability")
$tabTip.SetToolTip($navEvents,      "Recent OS system errors filtered for hardware and service-related issues")
$tabTip.SetToolTip($navReports,     "View, copy, or export previously saved diagnostic reports")
$tabTip.SetToolTip($navSettings,    "Theme and application settings")
$tabTip.SetToolTip($navAbout,       "Help, version, and feedback form")

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
. "$ModulesDir\SystemOverview.psm1"
. "$ModulesDir\CameraConnectivity.psm1"
. "$ModulesDir\NetworkDiagnostics.psm1"
. "$ModulesDir\ReportGenerator.psm1"
. "$ModulesDir\HelpAbout.psm1"
. "$ModulesDir\PoeNicHardware.psm1"
. "$ModulesDir\PixellotServices.psm1"
. "$ModulesDir\DiskHealth.psm1"
. "$ModulesDir\EventLogs.psm1"
. "$ModulesDir\SystemInformation.psm1"
. "$ModulesDir\FullDiagnostic.psm1"
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

# Feedback — token configuration shortcut
$cardFeedback = _NewSetCard -Y 374 -H 110 -Title "Feedback"
$lblSetFbName = New-Object System.Windows.Forms.Label
$lblSetFbName.Text      = "GitHub Token"
$lblSetFbName.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
$lblSetFbName.ForeColor = $ColText
$lblSetFbName.Location  = New-Object System.Drawing.Point(16, 44)
$lblSetFbName.AutoSize  = $true
$cardFeedback.Controls.Add($lblSetFbName)

$lblSetFbState = New-Object System.Windows.Forms.Label
$lblSetFbState.Text      = if ($script:FeedbackToken) { "Configured. Feedback will post directly to the tools team." } else { "Not configured. Feedback will be copied to clipboard as a fallback." }
$lblSetFbState.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSetFbState.ForeColor = if ($script:FeedbackToken) { $ColGreen } else { $ColYellow }
$lblSetFbState.Location  = New-Object System.Drawing.Point(16, 64)
$lblSetFbState.Size      = New-Object System.Drawing.Size(440, 18)
$cardFeedback.Controls.Add($lblSetFbState)

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

    # Async update check - compares remote $ScriptVersion to current; shows notice if newer.
    # Stash $wc and the event subscription so FormClosing can clean them up.
    try {
        $script:updateWc = New-Object System.Net.WebClient
        if ($env:VPU_DEPLOY_TOKEN) { $script:updateWc.Headers.Add("Authorization", "Bearer $env:VPU_DEPLOY_TOKEN") }
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
