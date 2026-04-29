# =============================================================================
#  VPU Diagnostic Tool Suite  v2.2.0
#  Launcher — loads modules from .\Modules\ and runs the GUI.
#
#  HOW TO RUN: double-click RunDiagnostic.bat  (handles elevation automatically)
# =============================================================================

$ScriptVersion = "2.2.0"

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
$NicDriverPatterns = @("Intel(R) 82574L*", "Intel(R) I210*")
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

$AnchorTLRB = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTLR  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorTLB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorTRB  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$AnchorBLR  = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorBL   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$AnchorTR   = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right

# Layout constants
$HdrH     = 68
$SbarH    = 28
$SideW    = 220
$ContentY = $HdrH
$ContentH = 760 - $HdrH - $SbarH   # 664
$NarrowW  = 800                      # camera panel (with right panel)
$WideW    = 1060                     # all other sections (no right panel)
$RightX   = $SideW + $NarrowW       # 1020
$RightW   = 259

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
$lblHdrTitle.Text      = "VPU Diagnostic Tool Suite"
$lblHdrTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$lblHdrTitle.ForeColor = [System.Drawing.Color]::White
$lblHdrTitle.Location  = New-Object System.Drawing.Point(64, 10)
$lblHdrTitle.Size      = New-Object System.Drawing.Size(700, 26)
$pnlHeader.Controls.Add($lblHdrTitle)

$lblHdrSub = New-Object System.Windows.Forms.Label
$lblHdrSub.Text      = "All-in-one diagnostic and troubleshooting tool for Pixellot VPU systems."
$lblHdrSub.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblHdrSub.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblHdrSub.Location  = New-Object System.Drawing.Point(66, 38)
$lblHdrSub.Size      = New-Object System.Drawing.Size(560, 16)
$pnlHeader.Controls.Add($lblHdrSub)

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
$pnlBadge.BackColor = [System.Drawing.Color]::FromArgb(220, 252, 231)
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
$sepHdr.Location  = New-Object System.Drawing.Point(0, $HdrH - 1)
$sepHdr.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sepHdr.Anchor    = $AnchorTLR
$pnlHeader.Controls.Add($sepHdr)

# ---- Bottom Status Bar -----------------------------------------------------
$pnlStatusBar = New-Object System.Windows.Forms.Panel
$pnlStatusBar.Size      = New-Object System.Drawing.Size(1280, $SbarH)
$pnlStatusBar.Location  = New-Object System.Drawing.Point(0, 760 - $SbarH)
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

# ---- Sidebar ---------------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Size      = New-Object System.Drawing.Size($SideW, $ContentH)
$sidebar.Location  = New-Object System.Drawing.Point(0, $HdrH)
$sidebar.BackColor = $ColSidebar
$sidebar.Anchor    = $AnchorTLB
$form.Controls.Add($sidebar)

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

# Keep New-SidebarButton as alias so existing internal code still works
function New-SidebarButton { param([string]$Text,[int]$Y,[bool]$Active=$false); return New-NavButton $Text $Y $Active }

$navSysOverview = New-NavButton "  System Overview"      8   $true
$navNetConfig   = New-NavButton "  Network Configuration" 52
$navCamera      = New-NavButton "  Camera Connectivity"  96
$navPoE         = New-NavButton "  PoE / NIC Hardware"   140
$navServices    = New-NavButton "  Pixellot Services"    184
$navDisk        = New-NavButton "  System & Disk Health" 228
$navEvents      = New-NavButton "  Event Viewer"         272

$sepNav = New-Object System.Windows.Forms.Panel
$sepNav.Size      = New-Object System.Drawing.Size(196, 1)
$sepNav.Location  = New-Object System.Drawing.Point(12, 320)
$sepNav.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)

$navReports  = New-NavButton "  Reports"  328
$navSettings = New-NavButton "  Settings" 372
$navAbout    = New-NavButton "  About"    416

# Hidden nav buttons kept for internal PerformClick() compatibility
$navOverview = New-NavButton "  Camera Connectivity" 96   # alias for $navCamera
$navTests    = New-NavButton "  Isolate"  0; $navTests.Visible   = $false
$navHistory  = New-NavButton "  History"  0; $navHistory.Visible = $false
$navHelp     = New-NavButton "  Help"     0; $navHelp.Visible    = $false

$sidebar.Controls.AddRange(@(
    $navSysOverview,$navNetConfig,$navCamera,$navPoE,$navServices,$navDisk,$navEvents,
    $sepNav,$navReports,$navSettings,$navAbout,
    $navTests,$navHistory,$navHelp
))

$sepUpdateSep = New-Object System.Windows.Forms.Panel
$sepUpdateSep.Size      = New-Object System.Drawing.Size(196, 1)
$sepUpdateSep.Location  = New-Object System.Drawing.Point(12, 468)
$sepUpdateSep.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$sidebar.Controls.Add($sepUpdateSep)

$lblUpdate = New-Object System.Windows.Forms.Label
$lblUpdate.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblUpdate.ForeColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
$lblUpdate.Location  = New-Object System.Drawing.Point(12, 478)
$lblUpdate.Size      = New-Object System.Drawing.Size(196, 32)
$lblUpdate.Visible   = $false
$sidebar.Controls.Add($lblUpdate)

$btnUpdate = New-Object System.Windows.Forms.Button
$btnUpdate.Text      = "  Update Now"
$btnUpdate.Size      = New-Object System.Drawing.Size(196, 28)
$btnUpdate.Location  = New-Object System.Drawing.Point(12, 514)
$btnUpdate.BackColor = [System.Drawing.Color]::FromArgb(251, 191, 36)
$btnUpdate.ForeColor = [System.Drawing.Color]::FromArgb(30, 27, 12)
$btnUpdate.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUpdate.FlatAppearance.BorderSize = 0
$btnUpdate.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5)
$btnUpdate.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnUpdate.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnUpdate.Visible   = $false
$btnUpdate.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 196, 28)), 5))
$sidebar.Controls.Add($btnUpdate)

# Sidebar VPU model (referenced by timer)
$lblVpuVal = New-Object System.Windows.Forms.Label
$lblVpuVal.Text      = "Detecting..."
$lblVpuVal.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5)
$lblVpuVal.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblVpuVal.Location  = New-Object System.Drawing.Point(14, 600)
$lblVpuVal.Size      = New-Object System.Drawing.Size(196, 36)
$sidebar.Controls.Add($lblVpuVal)

# Sidebar bottom status dot
$pnlSideDot = New-Object System.Windows.Forms.Panel
$pnlSideDot.Size      = New-Object System.Drawing.Size(8, 8)
$pnlSideDot.Location  = New-Object System.Drawing.Point(14, 644)
$pnlSideDot.BackColor = $ColGreen
$pnlSideDot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 8, 8)), 4))
$sidebar.Controls.Add($pnlSideDot)

$lblSideStatus = New-Object System.Windows.Forms.Label
$lblSideStatus.Text      = "Ready"
$lblSideStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
$lblSideStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$lblSideStatus.Location  = New-Object System.Drawing.Point(28, 638)
$lblSideStatus.Size      = New-Object System.Drawing.Size(170, 18)
$sidebar.Controls.Add($lblSideStatus)


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
$pnlReports  = New-StubPanel "Reports"  "Generate and manage diagnostic reports."
$pnlSettings = New-StubPanel "Settings" "Configure tool behavior and preferences."

# ---------- Nav panel registry (must be after all panels created) ------------
$script:allNavPanels = @(
    $pnlSysOverview,$center,$pnlGuide,$pnlHistory,$pnlHelp,$pnlNetwork,
    $pnlPoE,$pnlServices,$pnlDisk,$pnlEvents,$pnlReports,$pnlSettings
)

# ---------- Nav click handlers -----------------------------------------------
$navSysOverview.Add_Click({ Show-Panel $pnlSysOverview; Set-ActiveNav $navSysOverview })
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
        if ($osCaption) { $lblVpuVal.Text = "$($env:COMPUTERNAME)  ·  $($osCaption -replace 'Microsoft Windows ','Win ')" }
    } catch { }

    # Async update check — compares remote $ScriptVersion to current; shows notice if newer
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
    $timer.Stop(); $netTimer.Stop(); $svcTimer.Stop(); $diskTimer.Stop(); $evtTimer.Stop()
    $sync.Cancelled=$true; $sync.NetCancelled=$true; $sync.SvcCancelled=$true; $sync.DiskCancelled=$true; $sync.EvtCancelled=$true
    try { if ($script:runspace)    { $script:runspace.Close();    $script:runspace.Dispose()    } } catch { }
    try { if ($script:netRunspace) { $script:netRunspace.Close(); $script:netRunspace.Dispose() } } catch { }
    try { if ($script:svcRunspace) { $script:svcRunspace.Close(); $script:svcRunspace.Dispose() } } catch { }
    try { if ($script:diskRunspace){ $script:diskRunspace.Close();$script:diskRunspace.Dispose()} } catch { }
    try { if ($script:evtRunspace) { $script:evtRunspace.Close(); $script:evtRunspace.Dispose() } } catch { }
})

[System.Windows.Forms.Application]::Run($form)
