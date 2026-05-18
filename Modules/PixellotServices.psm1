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

    # D6 fix: Pixellot-installed pre-gate. On a non-VPU Windows box (developer
    # laptop, support tech's machine, demo VM) the required-process check
    # produces "4 required processes not running" Critical + a misleading
    # "Restart the missing process(es) or reboot the VPU" recommendation.
    # Detect the Pixellot install before declaring any process Critical.
    $sync.SvcStep = "Detecting Pixellot install..."
    $pixellotInstalled = $false
    $pixellotIndicators = @(
        "HKLM:\SOFTWARE\Pixellot",
        "HKLM:\SOFTWARE\WOW6432Node\Pixellot",
        "C:\Pixellot",
        "C:\Pixellot\Agent",
        "C:\Pixellot\Coordinator"
    )
    foreach ($ind in $pixellotIndicators) {
        if (Test-Path $ind -ErrorAction SilentlyContinue) { $pixellotInstalled = $true; break }
    }
    if (-not $pixellotInstalled) {
        # Last-resort heuristic: a recent Pixellot service entry counts.
        try {
            $svc = Get-Service | Where-Object { $_.Name -like "Pixellot*" -or $_.Name -like "Scoreconnect*" }
            if ($svc) { $pixellotInstalled = $true }
        } catch { }
    }

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
        } elseif (-not $pixellotInstalled) {
            # D6 fix: degrade missing process to neutral / Not Installed instead
            # of Critical, so a non-VPU box doesn't masquerade as a broken VPU.
            Svc-Log $r.Label "Not installed on this machine" "Gray"
            $sync.Cards[$r.CardKey] = @{ Value = "Not installed"; Status = "neutral" }
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
    if (-not $pixellotInstalled) {
        # D6 fix: distinct status for non-VPU machine. Suppresses the
        # "Restart the missing process(es) or reboot the VPU" recommendation
        # cascade in FullDiagnostic and lets the home banner say "Unknown"
        # rather than "Critical" for a developer / support laptop.
        $sync.Cards["SvcStatus"] = @{ Value="Pixellot not detected on this machine"; Status="neutral" }
    } elseif ($critFail -gt 0) {
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

        # R2: surface any runspace errors.
        $svcErrs = Get-DiagRunspaceErrors $script:svcState
        foreach ($em in $svcErrs) { Add-LogRow $dgvSvcLog "Runspace error" $em "Fail" }

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
    # R2/R13: standardised runspace hosting.
    $script:svcState = Start-DiagRunspace `
        -Script    $SvcScript `
        -Parameters @{ sync = $sync } `
        -Previous   $script:svcState
    $script:svcRunspace = $script:svcState.Runspace
    $script:svcPs       = $script:svcState.Ps
    $svcTimer.Start()
}

$btnSvcRun.Add_Click({ Start-SvcDiagnostic })
$btnSvcCancel.Add_Click({ $sync.SvcCancelled=$true; $btnSvcCancel.Visible=$false })
