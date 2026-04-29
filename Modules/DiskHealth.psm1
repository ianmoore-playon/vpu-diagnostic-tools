# =============================================================================
#  DiskHealth.psm1  -  System and Disk Health panel
# =============================================================================

# ---------- Disk/System health background script -----------------------------
$DiskScript = {
    param($sync)
    $sync.DiskRunning = $true; $sync.DiskComplete = $false; $sync.DiskCancelled = $false
    $item = $null; while ($sync.DiskQueue.TryDequeue([ref]$item)) { }
    function Disk-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.DiskQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Disk-Section { param([string]$Title)
        $sync.DiskQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    $sync.DiskStep = "Reading system info..."
    Disk-Section "System"
    try {
        $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
        Disk-Log "Computer"  $env:COMPUTERNAME "Info"
        Disk-Log "OS"        ($os.Caption -replace "Microsoft ","") "Info"
        Disk-Log "Uptime"    ("{0}d {1}h {2}m" -f [int]$uptime.TotalDays,$uptime.Hours,$uptime.Minutes) "Info"
        $totalMem = [math]::Round($os.TotalVisibleMemorySize/1MB,1)
        $freeMem  = [math]::Round($os.FreePhysicalMemory/1MB,1)
        $memPct   = [math]::Round((($totalMem-$freeMem)/$totalMem)*100)
        $memLvl   = if($memPct-gt90){"Fail"}elseif($memPct-gt75){"Warn"}else{"Pass"}
        Disk-Log "Memory" ("{0} GB used / {1} GB total  ({2}%)" -f ($totalMem-$freeMem),$totalMem,$memPct) $memLvl
        $sync.Cards["MemStatus"] = @{ Value="$memPct% used"; Status=switch($memLvl){"Pass"{"ok"}"Warn"{"warn"}"Fail"{"fail"}} }
    } catch { Disk-Log "System info" "Error reading" "Warn" }
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }

    $sync.DiskStep = "Checking disk space..."
    Disk-Section "Disk Space"
    try {
        $disks = @(Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop)
        $worstStatus = "ok"; $cFree = 0
        foreach ($d in $disks) {
            if ($sync.DiskCancelled) { break }
            $freeGb  = [math]::Round($d.FreeSpace/1GB,1)
            $totalGb = [math]::Round($d.Size/1GB,1)
            $pct     = if($d.Size-gt0){[math]::Round((1-$d.FreeSpace/$d.Size)*100)}else{0}
            $lvl     = if($pct-gt95){"Fail"}elseif($pct-gt85){"Warn"}else{"Pass"}
            if($d.DeviceID -eq "C:"){$cFree=$freeGb}
            if($lvl-eq"Fail"-and$worstStatus-ne"fail"){$worstStatus="fail"}
            elseif($lvl-eq"Warn"-and$worstStatus-eq"ok"){$worstStatus="warn"}
            Disk-Log "$($d.DeviceID)  $($d.VolumeName)" ("{0} GB free / {1} GB  ({2}% used)" -f $freeGb,$totalGb,$pct) $lvl
        }
        $sync.Cards["DiskStatus"] = @{ Value="C: $cFree GB free"; Status=$worstStatus }
    } catch { Disk-Log "Disk" "Error reading disk info" "Warn" }
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }

    $sync.DiskStep = "Checking Pixellot folders..."
    Disk-Section "Pixellot Data Paths"
    foreach ($pp in @(
        @{Path="C:\Pixellot";           Label="Pixellot root"}
        @{Path="C:\Pixellot\Data";      Label="Data folder"}
        @{Path="C:\Pixellot\Data\Log";  Label="Log folder"}
        @{Path="C:\Pixellot\recordings";Label="Recordings"}
    )) {
        if ($sync.DiskCancelled) { break }
        if (Test-Path $pp.Path) {
            try {
                $sz = (Get-ChildItem $pp.Path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $szStr = if($sz-ge1GB){"{0:F1} GB" -f ($sz/1GB)}else{"{0:F0} MB" -f ($sz/1MB)}
                Disk-Log $pp.Label "Exists  ($szStr)" "Pass"
            } catch { Disk-Log $pp.Label "Exists" "Pass" }
        } else { Disk-Log $pp.Label "Not found" "Gray" }
    }

    $sync.DiskStep = "Complete"; $sync.DiskRunning=$false; $sync.DiskComplete=$true
}


# ---------- Disk timer ------------------------------------------------------
$diskTimer = New-Object System.Windows.Forms.Timer; $diskTimer.Interval = 300
$diskTimer.Add_Tick({
    $diskItem = $null
    while ($sync.DiskQueue.TryDequeue([ref]$diskItem)) {
        if ($diskItem.L -eq "Section") {
            $rtbDiskLog.SelectionStart=$rtbDiskLog.TextLength;$rtbDiskLog.SelectionLength=0
            $rtbDiskLog.SelectionFont=New-Object System.Drawing.Font("Consolas",7.5,[System.Drawing.FontStyle]::Bold)
            $rtbDiskLog.SelectionColor=[System.Drawing.Color]::FromArgb(100,116,139)
            $rtbDiskLog.AppendText("`n  $($diskItem.Result.ToUpper())`n")
        } else {
            $rtbDiskLog.SelectionStart=$rtbDiskLog.TextLength;$rtbDiskLog.SelectionLength=0
            $rtbDiskLog.SelectionColor=[System.Drawing.Color]::FromArgb(100,116,139)
            $rtbDiskLog.SelectionFont=New-Object System.Drawing.Font("Consolas",8)
            $rtbDiskLog.AppendText(("{0,-26}" -f $diskItem.Label))
            $col = switch ($diskItem.L) { "Pass"{[System.Drawing.Color]::FromArgb(74,222,128)} "Fail"{[System.Drawing.Color]::FromArgb(252,165,165)} "Warn"{[System.Drawing.Color]::FromArgb(253,224,71)} "Gray"{[System.Drawing.Color]::FromArgb(100,116,139)} default{[System.Drawing.Color]::FromArgb(203,213,225)} }
            $rtbDiskLog.SelectionStart=$rtbDiskLog.TextLength;$rtbDiskLog.SelectionLength=0
            $rtbDiskLog.SelectionColor=$col; $rtbDiskLog.SelectionFont=New-Object System.Drawing.Font("Consolas",8)
            $rtbDiskLog.AppendText("$($diskItem.Result)`n")
        }
        $rtbDiskLog.ScrollToCaret()
    }
    foreach ($key in $diskCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $diskCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $diskCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.DiskRunning) {
        $script:diskSpinIdx=($script:diskSpinIdx+1)%4
        $lblDiskStatus.ForeColor=$ColAccent
        $lblDiskStatus.Text=" $(@('|','/','-','\')[$script:diskSpinIdx])  $($sync.DiskStep)"
    }
    if ($sync.DiskComplete -and -not $sync.DiskRunning) {
        $diskTimer.Stop(); $btnDiskCancel.Visible=$false
        $btnDiskRun.Enabled=$true; $btnDiskRun.Text=[char]0x25B6+"  Check System Health"
        $lblDiskStatus.ForeColor=$ColMuted; $lblDiskStatus.Text="  $($sync.DiskStep)"
    }
})


# ---- System & Disk Health Panel --------------------------------------------
$pnlDisk = New-Object System.Windows.Forms.Panel
$pnlDisk.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlDisk.Location = New-Object System.Drawing.Point($SideW,$HdrH)
$pnlDisk.BackColor = $ColBg; $pnlDisk.Visible = $false; $pnlDisk.Anchor = $AnchorTLRB
$form.Controls.Add($pnlDisk)
$lblDiskTitle = New-Object System.Windows.Forms.Label; $lblDiskTitle.Text = "System & Disk Health"
$lblDiskTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblDiskTitle.ForeColor = $ColText
$lblDiskTitle.Location = New-Object System.Drawing.Point(10,16); $lblDiskTitle.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskTitle)
$lblDiskSub = New-Object System.Windows.Forms.Label
$lblDiskSub.Text = "Checks disk space, memory usage, system uptime, and Pixellot data folder sizes."
$lblDiskSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblDiskSub.ForeColor = $ColMuted
$lblDiskSub.Location = New-Object System.Drawing.Point(10,42); $lblDiskSub.Size = New-Object System.Drawing.Size(762,18)
$pnlDisk.Controls.Add($lblDiskSub)
$diskCardDefs = @(
    @{ Key="DiskStatus"; Title="Disk Space";   Sub="C: free space";   X=10;  Icon=[char]0xEDA2; W=250 }
    @{ Key="MemStatus";  Title="Memory";       Sub="RAM utilization"; X=270; Icon=[char]0xE950; W=250 }
)
$diskCards = @{}
foreach ($cd in $diskCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $diskCards[$cd.Key] = $c; $pnlDisk.Controls.Add($c.Panel)
}
$btnDiskRun = New-Object System.Windows.Forms.Button; $btnDiskRun.Text = [char]0x25B6 + "  Check System Health"
$btnDiskRun.Size = New-Object System.Drawing.Size(240,40); $btnDiskRun.Location = New-Object System.Drawing.Point(10,170)
$btnDiskRun.BackColor = $ColAccent; $btnDiskRun.ForeColor = [System.Drawing.Color]::White
$btnDiskRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDiskRun.FlatAppearance.BorderSize = 0
$btnDiskRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnDiskRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnDiskRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlDisk.Controls.Add($btnDiskRun)
$btnDiskRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,240,40)),6))
$btnDiskCancel = New-Object System.Windows.Forms.Button; $btnDiskCancel.Text = "Cancel"
$btnDiskCancel.Size = New-Object System.Drawing.Size(100,40); $btnDiskCancel.Location = New-Object System.Drawing.Point(258,170)
$btnDiskCancel.BackColor = $ColRed; $btnDiskCancel.ForeColor = [System.Drawing.Color]::White
$btnDiskCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnDiskCancel.FlatAppearance.BorderSize = 0
$btnDiskCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnDiskCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnDiskCancel.Visible = $false
$pnlDisk.Controls.Add($btnDiskCancel)
$btnDiskCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))
$lblDiskStatus = New-Object System.Windows.Forms.Label; $lblDiskStatus.Text = ""
$lblDiskStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblDiskStatus.ForeColor = $ColMuted
$lblDiskStatus.Location = New-Object System.Drawing.Point(10,218); $lblDiskStatus.Size = New-Object System.Drawing.Size(762,18)
$pnlDisk.Controls.Add($lblDiskStatus)
$lblDiskLogHdr = New-Object System.Windows.Forms.Label; $lblDiskLogHdr.Text = "Health Report"
$lblDiskLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblDiskLogHdr.ForeColor = $ColText
$lblDiskLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblDiskLogHdr.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskLogHdr)
$rtbDiskLog = New-Object System.Windows.Forms.RichTextBox
$rtbDiskLog.Size = New-Object System.Drawing.Size(762,422); $rtbDiskLog.Location = New-Object System.Drawing.Point(10,266)
$rtbDiskLog.BackColor = $ColLogBg; $rtbDiskLog.ForeColor = [System.Drawing.Color]::FromArgb(203,213,225)
$rtbDiskLog.Font = New-Object System.Drawing.Font("Consolas",8); $rtbDiskLog.ReadOnly = $true
$rtbDiskLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbDiskLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical; $rtbDiskLog.Anchor = $AnchorTLRB
$rtbDiskLog.Text = "Click 'Check System Health' to begin."
$pnlDisk.Controls.Add($rtbDiskLog)
$script:diskRunspace = $null; $script:diskSpinIdx = 0


$btnDiskRun.Add_Click({
    if ($sync.DiskRunning) { return }
    $sync.DiskCancelled = $false
    foreach ($key in @("DiskStatus","MemStatus")) { $sync.Cards[$key]=@{Value="--";Status="neutral"} }
    foreach ($key in $diskCards.Keys) { Update-CardStatus -Card $diskCards[$key] -Value "--" -Status "neutral" }
    $rtbDiskLog.Clear(); $btnDiskRun.Enabled=$false; $btnDiskRun.Text="  Running..."
    $btnDiskCancel.Visible=$true; $script:diskSpinIdx=0
    $lblDiskStatus.ForeColor=$ColAccent; $lblDiskStatus.Text=" |  Starting..."
    if ($script:diskRunspace) { try { $script:diskRunspace.Close() } catch { } }
    $script:diskRunspace = [runspacefactory]::CreateRunspace()
    $script:diskRunspace.ApartmentState="STA"; $script:diskRunspace.ThreadOptions="ReuseThread"; $script:diskRunspace.Open()
    $ps = [powershell]::Create(); $ps.Runspace=$script:diskRunspace
    $ps.AddScript($DiskScript) | Out-Null
    $ps.AddParameters(@{ sync=$sync }) | Out-Null
    $ps.BeginInvoke() | Out-Null; $diskTimer.Start()
})
$btnDiskCancel.Add_Click({ $sync.DiskCancelled=$true; $btnDiskCancel.Visible=$false })

