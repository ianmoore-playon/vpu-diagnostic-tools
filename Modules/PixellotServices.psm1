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

    $sync.SvcStep = "Checking Pixellot services..."
    Svc-Section "Pixellot Services"
    $allSvcs = @()
    foreach ($p in @("Pixellot*","pxl*","CanopyAgent*","SportzCast*")) {
        try { $allSvcs += @(Get-Service -Name $p -ErrorAction SilentlyContinue) } catch { }
    }
    if ($allSvcs.Count -gt 0) {
        $running = 0
        foreach ($svc in ($allSvcs | Sort-Object DisplayName)) {
            if ($sync.SvcCancelled) { break }
            $lvl = if ($svc.Status -eq "Running") { $running++; "Pass" } else { "Warn" }
            Svc-Log $svc.DisplayName $svc.Status.ToString() $lvl
        }
        $sync.Cards["SvcStatus"] = @{ Value="$running/$($allSvcs.Count) running"; Status=if($running -lt $allSvcs.Count){"warn"}else{"ok"} }
    } else {
        Svc-Log "Pixellot services" "None found on this system" "Gray"
        $sync.Cards["SvcStatus"] = @{ Value="None found"; Status="neutral" }
    }
    if ($sync.SvcCancelled) { $sync.SvcRunning=$false; $sync.SvcComplete=$true; return }

    $sync.SvcStep = "Checking system dependencies..."
    Svc-Section "System Dependencies"
    foreach ($dep in @(
        @{Name="W32Time";     Label="Windows Time (NTP)"}
        @{Name="Dnscache";    Label="DNS Client"}
        @{Name="Dhcp";        Label="DHCP Client"}
        @{Name="EventLog";    Label="Windows Event Log"}
        @{Name="wuauserv";    Label="Windows Update"}
    )) {
        if ($sync.SvcCancelled) { break }
        try {
            $s = Get-Service -Name $dep.Name -ErrorAction Stop
            Svc-Log $dep.Label $s.Status.ToString() $(if($s.Status -eq "Running"){"Pass"}else{"Warn"})
        } catch { Svc-Log $dep.Label "Not found" "Gray" }
    }

    $sync.SvcStep = "Complete"; $sync.SvcRunning=$false; $sync.SvcComplete=$true
}


# ---------- Services timer --------------------------------------------------
$svcTimer = New-Object System.Windows.Forms.Timer; $svcTimer.Interval = 300
$svcTimer.Add_Tick({
    $svcItem = $null
    while ($sync.SvcQueue.TryDequeue([ref]$svcItem)) {
        if ($svcItem.L -eq "Section") {
            $rtbSvcLog.SelectionStart=$rtbSvcLog.TextLength;$rtbSvcLog.SelectionLength=0
            $rtbSvcLog.SelectionFont=New-Object System.Drawing.Font("Consolas",7.5,[System.Drawing.FontStyle]::Bold)
            $rtbSvcLog.SelectionColor=[System.Drawing.Color]::FromArgb(100,116,139)
            $rtbSvcLog.AppendText("`n  $($svcItem.Result.ToUpper())`n")
        } else {
            $rtbSvcLog.SelectionStart=$rtbSvcLog.TextLength;$rtbSvcLog.SelectionLength=0
            $rtbSvcLog.SelectionColor=[System.Drawing.Color]::FromArgb(100,116,139)
            $rtbSvcLog.SelectionFont=New-Object System.Drawing.Font("Consolas",8)
            $rtbSvcLog.AppendText(("{0,-26}" -f $svcItem.Label))
            $col = switch ($svcItem.L) { "Pass"{[System.Drawing.Color]::FromArgb(74,222,128)} "Fail"{[System.Drawing.Color]::FromArgb(252,165,165)} "Warn"{[System.Drawing.Color]::FromArgb(253,224,71)} "Gray"{[System.Drawing.Color]::FromArgb(100,116,139)} default{[System.Drawing.Color]::FromArgb(203,213,225)} }
            $rtbSvcLog.SelectionStart=$rtbSvcLog.TextLength;$rtbSvcLog.SelectionLength=0
            $rtbSvcLog.SelectionColor=$col; $rtbSvcLog.SelectionFont=New-Object System.Drawing.Font("Consolas",8)
            $rtbSvcLog.AppendText("$($svcItem.Result)`n")
        }
        $rtbSvcLog.ScrollToCaret()
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
$lblSvcSub.Text = "Checks Pixellot application services and key Windows dependencies."
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
$rtbSvcLog = New-Object System.Windows.Forms.RichTextBox
$rtbSvcLog.Size = New-Object System.Drawing.Size(1240,336); $rtbSvcLog.Location = New-Object System.Drawing.Point(10,266)
$rtbSvcLog.BackColor = $ColLogBg; $rtbSvcLog.ForeColor = [System.Drawing.Color]::FromArgb(203,213,225)
$rtbSvcLog.Font = New-Object System.Drawing.Font("Consolas",8); $rtbSvcLog.ReadOnly = $true
$rtbSvcLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbSvcLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical; $rtbSvcLog.Anchor = $AnchorTLRB
$rtbSvcLog.Text = "Click 'Check Services' to begin."
$pnlServices.Controls.Add($rtbSvcLog)
$script:svcRunspace = $null; $script:svcSpinIdx = 0


$btnSvcRun.Add_Click({
    if ($sync.SvcRunning) { return }
    $sync.SvcCancelled = $false
    $sync.Cards["SvcStatus"] = @{ Value="--"; Status="neutral" }
    foreach ($key in $svcCards.Keys) { Update-CardStatus -Card $svcCards[$key] -Value "--" -Status "neutral" }
    $rtbSvcLog.Clear(); $btnSvcRun.Enabled=$false; $btnSvcRun.Text="  Running..."
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

