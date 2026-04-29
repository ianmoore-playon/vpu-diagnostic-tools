# =============================================================================
#  SystemOverview.psm1  -  System Overview hub panel
# =============================================================================

# ---- System Overview Hub ---------------------------------------------------
$pnlSysOverview = New-Object System.Windows.Forms.Panel
$pnlSysOverview.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlSysOverview.Location  = New-Object System.Drawing.Point($SideW, $HdrH)
$pnlSysOverview.BackColor = $ColBg
$pnlSysOverview.Anchor    = $AnchorTLRB
$form.Controls.Add($pnlSysOverview)

$lblHubTitle = New-Object System.Windows.Forms.Label
$lblHubTitle.Text      = "VPU Diagnostic Tool Suite"
$lblHubTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$lblHubTitle.ForeColor = $ColText
$lblHubTitle.Location  = New-Object System.Drawing.Point(30, 32)
$lblHubTitle.Size      = New-Object System.Drawing.Size(700, 34)
$pnlSysOverview.Controls.Add($lblHubTitle)

$lblHubSub = New-Object System.Windows.Forms.Label
$lblHubSub.Text      = "All-in-one diagnostic and troubleshooting tool for Pixellot VPU systems."
$lblHubSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblHubSub.ForeColor = $ColMuted
$lblHubSub.Location  = New-Object System.Drawing.Point(30, 72)
$lblHubSub.Size      = New-Object System.Drawing.Size(800, 20)
$pnlSysOverview.Controls.Add($lblHubSub)

function New-SectionCard {
    param([string]$Title,[string]$Desc,[int]$IconCode,[int]$X,[int]$Y,[int]$W=234,[int]$H=128)
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Size      = New-Object System.Drawing.Size($W, $H)
    $pnl.Location  = New-Object System.Drawing.Point($X, $Y)
    $pnl.BackColor = [System.Drawing.Color]::White
    $pnl.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $pnl.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, $W, $H)), 8))
    $pnl.Add_Paint({
        $g = $args[1].Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $bp  = [GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, ([int]$this.Width - 1), ([int]$this.Height - 1))), 8)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(226, 232, 240), 1)
        $g.DrawPath($pen, $bp); $pen.Dispose(); $bp.Dispose()
    })
    $iLbl = New-Object System.Windows.Forms.Label
    $iLbl.Text      = [char]$IconCode
    $iLbl.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 16)
    $iLbl.ForeColor = $ColAccent
    $iLbl.Location  = New-Object System.Drawing.Point(16, 16)
    $iLbl.Size      = New-Object System.Drawing.Size(36, 32)
    $iLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($iLbl)
    $tLbl = New-Object System.Windows.Forms.Label
    $tLbl.Text      = $Title
    $tLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $tLbl.ForeColor = $ColText
    $tLbl.Location  = New-Object System.Drawing.Point(16, 56)
    $tLbl.Size      = New-Object System.Drawing.Size($W - 24, 20)
    $tLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($tLbl)
    $dLbl = New-Object System.Windows.Forms.Label
    $dLbl.Text      = $Desc
    $dLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $dLbl.ForeColor = $ColMuted
    $dLbl.Location  = New-Object System.Drawing.Point(16, 80)
    $dLbl.Size      = New-Object System.Drawing.Size($W - 24, 34)
    $dLbl.BackColor = [System.Drawing.Color]::Transparent
    $pnl.Controls.Add($dLbl)
    return $pnl
}

$hubCardDefs = @(
    @{Nav="navSysOverview"; Title="System Overview";       Desc="Hardware and OS information";        Icon=0xE80F; R=0;C=0}
    @{Nav="navNetConfig";   Title="Network Configuration"; Desc="IP, DNS, firewall and connectivity"; Icon=0xE701;R=0;C=1}
    @{Nav="navCamera";      Title="Camera Connectivity";   Desc="Cameras, NICs and link status";      Icon=0xE722;R=0;C=2}
    @{Nav="navServices";    Title="Pixellot Services";     Desc="Services status and logs";            Icon=0xE9F5;R=0;C=3}
    @{Nav="navPoE";         Title="PoE / NIC Hardware";    Desc="PoE ports, NICs and hardware";       Icon=0xE7E8;R=1;C=0}
    @{Nav="navDisk";        Title="System & Disk Health";  Desc="Disk space, performance and health"; Icon=0xEDA2;R=1;C=1}
    @{Nav="navEvents";      Title="Event Viewer";           Desc="Critical and warning events";        Icon=0xE7BA;R=1;C=2}
    @{Nav="navReports";     Title="Reports";                Desc="Generate and export reports";        Icon=0xE7C3;R=1;C=3}
)
$hCW = 234; $hCH = 128; $hGap = 10
$hRowY = @(106, 248)
foreach ($hc in $hubCardDefs) {
    $hx = 30 + $hc.C * ($hCW + $hGap)
    $hy = $hRowY[$hc.R]
    $cp = New-SectionCard -Title $hc.Title -Desc $hc.Desc -IconCode $hc.Icon -X $hx -Y $hy -W $hCW -H $hCH
    $pnlSysOverview.Controls.Add($cp)
    $navBtn = Get-Variable -Name $hc.Nav -ValueOnly
    $clickBlock = { $navBtn.PerformClick() }.GetNewClosure()
    $cp.Add_Click($clickBlock)
    foreach ($ctrl in @($cp.Controls)) { $ctrl.Add_Click($clickBlock) }
}

$btnHubRun = New-Object System.Windows.Forms.Button
$btnHubRun.Text      = [char]0x25B6 + "  Run Full Diagnostic"
$btnHubRun.Size      = New-Object System.Drawing.Size(260, 44)
$btnHubRun.Location  = New-Object System.Drawing.Point(30, 396)
$btnHubRun.BackColor = $ColAccent
$btnHubRun.ForeColor = [System.Drawing.Color]::White
$btnHubRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHubRun.FlatAppearance.BorderSize = 0
$btnHubRun.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$btnHubRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnHubRun.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnHubRun.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 260, 44)), 7))
$pnlSysOverview.Controls.Add($btnHubRun)

$btnHubLastReport = New-Object System.Windows.Forms.Button
$btnHubLastReport.Text      = "Open Last Report"
$btnHubLastReport.Size      = New-Object System.Drawing.Size(180, 44)
$btnHubLastReport.Location  = New-Object System.Drawing.Point(300, 396)
$btnHubLastReport.BackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$btnHubLastReport.ForeColor = $ColText
$btnHubLastReport.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnHubLastReport.FlatAppearance.BorderSize = 0
$btnHubLastReport.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
$btnHubLastReport.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnHubLastReport.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 180, 44)), 7))
$pnlSysOverview.Controls.Add($btnHubLastReport)

$btnHubRun.Add_Click({ $navCamera.PerformClick(); $btnRun.PerformClick() })
$btnHubLastReport.Add_Click({
    $latest = Get-ChildItem -Path $OutputDir -Filter "CameraLink_Results_*.txt" -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { Start-Process notepad.exe $latest.FullName }
    else { [System.Windows.Forms.MessageBox]::Show("No reports found yet.", "Open Last Report", "OK", "Information") | Out-Null }
})

