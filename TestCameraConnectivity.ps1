# =============================================================================
#  VPU Diagnostic Tool Suite  v1.0.0
#  Launcher - loads modules from .\Modules\ and runs the GUI.
#
#  HOW TO RUN: double-click RunDiagnostic.bat  (handles elevation automatically)
# =============================================================================

$ScriptVersion = "1.0.2"

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
$OutputDir         = Join-Path $OutputBaseDir "CameraLink_Results"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$NicDriverPatterns = @("Intel(R) 82574L*", "Intel(R) I210*", "Intel(R) I211*", "Intel(R) I350*", "Intel(R) I354*")
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
        SvcStatus   = @{ Value = "--"; Status = "neutral" }
        DiskStatus  = @{ Value = "--"; Status = "neutral" }
        MemStatus   = @{ Value = "--"; Status = "neutral" }
        EvtStatus   = @{ Value = "--"; Status = "neutral" }
        HwGpu       = @{ Value = "--"; Status = "neutral" }
        HwMonitor   = @{ Value = "--"; Status = "neutral" }
        HwMmk       = @{ Value = "--"; Status = "neutral" }
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
$form.Text = "VPU Diagnostic Tool Suite"
$form.ClientSize = New-Object System.Drawing.Size(1280, 760)
$form.MinimumSize = $form.Size
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $ColBg
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$AssetsDir   = Join-Path $PSScriptRoot "Assets"
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

$AnchorTLRB = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTLR  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorTLB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTRB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorBLR  = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorBL   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$AnchorTR   = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right

# Layout constants — typed [int] so arithmetic never fails on malformed environments
[int]$HdrH     = 68
[int]$TabH     = 52
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

$picHdrLogo = New-Object System.Windows.Forms.PictureBox
$picHdrLogo.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picHdrLogo.Location  = New-Object System.Drawing.Point(8, 4)
$picHdrLogo.Size      = New-Object System.Drawing.Size(200, 60)
$picHdrLogo.BackColor = [System.Drawing.Color]::Transparent
$logoPngPath = Join-Path $AssetsDir "logo.png"
if (Test-Path $logoPngPath) {
    $picHdrLogo.Image = [System.Drawing.Image]::FromFile($logoPngPath)
}
$pnlHeader.Controls.Add($picHdrLogo)

$lblHdrVer = New-Object System.Windows.Forms.Label
$lblHdrVer.Text      = "Version $ScriptVersion"
$lblHdrVer.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblHdrVer.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblHdrVer.Location  = New-Object System.Drawing.Point(1090, 10)
$lblHdrVer.Size      = New-Object System.Drawing.Size(160, 16)
$lblHdrVer.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblHdrVer.Anchor    = $AnchorTR
$pnlHeader.Controls.Add($lblHdrVer)

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
$navSysInfo     = New-TabButton "System Overview"      0xE9A0  (1 * $tabW)  $tabW
$navNetConfig   = New-TabButton "Network Config"       0xE701  (2 * $tabW)  $tabW
$navCamera      = New-TabButton "Camera Connectivity"  0xE722  (3 * $tabW)  $tabW
$navServices    = New-TabButton "Pixellot Services"    0xE9F5  (4 * $tabW)  $tabW
$navPoE         = New-TabButton "PoE / NIC Hardware"   0xE7E8  (5 * $tabW)  $tabW
$navDisk        = New-TabButton "Disk & System Health" 0xEDA2  (6 * $tabW)  $tabW
$navEvents      = New-TabButton "Event Viewer"         0xE7BA  (7 * $tabW)  $tabW
$navReports     = New-TabButton "Reports"              0xE7C3  (8 * $tabW)  $tabW

$pnlTabBar.Controls.AddRange(@(
    $navSysOverview,$navSysInfo,$navNetConfig,$navCamera,$navServices,
    $navPoE,$navDisk,$navEvents,$navReports
))

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
. "$ModulesDir\EventViewer.psm1"
. "$ModulesDir\HardwareOverview.psm1"
$pnlReports  = New-StubPanel "Reports"  "Generate and manage diagnostic reports."
$pnlSettings = New-StubPanel "Settings" "Configure tool behavior and preferences."

# ---------- Nav panel registry (must be after all panels created) ------------
$script:allNavPanels = @(
    $pnlSysOverview,$center,$pnlGuide,$pnlHistory,$pnlHelp,$pnlNetwork,
    $pnlPoE,$pnlServices,$pnlDisk,$pnlEvents,$pnlReports,$pnlSettings,$pnlSysInfo
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
        $rawUrl = "https://raw.githubusercontent.com/ianmoore-playon/vpu-diagnostic-tools/refs/heads/main/TestCameraConnectivity.ps1"
        $wc.DownloadStringAsync([uri]$rawUrl)
    } catch { }
})

$form.Add_FormClosing({
    $timer.Stop(); $netTimer.Stop(); $svcTimer.Stop(); $diskTimer.Stop(); $evtTimer.Stop(); $hwTimer.Stop(); $sysInfoTimer.Stop()
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
