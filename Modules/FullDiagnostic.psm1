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
    @{ Name="Hardware & Peripherals";Icon=0xE7E8; NavBtn={$navPoE};       RunFn={Start-HwDiagnostic};         CompleteFn={$sync.HwComplete};      RunningFn={$sync.HwRunning};      CardKeys=@("HwGpu","HwMonitor","HwMmk") }
    @{ Name="Disk & System Health";  Icon=0xEDA2; NavBtn={$navDisk};      RunFn={Start-DiskDiagnostic};       CompleteFn={$sync.DiskComplete};    RunningFn={$sync.DiskRunning};    CardKeys=@("DiskStatus") }
    @{ Name="Event Viewer";          Icon=0xE7BA; NavBtn={$navEvents};    RunFn={Start-EvtDiagnostic};        CompleteFn={$sync.EvtComplete};     RunningFn={$sync.EvtRunning};     CardKeys=@("EvtStatus") }
)

# Indices being re-run in a partial run; empty means all modules.
$script:fdRerunIndices = @()

# --- Status helpers -----------------------------------------------------------
function Get-WorstCardStatus {
    param([string[]]$Keys)
    # Priority: fail > warn > ok > neutral. "neutral" = card was never populated
    # (runspace exception, missing module, cancellation). The caller must
    # distinguish "neutral" from "ok" in the rollup — collapsing them produces a
    # false-Pass (D1 from the diagnostic-logic review).
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
        # Defensive against empty-string status (D21): explicitly treat as neutral.
        if ($s -in @("", $null)) { continue }
        if ($pri.ContainsKey($s) -and $pri[$s] -gt $pri[$worst]) { $worst = $s }
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
    # D11 fix: don't ever claim the module succeeded ("All cameras online ...")
    # when worst is neutral. Caller still shows the muted Unknown dot.
    if ($Worst -eq "neutral") { return "Check did not complete" }
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
        4 { # Hardware & Peripherals
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

# Per-module next-step recommendation (shown only for Warning / Critical / Unknown).
function Get-FdActionText {
    param([int]$Idx, [string]$Worst)
    if ($Worst -eq "neutral") {
        # D1 fix: a module that completed without populating any card is treated
        # as Unknown, not Healthy. Tell the tech to look at the owning panel.
        return "Check did not complete - open the module's panel and run it manually"
    }
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

# R12: stagger module-start invocations. Previously every module's runspace
# opened in the same tick — WMI/CIM on stressed Win10 LTSC routinely throttles
# concurrent queries and a 7-way burst could hit 0x80041032 / 60 s timeouts.
# 250 ms between starts keeps the total startup under 2 s while letting each
# runspace's first WMI query land cleanly.
function Invoke-FdModulesStaggered {
    param([hashtable[]]$Modules, [int]$DelayMs = 250)
    if (-not $Modules -or $Modules.Count -eq 0) { return }
    # Fire the first immediately so the UI has visible motion right away.
    Invoke-FdModule $Modules[0]
    if ($Modules.Count -eq 1) { return }
    # Stagger the remaining via a one-shot timer chain. We can't use Start-Sleep
    # here because we're on the UI thread; blocking it would freeze the form.
    $script:fdStaggerQueue = [System.Collections.ArrayList]::new()
    for ($i = 1; $i -lt $Modules.Count; $i++) { [void]$script:fdStaggerQueue.Add($Modules[$i]) }
    if (-not $script:fdStaggerTimer) {
        $script:fdStaggerTimer = New-Object System.Windows.Forms.Timer
        $script:fdStaggerTimer.Add_Tick({
            if ($script:fdStaggerQueue.Count -eq 0) {
                $script:fdStaggerTimer.Stop()
                return
            }
            $next = $script:fdStaggerQueue[0]
            $script:fdStaggerQueue.RemoveAt(0)
            Invoke-FdModule $next
        })
    }
    $script:fdStaggerTimer.Interval = $DelayMs
    $script:fdStaggerTimer.Start()
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
    $allDone      = $true
    $critCount    = 0
    $warnCount    = 0
    $unknownCount = 0
    $critNames    = @()
    $warnNames    = @()
    $unknownNames = @()

    for ($i = 0; $i -lt $fdModuleDefs.Count; $i++) {
        $mod      = $fdModuleDefs[$i]
        $row      = $fdRows[$i]
        $complete = & $mod.CompleteFn
        $running  = & $mod.RunningFn

        # ---- Module not part of this run (partial re-run) --------------------
        if ($script:fdRerunIndices.Count -gt 0 -and $i -notin $script:fdRerunIndices) {
            # Include its prior result in the overall count, then skip it.
            $w = $row.LastWorst
            if ($w -eq "fail")        { $critCount++;    $critNames    += $mod.Name }
            elseif ($w -eq "warn")    { $warnCount++;    $warnNames    += $mod.Name }
            elseif ($w -eq "neutral") { $unknownCount++; $unknownNames += $mod.Name }
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

        if     ($worst -eq "fail")    { $critCount++;    $critNames    += $mod.Name }
        elseif ($worst -eq "warn")    { $warnCount++;    $warnNames    += $mod.Name }
        elseif ($worst -eq "neutral") { $unknownCount++; $unknownNames += $mod.Name }

        # Paint the row only once (ViewBtn.Enabled flips false -> true as the guard).
        if (-not $row.ViewBtn.Enabled) {
            # D1 fix: neutral now paints as Unknown (muted dot, "Check did not complete"),
            # not as Healthy. The default branch is intentionally NOT green any more.
            $dotColor  = switch ($worst) { "fail"{$ColRed}      "warn"{$ColYellow} "ok"{$ColGreen} default{$ColMuted} }
            $severityT = switch ($worst) { "fail"{"Critical"}   "warn"{"Warning"}  "ok"{"Healthy"} default{"Unknown"} }

            $row.Dot.BackColor       = $dotColor
            $row.StatusLbl.Text      = $severityT
            $row.StatusLbl.ForeColor = $dotColor

            $row.ValueLbl.Text       = Get-FdModuleSummary $i $worst
            $row.ValueLbl.ForeColor  = if ($worst -in @("fail","warn")) { $ColText } else { $ColMuted }

            # Suggested action - shown for Warning / Critical / Unknown
            $action = Get-FdActionText $i $worst
            if ($action) {
                $row.ActionLbl.Text      = $action
                $row.ActionLbl.ForeColor = switch ($worst) {
                    "fail"    { $ColRed }
                    "warn"    { $ColYellow }
                    "neutral" { $ColMuted }
                    default   { $ColYellow }
                }
                $row.ActionLbl.Visible   = $true
            }

            # Background tint for issue rows (no tint for unknown - keep card neutral)
            if ($worst -eq "fail") {
                $row.Panel.BackColor = $ColFailBg
            } elseif ($worst -eq "warn") {
                $row.Panel.BackColor = $ColWarnBg
            }

            # Accent the View button for anything that needs attention
            if ($worst -in @("fail","warn","neutral")) {
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
        if ($unknownCount -gt 0) { $parts += "$unknownCount unknown" }
        $lblFdBannerText.Text      = ($parts -join ", ") + " detected - review highlighted modules below"
        $lblFdBannerText.ForeColor = $ColRed

        # Detail line: module names + severity
        $nameList = @()
        $nameList += $critNames    | ForEach-Object { "$_ (Critical)" }
        $nameList += $warnNames    | ForEach-Object { "$_ (Warning)" }
        $nameList += $unknownNames | ForEach-Object { "$_ (Unknown)" }
        $lblFdBannerDetail.Text      = $nameList -join "   |   "
        $lblFdBannerDetail.ForeColor = [System.Drawing.Color]::FromArgb(210, 140, 140)

    } elseif ($unknownCount -gt 0) {
        # --- Some checks didn't run (D1 fix) ---
        # Distinct from both "all clear" and "issues found". Prevents the
        # false-Pass where every module crashed silently and the banner
        # claimed "All N checks passed - this VPU appears healthy."
        $pnlFdBanner.BackColor = $ColWarnBg

        $lblFdBannerIcon.Text      = [char]0xE7BA   # info/help
        $lblFdBannerIcon.ForeColor = $ColYellow

        $okCount = $fdModuleDefs.Count - $unknownCount
        $lblFdBannerText.Text      = "$unknownCount of $($fdModuleDefs.Count) checks did not complete - cannot confirm VPU health"
        $lblFdBannerText.ForeColor = $ColYellow

        $names = ($unknownNames | ForEach-Object { "$_ (Unknown)" }) -join "   |   "
        $lblFdBannerDetail.Text      = "$okCount passed | Open the affected panels and re-run manually. Details: $names"
        $lblFdBannerDetail.ForeColor = [System.Drawing.Color]::FromArgb(220, 200, 130)

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

    $rerunMods = @($toRerun | ForEach-Object { $fdModuleDefs[$_] })
    Invoke-FdModulesStaggered -Modules $rerunMods

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

    Invoke-FdModulesStaggered -Modules $fdModuleDefs

    $timerFullDiag.Start()
}
