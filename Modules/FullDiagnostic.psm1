# =============================================================================
#  FullDiagnostic.psm1  -  Orchestrates all module diagnostics and shows a
#  one-page summary on the Home panel.
# =============================================================================

# --- Module definitions ------------------------------------------------------
# NavBtn is a scriptblock so it resolves at call-time (after form load).
$fdModuleDefs = @(
    @{ Name="System Overview";       Icon=0xE80F; NavBtn={$navSysInfo};   RunFn={Start-SysInfoCollection};    CompleteFn={$sync.SysInfoComplete}; RunningFn={$sync.SysInfoRunning}; CardKeys=@("SysInfo") }
    @{ Name="Network Configuration"; Icon=0xE701; NavBtn={$navNetConfig}; RunFn={$btnNetRun.PerformClick()};  CompleteFn={$sync.NetComplete};     RunningFn={$sync.NetRunning};     CardKeys=@("NetInternet","NetPorts","NetDomains") }
    @{ Name="Camera Connectivity";   Icon=0xE722; NavBtn={$navCamera};    RunFn={$btnRun.PerformClick()};     CompleteFn={$sync.Complete};        RunningFn={$sync.Running};        CardKeys=@("SmartSpeed","PingCHU","ChuDetect","PoEBudget") }
    @{ Name="Pixellot Services";     Icon=0xE9F5; NavBtn={$navServices};  RunFn={$btnSvcRun.PerformClick()};  CompleteFn={$sync.SvcComplete};     RunningFn={$sync.SvcRunning};     CardKeys=@("SvcStatus") }
    @{ Name="VPU Hardware";          Icon=0xE7E8; NavBtn={$navPoE};       RunFn={$btnHwRun.PerformClick()};   CompleteFn={$sync.HwComplete};      RunningFn={$sync.HwRunning};      CardKeys=@("HwGpu","HwMonitor","HwMmk") }
    @{ Name="Disk & System Health";  Icon=0xEDA2; NavBtn={$navDisk};      RunFn={$btnDiskRun.PerformClick()}; CompleteFn={$sync.DiskComplete};    RunningFn={$sync.DiskRunning};    CardKeys=@("DiskStatus","MemStatus") }
    @{ Name="Event Viewer";          Icon=0xE7BA; NavBtn={$navEvents};    RunFn={$btnEvtRun.PerformClick()};  CompleteFn={$sync.EvtComplete};     RunningFn={$sync.EvtRunning};     CardKeys=@("EvtStatus") }
)

# --- Helpers -----------------------------------------------------------------
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
    return ($parts -join "  ·  ")
}

# --- Panel -------------------------------------------------------------------
$pnlFullDiag = New-Object System.Windows.Forms.Panel
$pnlFullDiag.Size      = New-Object System.Drawing.Size($ContentW, $ContentH)
$pnlFullDiag.Location  = New-Object System.Drawing.Point(0, $ContentY)
$pnlFullDiag.BackColor = $ColBg
$pnlFullDiag.Anchor    = $AnchorTLRB
$pnlFullDiag.Visible   = $false
$form.Controls.Add($pnlFullDiag)

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

# Overall status banner
$pnlFdBanner = New-Object System.Windows.Forms.Panel
$pnlFdBanner.Size      = New-Object System.Drawing.Size(1220, 38)
$pnlFdBanner.Location  = New-Object System.Drawing.Point(30, 84)
$pnlFdBanner.BackColor = $ColCard
$pnlFdBanner.Visible   = $false
$pnlFdBanner.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 1220, 38)), 6))
$pnlFullDiag.Controls.Add($pnlFdBanner)

$lblFdBannerIcon = New-Object System.Windows.Forms.Label
$lblFdBannerIcon.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 13)
$lblFdBannerIcon.ForeColor = $ColGreen
$lblFdBannerIcon.Location  = New-Object System.Drawing.Point(14, 8)
$lblFdBannerIcon.AutoSize  = $true
$lblFdBannerIcon.BackColor = [System.Drawing.Color]::Transparent
$pnlFdBanner.Controls.Add($lblFdBannerIcon)

$lblFdBannerText = New-Object System.Windows.Forms.Label
$lblFdBannerText.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$lblFdBannerText.ForeColor = $ColGreen
$lblFdBannerText.Location  = New-Object System.Drawing.Point(44, 10)
$lblFdBannerText.AutoSize  = $true
$lblFdBannerText.BackColor = [System.Drawing.Color]::Transparent
$pnlFdBanner.Controls.Add($lblFdBannerText)

# --- Module rows -------------------------------------------------------------
$fdRows      = @()
$script:fdRowY    = 134
$fdRowH      = 54
$fdRowGap    = 6

foreach ($mod in $fdModuleDefs) {
    $rPnl = New-Object System.Windows.Forms.Panel
    $rPnl.Size      = New-Object System.Drawing.Size(1220, $fdRowH)
    $rPnl.Location  = New-Object System.Drawing.Point(30, $script:fdRowY)
    $rPnl.BackColor = $ColCard
    $rPnl.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 1220, $fdRowH)), 6))
    $pnlFullDiag.Controls.Add($rPnl)

    # Icon
    $iLbl = New-Object System.Windows.Forms.Label
    $iLbl.Text      = [char]$mod.Icon
    $iLbl.Font      = New-Object System.Drawing.Font("Segoe MDL2 Assets", 14)
    $iLbl.ForeColor = $ColAccent
    $iLbl.Location  = New-Object System.Drawing.Point(14, 13)
    $iLbl.Size      = New-Object System.Drawing.Size(28, 28)
    $iLbl.BackColor = [System.Drawing.Color]::Transparent
    $rPnl.Controls.Add($iLbl)

    # Module name
    $nLbl = New-Object System.Windows.Forms.Label
    $nLbl.Text      = $mod.Name
    $nLbl.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
    $nLbl.ForeColor = $ColText
    $nLbl.Location  = New-Object System.Drawing.Point(50, 17)
    $nLbl.Size      = New-Object System.Drawing.Size(220, 20)
    $nLbl.BackColor = [System.Drawing.Color]::Transparent
    $rPnl.Controls.Add($nLbl)

    # Status dot
    $sDot = New-Object System.Windows.Forms.Panel
    $sDot.Size      = New-Object System.Drawing.Size(10, 10)
    $sDot.Location  = New-Object System.Drawing.Point(280, 22)
    $sDot.BackColor = $ColMuted
    $sDot.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 10, 10)), 5))
    $rPnl.Controls.Add($sDot)

    # Status text
    $sLbl = New-Object System.Windows.Forms.Label
    $sLbl.Text      = "Waiting"
    $sLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $sLbl.ForeColor = $ColMuted
    $sLbl.Location  = New-Object System.Drawing.Point(298, 17)
    $sLbl.Size      = New-Object System.Drawing.Size(110, 20)
    $sLbl.BackColor = [System.Drawing.Color]::Transparent
    $rPnl.Controls.Add($sLbl)

    # Value / summary text
    $vLbl = New-Object System.Windows.Forms.Label
    $vLbl.Text      = ""
    $vLbl.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $vLbl.ForeColor = $ColMuted
    $vLbl.Location  = New-Object System.Drawing.Point(416, 17)
    $vLbl.Size      = New-Object System.Drawing.Size(676, 20)
    $vLbl.BackColor = [System.Drawing.Color]::Transparent
    $rPnl.Controls.Add($vLbl)

    # View button
    $vBtn = New-Object System.Windows.Forms.Button
    $vBtn.Text      = "View  " + [char]0xE76C
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

    $fdRows += @{ Panel=$rPnl; Dot=$sDot; StatusLbl=$sLbl; ValueLbl=$vLbl; ViewBtn=$vBtn }
    $script:fdRowY += $fdRowH + $fdRowGap
}

# --- Bottom buttons ----------------------------------------------------------
$btnFdRerun = New-Object System.Windows.Forms.Button
$btnFdRerun.Text      = [char]0x25B6 + "  Re-run Full Diagnostic"
$btnFdRerun.Size      = New-Object System.Drawing.Size(240, 40)
$btnFdRerun.Location  = New-Object System.Drawing.Point(30, 566)
$btnFdRerun.BackColor = $ColAccent
$btnFdRerun.ForeColor = [System.Drawing.Color]::White
$btnFdRerun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFdRerun.FlatAppearance.BorderSize = 0
$btnFdRerun.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 9.5)
$btnFdRerun.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFdRerun.Enabled   = $false
$btnFdRerun.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 240, 40)), 6))
$pnlFullDiag.Controls.Add($btnFdRerun)

$btnFdBack = New-Object System.Windows.Forms.Button
$btnFdBack.Text      = [char]0xE76B + "  Back to Home"
$btnFdBack.Size      = New-Object System.Drawing.Size(160, 40)
$btnFdBack.Location  = New-Object System.Drawing.Point(286, 566)
$btnFdBack.BackColor = $ColNavHover
$btnFdBack.ForeColor = $ColText
$btnFdBack.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFdBack.FlatAppearance.BorderSize = 0
$btnFdBack.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnFdBack.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnFdBack.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 160, 40)), 6))
$btnFdBack.Add_Click({ $navSysOverview.PerformClick() })
$pnlFullDiag.Controls.Add($btnFdBack)

# --- Timer -------------------------------------------------------------------
$timerFullDiag          = New-Object System.Windows.Forms.Timer
$timerFullDiag.Interval = 300
$script:fdSpinIdx       = 0
$script:fdStartTime     = $null
$script:fdSpinChars     = @('|','/','-','\')

$timerFullDiag.Add_Tick({
    $script:fdSpinIdx = ($script:fdSpinIdx + 1) % 4
    $spin    = $script:fdSpinChars[$script:fdSpinIdx]
    $allDone = $true
    $anyIssue = $false

    for ($i = 0; $i -lt $fdModuleDefs.Count; $i++) {
        $mod      = $fdModuleDefs[$i]
        $row      = $fdRows[$i]
        $complete = & $mod.CompleteFn
        $running  = & $mod.RunningFn

        if (-not $complete) {
            $allDone = $false
            if ($running) {
                $row.Dot.BackColor       = $ColAccent
                $row.StatusLbl.Text      = "$spin  Running"
                $row.StatusLbl.ForeColor = $ColAccent
            }
        } else {
            if ($row.ViewBtn.Enabled) { continue }   # already painted
            $worst = Get-WorstCardStatus $mod.CardKeys
            $dotC  = switch ($worst) { "fail"{$ColRed} "warn"{$ColYellow} "ok"{$ColGreen} default{$ColMuted} }
            $statT = switch ($worst) { "fail"{"Issues Found"} "warn"{"Warning"} "ok"{"Pass"} default{"Complete"} }
            $row.Dot.BackColor       = $dotC
            $row.StatusLbl.Text      = $statT
            $row.StatusLbl.ForeColor = $dotC
            $row.ValueLbl.Text       = Get-ModuleSummaryText $mod.CardKeys
            $row.ViewBtn.Enabled     = $true
            if ($worst -in @("fail","warn")) { $anyIssue = $true }
        }

        # Re-evaluate anyIssue for already-painted rows
        if ($complete -and $row.ViewBtn.Enabled) {
            $w = Get-WorstCardStatus $mod.CardKeys
            if ($w -in @("fail","warn")) { $anyIssue = $true }
        }
    }

    if ($allDone) {
        $timerFullDiag.Stop()
        $elapsed = [int]((Get-Date) - $script:fdStartTime).TotalSeconds
        $lblFdSub.Text = "Completed in ${elapsed}s  ·  $(Get-Date -Format 'MM/dd HH:mm')"

        if ($anyIssue) {
            $pnlFdBanner.BackColor     = [System.Drawing.Color]::FromArgb(55, 20, 20)
            $lblFdBannerIcon.Text      = [char]0xE783
            $lblFdBannerIcon.ForeColor = $ColRed
            $lblFdBannerText.Text      = "Issues found — review highlighted modules below"
            $lblFdBannerText.ForeColor = $ColRed
        } else {
            $pnlFdBanner.BackColor     = [System.Drawing.Color]::FromArgb(15, 48, 28)
            $lblFdBannerIcon.Text      = [char]0xE73E
            $lblFdBannerIcon.ForeColor = $ColGreen
            $lblFdBannerText.Text      = "All systems healthy — no issues detected"
            $lblFdBannerText.ForeColor = $ColGreen
        }
        $pnlFdBanner.Visible = $true
        $btnFdRerun.Enabled  = $true
    }
})

$btnFdRerun.Add_Click({ Start-FullDiagnostic })

# --- Public entry point ------------------------------------------------------
function Start-FullDiagnostic {
    Show-Panel $pnlFullDiag
    Set-ActiveNav $navSysOverview

    $pnlFdBanner.Visible = $false
    $btnFdRerun.Enabled  = $false
    $script:fdStartTime  = Get-Date
    $script:fdSpinIdx    = 0
    $lblFdSub.Text       = "Running all checks — this takes about 60 seconds..."

    foreach ($row in $fdRows) {
        $row.Dot.BackColor       = $ColMuted
        $row.StatusLbl.Text      = "Waiting"
        $row.StatusLbl.ForeColor = $ColMuted
        $row.ValueLbl.Text       = ""
        $row.ViewBtn.Enabled     = $false
    }

    # Fire all module diagnostics in parallel
    Start-SysInfoCollection
    $btnNetRun.PerformClick()
    $btnRun.PerformClick()
    $btnSvcRun.PerformClick()
    $btnHwRun.PerformClick()
    $btnDiskRun.PerformClick()
    $btnEvtRun.PerformClick()

    $timerFullDiag.Start()
}
