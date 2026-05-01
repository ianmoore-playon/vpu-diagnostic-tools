# =============================================================================
#  Pulse.ps1  -  Pulse — Pixellot Diagnostic Toolset
#  Loads modules from .\Modules\ and runs the GUI.
#
#  HOW TO RUN: double-click "Pulse.bat"  (handles elevation automatically)
# =============================================================================

$ScriptVersion = "1.0.18"

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
$form.Text = "Pulse — Pixellot Diagnostic Toolset"
$form.ClientSize = New-Object System.Drawing.Size(1280, 760)
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

# Layout constants — typed [int] so arithmetic never fails on malformed environments
[int]$HdrH     = 68
[int]$TabH     = 64
[int]$SbarH    = 28
[int]$SideW    = 0                              # no sidebar
[int]$ContentX = 0
[int]$ContentY = $HdrH + $TabH                 # 120
[int]$ContentH = 760 - $HdrH - $TabH - $SbarH  # 612
[int]$ContentW = 1280                           # full-width content area
# Legacy aliases — Phase 2 will rewrite panel modules to use ContentW/ContentH directly
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
$lblHdrSub.Text      = "A Pixellot Diagnostic Toolset"
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

$btnTheme = New-Object System.Windows.Forms.Button
$btnTheme.Text      = if ($VpuTheme -eq "light") { "Dark Mode" } else { "Light Mode" }
$btnTheme.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$btnTheme.Size      = New-Object System.Drawing.Size(110, 20)
$btnTheme.Location  = New-Object System.Drawing.Point(960, 4)
$btnTheme.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTheme.FlatAppearance.BorderColor = $ColBorder
$btnTheme.FlatAppearance.BorderSize  = 1
$btnTheme.BackColor = $ColCard
$btnTheme.ForeColor = $ColMuted
$btnTheme.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnTheme.Anchor    = $AnchorTR
$pnlStatusBar.Controls.Add($btnTheme)
$btnTheme.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,110,20)),4))
$btnTheme.Add_Click({
    $newTheme = if ($VpuTheme -eq "dark") { "light" } else { "dark" }
    try { [System.IO.File]::WriteAllText($SettingsPath, "{`"Theme`":`"$newTheme`"}") } catch { }
    $runScript = if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $PSCommandPath } else { Join-Path $PSScriptRoot "Run.ps1" }
    Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`""
    $form.Close()
})

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
$btnTabFullDiag.Location  = New-Object System.Drawing.Point(1142, 13)
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
    $navPoE,$navDisk,$navEvents,$navReports,$btnTabFullDiag
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

# Update notification — placed in header
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

# Compat controls referenced by timer code — hidden, off-screen
$lblVpuVal     = New-Object System.Windows.Forms.Label; $lblVpuVal.Visible     = $false
$pnlSideDot    = New-Object System.Windows.Forms.Panel; $pnlSideDot.Visible    = $false; $pnlSideDot.BackColor = $ColGreen
$lblSideStatus = New-Object System.Windows.Forms.Label; $lblSideStatus.Visible = $false
$form.Controls.AddRange(@($lblVpuVal, $pnlSideDot, $lblSideStatus))


# ---------- Load panel modules -----------------------------------------------
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
$pnlSettings = New-StubPanel "Settings" "Configure tool behavior and preferences."

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

# Watcher timer — fires every 400ms, shows toast when any module completes
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
            $msg  = "$($meta.Name)  —  " + $(if ($isOk -and -not $isWarn) { "All Clear" } elseif ($isWarn) { "Warning" } else { "Issues Found" })
            $sub  = "Completed $(Get-Date -Format 'HH:mm:ss')   |   Click X to dismiss"

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
