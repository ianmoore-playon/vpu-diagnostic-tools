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
$script:svcRunspace = $null; $script:svcSpinIdx = 0


$btnSvcRun.Add_Click({
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
    $script:svcRunspace = [runspacefactory]::CreateRunspace()
    $script:svcRunspace.ApartmentState="STA"; $script:svcRunspace.ThreadOptions="ReuseThread"; $script:svcRunspace.Open()
    $ps = [powershell]::Create(); $ps.Runspace=$script:svcRunspace
    $ps.AddScript($SvcScript) | Out-Null
    $ps.AddParameters(@{ sync=$sync }) | Out-Null
    $ps.BeginInvoke() | Out-Null; $svcTimer.Start()
})
$btnSvcCancel.Add_Click({ $sync.SvcCancelled=$true; $btnSvcCancel.Visible=$false })
