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

    $critFail = 0   # required processes that are NOT running
    $warnCount = 0  # non-critical issues (Scoreconnect stopped, etc.)

    # ── Section 1: Core Pixellot Processes ────────────────────────────────────
    # These four must always be running. VPU.exe is informational only.
    $sync.SvcStep = "Checking core Pixellot processes..."
    Svc-Section "Core Pixellot Processes"

    $required = @(
        @{ Proc="Agent";       Label="Agent.exe";       Note="" }
        @{ Proc="KeepAgentUp"; Label="KeepAgentUp.exe"; Note="" }
        @{ Proc="Coordinator"; Label="Coordinator.exe"; Note="" }
        @{ Proc="LogMeIn";     Label="LogMeIn.exe";     Note="" }
    )

    foreach ($r in $required) {
        if ($sync.SvcCancelled) { $sync.SvcRunning=$false; $sync.SvcComplete=$true; return }
        $procs = @(Get-Process -Name $r.Proc -ErrorAction SilentlyContinue)
        if ($procs.Count -gt 0) {
            $pidStr = ($procs | ForEach-Object { $_.Id }) -join ", "
            Svc-Log $r.Label "Running  (PID $pidStr)" "Pass"
        } else {
            Svc-Log $r.Label "NOT running" "Fail"
            $critFail++
        }
    }

    # VPU.exe — informational only; not running is normal when cameras are idle
    if (-not $sync.SvcCancelled) {
        $vpuProc = @(Get-Process -Name "VPU" -ErrorAction SilentlyContinue)
        if ($vpuProc.Count -gt 0) {
            $pidStr = ($vpuProc | ForEach-Object { $_.Id }) -join ", "
            Svc-Log "VPU.exe" "Running  (PID $pidStr)  — cameras active" "Pass"
        } else {
            Svc-Log "VPU.exe" "Not running  — normal when cameras are idle" "Gray"
        }
    }

    # ── Section 2: Scoreconnect ───────────────────────────────────────────────
    # Covers v1, v2, and v3 via wildcard.  Missing = not installed (not a fault).
    if ($sync.SvcCancelled) { $sync.SvcRunning=$false; $sync.SvcComplete=$true; return }
    $sync.SvcStep = "Checking Scoreconnect..."
    Svc-Section "Scoreconnect"

    # Windows service (wildcard matches Scoreconnect I / II / III)
    $scSvcs = @()
    try { $scSvcs += @(Get-Service -Name        "Scoreconnect*" -ErrorAction SilentlyContinue) } catch {}
    try { $scSvcs += @(Get-Service -DisplayName "Scoreconnect*" -ErrorAction SilentlyContinue) } catch {}
    # Deduplicate by service name
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

    # Process check (exe may run independently of the service)
    $scProcs = @(Get-Process -Name "Scoreconnect*" -ErrorAction SilentlyContinue)
    if ($scProcs.Count -gt 0) {
        foreach ($p in $scProcs) {
            Svc-Log "$($p.Name).exe" "Running  (PID $($p.Id))" "Pass"
        }
    } elseif ($scSvcs.Count -gt 0) {
        # Service is registered but process not found — add context
        Svc-Log "Scoreconnect*.exe" "Process not running" "Warn"
        $warnCount++
    } else {
        # Neither service nor process found — likely not installed on this VPU
        Svc-Log "Scoreconnect" "Not detected on this VPU" "Gray"
    }

    # ── Section 3: System Dependencies ───────────────────────────────────────
    if ($sync.SvcCancelled) { $sync.SvcRunning=$false; $sync.SvcComplete=$true; return }
    $sync.SvcStep = "Checking system dependencies..."
    Svc-Section "System Dependencies"
    foreach ($dep in @(
        @{Name="W32Time";  Label="Windows Time (NTP)"}
        @{Name="Dnscache"; Label="DNS Client"}
        @{Name="Dhcp";     Label="DHCP Client"}
        @{Name="EventLog"; Label="Windows Event Log"}
        @{Name="wuauserv"; Label="Windows Update"}
    )) {
        if ($sync.SvcCancelled) { break }
        try {
            $s = Get-Service -Name $dep.Name -ErrorAction Stop
            Svc-Log $dep.Label $s.Status.ToString() $(if($s.Status -eq "Running"){"Pass"}else{"Warn"})
        } catch { Svc-Log $dep.Label "Not found" "Gray" }
    }

    # ── Card summary ─────────────────────────────────────────────────────────
    if ($critFail -gt 0) {
        $noun = if ($critFail -eq 1) { "process" } else { "processes" }
        $sync.Cards["SvcStatus"] = @{ Value="$critFail required $noun not running"; Status="fail" }
    } elseif ($warnCount -gt 0) {
        $sync.Cards["SvcStatus"] = @{ Value="Core processes OK — Scoreconnect needs attention"; Status="warn" }
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
$lblSvcSub.Text = "Checks required Pixellot processes, Scoreconnect service, and system dependencies."
$lblSvcSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblSvcSub.ForeColor = $ColMuted
$lblSvcSub.Location = New-Object System.Drawing.Point(10,42); $lblSvcSub.Size = New-Object System.Drawing.Size(1240,18)
$pnlServices.Controls.Add($lblSvcSub)
$svcCardDefs = @(
    @{ Key="SvcStatus"; Title="Services"; Sub="Running / total"; X=10; Icon=[char]0xE9F5; W=250 }
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
$btnSvcCancel = New-Object System.Windows.Forms.Button; $btnSvcCancel.Text = "Cancel"
$btnSvcCancel.Size = New-Object System.Drawing.Size(100,40); $btnSvcCancel.Location = New-Object System.Drawing.Point(238,170)
$btnSvcCancel.BackColor = $ColRed; $btnSvcCancel.ForeColor = [System.Drawing.Color]::White
$btnSvcCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnSvcCancel.FlatAppearance.BorderSize = 0
$btnSvcCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnSvcCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnSvcCancel.Visible = $false
$pnlServices.Controls.Add($btnSvcCancel)
$btnSvcCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))
$lblSvcStatus = New-Object System.Windows.Forms.Label; $lblSvcStatus.Text = ""
$lblSvcStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblSvcStatus.ForeColor = $ColMuted
$lblSvcStatus.Location = New-Object System.Drawing.Point(10,218); $lblSvcStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlServices.Controls.Add($lblSvcStatus)
$lblSvcLogHdr = New-Object System.Windows.Forms.Label; $lblSvcLogHdr.Text = "Service Status"
$lblSvcLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblSvcLogHdr.ForeColor = $ColText
$lblSvcLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblSvcLogHdr.AutoSize = $true
$pnlServices.Controls.Add($lblSvcLogHdr)
$dgvSvcLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlServices.Controls.Add($dgvSvcLog)
$script:svcRunspace = $null; $script:svcSpinIdx = 0


$btnSvcRun.Add_Click({
    if ($sync.SvcRunning) { return }
    $sync.SvcCancelled = $false
    $sync.Cards["SvcStatus"] = @{ Value="--"; Status="neutral" }
    foreach ($key in $svcCards.Keys) { Update-CardStatus -Card $svcCards[$key] -Value "--" -Status "neutral" }
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

