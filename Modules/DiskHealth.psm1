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
    function Format-Size {
        param([double]$Bytes)
        if ($Bytes -ge 1TB) { return "{0:F2} TB" -f ($Bytes/1TB) }
        if ($Bytes -ge 1GB) { return "{0:F1} GB" -f ($Bytes/1GB) }
        if ($Bytes -ge 1MB) { return "{0:F0} MB" -f ($Bytes/1MB) }
        return "{0:F0} KB" -f ($Bytes/1KB)
    }

    $overallWorst = "ok"
    $osDrive      = $env:SystemDrive  # e.g. "C:"

    # ── 1. Physical Drives ────────────────────────────────────────────────────
    $sync.DiskStep = "Inventorying physical drives..."
    Disk-Section "Physical Drives"

    # Try Storage module for MediaType & HealthStatus (PS 5.1+, Storage cmdlets)
    $pdHealth = @{}
    try {
        @(Get-PhysicalDisk -ErrorAction Stop) | ForEach-Object {
            $pdHealth[$_.FriendlyName] = $_
        }
    } catch {}

    # SMART failure prediction (root\wmi namespace)
    $smartFail = $false
    try {
        $smartObjs = @(Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue)
        $smartFail = ($smartObjs | Where-Object { $_.PredictFailure }).Count -gt 0
    } catch {}

    $physDisks = @(Get-WmiObject Win32_DiskDrive -ErrorAction SilentlyContinue | Sort-Object Index)
    foreach ($phys in $physDisks) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }

        $sizeStr = Format-Size ([double]$phys.Size)

        # Media type: prefer Get-PhysicalDisk, fall back to model name heuristic
        $mediaType = "Unknown"
        $matchPd = $pdHealth.Values | Where-Object {
            $phys.Model -like "*$($_.FriendlyName)*" -or $_.FriendlyName -like "*$($phys.Model)*"
        } | Select-Object -First 1
        if ($matchPd -and $matchPd.MediaType -ne "Unspecified") {
            $mediaType = $matchPd.MediaType
        } elseif ($phys.Model -match "SSD|Solid.State|NVMe|M\.2") { $mediaType = "SSD" }
        elseif ($phys.Model -match "HDD|Hard.Disk") { $mediaType = "HDD" }
        elseif ($phys.MediaType -match "Fixed") { $mediaType = "HDD" }

        # Health: Win32_DiskDrive.Status + Get-PhysicalDisk.HealthStatus
        $healthStr = $phys.Status
        $healthLvl = if ($phys.Status -eq "OK") { "Pass" } else { "Warn" }
        if ($matchPd) {
            $healthStr = $matchPd.HealthStatus
            $healthLvl = switch ($matchPd.HealthStatus) {
                "Healthy"   { "Pass" }
                "Warning"   { "Warn" }
                "Unhealthy" { "Fail" }
                default     { "Info" }
            }
        }
        if ($smartFail -and $healthLvl -eq "Pass") { $healthStr = "SMART Predict Failure"; $healthLvl = "Fail" }
        if ($healthLvl -in @("Warn","Fail")) { $overallWorst = if ($healthLvl -eq "Fail") { "fail" } elseif ($overallWorst -ne "fail") { "warn" } else { $overallWorst } }

        $typeLabel = if ($mediaType -ne "Unknown") { "  [$mediaType]" } else { "" }
        Disk-Log "Disk $($phys.Index)  $($phys.Model)" "$sizeStr  $($phys.InterfaceType)$typeLabel" "Info"
        Disk-Log "  Health / SMART" $healthStr $healthLvl
        if ($phys.FirmwareRevision) { Disk-Log "  Firmware" $phys.FirmwareRevision "Gray" }
        if ($phys.SerialNumber -and $phys.SerialNumber.Trim()) { Disk-Log "  Serial" $phys.SerialNumber.Trim() "Gray" }
    }

    if ($physDisks.Count -eq 0) { Disk-Log "Physical drives" "None detected" "Warn" }

    # ── 2. Volumes & Space ────────────────────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Checking volumes and space..."
    Disk-Section "Volumes & Space"

    # Pixellot path patterns used to identify recording/storage drives
    $pixStorePaths = @("Pixellot\recordings","Pixellot\data","Pixellot\Data","recordings")

    $volumes = @(Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
    $cardFreeGB = 0; $cardPct = 0

    foreach ($vol in $volumes) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }

        # Inaccessible / unformatted
        if (-not $vol.Size -or $vol.Size -eq 0) {
            Disk-Log "$($vol.DeviceID)  $($vol.VolumeName)" "Inaccessible or unformatted" "Warn"
            if ($overallWorst -ne "fail") { $overallWorst = "warn" }
            continue
        }

        $totalGB = [math]::Round($vol.Size   / 1GB, 1)
        $freeGB  = [math]::Round($vol.FreeSpace / 1GB, 1)
        $usedGB  = [math]::Round(($vol.Size - $vol.FreeSpace) / 1GB, 1)
        $usedPct = [math]::Round((1 - $vol.FreeSpace/$vol.Size) * 100)
        $freePct = 100 - $usedPct

        # Drive role
        $roles = @()
        if ($vol.DeviceID -eq $osDrive) { $roles += "OS Drive" }
        foreach ($pp in $pixStorePaths) {
            if (Test-Path "$($vol.DeviceID)\$pp" -ErrorAction SilentlyContinue) { $roles += "Recording / Storage"; break }
        }
        if (-not $roles) { $roles += if ($totalGB -gt 200) { "Storage" } else { "Data" } }
        $roleLabel = " [$($roles -join ' / ')]"

        # Thresholds: absolute free space takes priority over percentage
        $lvl = "Pass"
        if ($freeGB -lt 5  -or $usedPct -gt 95) { $lvl = "Fail" }
        elseif ($freeGB -lt 15 -or $usedPct -gt 85) { $lvl = "Warn" }

        if ($lvl -eq "Fail" -and $overallWorst -ne "fail")            { $overallWorst = "fail" }
        elseif ($lvl -eq "Warn" -and $overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }

        $volName  = if ($vol.VolumeName) { "  $($vol.VolumeName)" } else { "" }
        $headline = "$($vol.DeviceID)$volName$roleLabel"
        $detail   = "{0} GB used  /  {1} GB free  /  {2} GB total   ({3}% used  |  {4}% free)" -f $usedGB,$freeGB,$totalGB,$usedPct,$freePct
        Disk-Log $headline $detail $lvl

        # Threshold guidance
        if ($lvl -eq "Fail") {
            Disk-Log "  >> Action" "Critically low — free space immediately or VPU may stop recording" "Fail"
        } elseif ($lvl -eq "Warn") {
            Disk-Log "  >> Action" "Space getting low — review large files and clear old recordings or logs" "Warn"
        }

        if ($vol.DeviceID -eq $osDrive) { $cardFreeGB = $freeGB; $cardPct = $usedPct }
    }

    if ($volumes.Count -eq 0) { Disk-Log "Volumes" "No fixed volumes detected" "Warn"; $overallWorst = "fail" }

    $sync.Cards["DiskStatus"] = @{
        Value  = "$osDrive $cardFreeGB GB free  ($cardPct% used)"
        Status = $overallWorst
    }

    # ── 3. Pixellot Storage Paths ─────────────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Scanning Pixellot paths..."
    Disk-Section "Pixellot Storage Paths"

    $pixPaths = @(
        @{ Path="C:\Pixellot\Data\Log";         Label="Pixellot Logs";        Warn=2GB;  Crit=5GB  }
        @{ Path="C:\Pixellot\recordings";        Label="Recordings (C:)";      Warn=10GB; Crit=50GB }
        @{ Path="C:\Pixellot\Data";              Label="Pixellot Data";        Warn=5GB;  Crit=20GB }
        @{ Path="C:\Pixellot\temp";              Label="Pixellot Temp";        Warn=1GB;  Crit=3GB  }
        @{ Path="C:\Pixellot";                   Label="Pixellot Root (total)"; Warn=20GB; Crit=80GB }
        @{ Path="C:\Windows\Temp";              Label="Windows Temp";          Warn=2GB;  Crit=5GB  }
        @{ Path="$env:TEMP";                    Label="User Temp";             Warn=2GB;  Crit=5GB  }
        @{ Path="C:\Users";                     Label="User Profiles (total)"; Warn=10GB; Crit=30GB }
    )

    foreach ($pp in $pixPaths) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
        if (-not (Test-Path $pp.Path -ErrorAction SilentlyContinue)) {
            Disk-Log $pp.Label "Path not found" "Gray"
            continue
        }
        try {
            $sz = (Get-ChildItem $pp.Path -Recurse -File -Force -ErrorAction SilentlyContinue |
                   Measure-Object Length -Sum).Sum
            if (-not $sz) { $sz = 0 }
            $szStr = Format-Size $sz
            $lvl   = if ($sz -ge $pp.Crit) { "Fail" }
                     elseif ($sz -ge $pp.Warn) { "Warn" }
                     else { "Pass" }
            Disk-Log $pp.Label $szStr $lvl
            if ($lvl -eq "Fail") {
                Disk-Log "  >> Action" "Unusually large — investigate and clear if safe" "Fail"
            } elseif ($lvl -eq "Warn") {
                Disk-Log "  >> Action" "Growing large — consider cleaning up old files" "Warn"
            }
        } catch {
            Disk-Log $pp.Label "Could not read (access error)" "Warn"
        }
    }

    # Additional recording drives (non-C: drives containing Pixellot paths)
    foreach ($vol in ($volumes | Where-Object { $_.DeviceID -ne "C:" })) {
        foreach ($pp in @("Pixellot\recordings","recordings","Pixellot\Data")) {
            $testPath = "$($vol.DeviceID)\$pp"
            if (Test-Path $testPath -ErrorAction SilentlyContinue) {
                try {
                    $sz = (Get-ChildItem $testPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                           Measure-Object Length -Sum).Sum
                    Disk-Log "Recordings ($($vol.DeviceID))" (Format-Size $sz) "Info"
                } catch { Disk-Log "Recordings ($($vol.DeviceID))" "Found (size unavailable)" "Info" }
                break
            }
        }
    }

    # ── 4. Top Space Consumers (per drive, top-level scan) ────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Finding large folders..."
    Disk-Section "Largest Top-Level Folders"

    foreach ($vol in $volumes) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
        if (-not $vol.Size -or $vol.Size -eq 0) { continue }

        $topDirs = @(Get-ChildItem "$($vol.DeviceID)\" -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -notin @("System Volume Information","$RECYCLE.BIN","Recovery") })

        $dirSizes = @()
        foreach ($dir in $topDirs) {
            if ($sync.DiskCancelled) { break }
            try {
                $sz = (Get-ChildItem $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                       Measure-Object Length -Sum).Sum
                if ($sz -gt 0) { $dirSizes += [PSCustomObject]@{ Name=$dir.Name; Path=$dir.FullName; Size=$sz } }
            } catch { }
        }

        $top = $dirSizes | Sort-Object Size -Descending | Select-Object -First 8
        if ($top.Count -gt 0) {
            Disk-Log "$($vol.DeviceID)\ — top folders" "" "Section"
            foreach ($d in $top) {
                $bar = "#" * [int]([math]::Min(($d.Size / $vol.Size) * 20, 20))
                Disk-Log "  $($d.Name)" "$(Format-Size $d.Size)  $bar" "Info"
            }
        }
    }

    # ── 5. Disk-Related Event Log Errors ─────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Checking disk-related event logs..."
    Disk-Section "Disk Event Log Errors (last 48 h)"

    $since  = (Get-Date).AddHours(-48)
    $diskEvtSources = @("disk","Ntfs","volmgr","partmgr","stornvme","msahci",
                        "iaStorAVC","iaStorV","storahci","cdrom")
    # Critical disk event IDs: 7/11 (device error), 51 (IO warning), 55 (NTFS corrupt),
    # 50 (delayed write failed), 153 (IO failure warning)
    $diskEvtIds = @(7, 11, 51, 52, 55, 50, 57, 140, 153)

    $diskEvents = @()
    try {
        $diskEvents = @(Get-EventLog -LogName System -EntryType Error,Warning -After $since -ErrorAction Stop |
            Where-Object {
                ($diskEvtSources -contains $_.Source) -or ($diskEvtIds -contains $_.EventID)
            } | Sort-Object TimeGenerated -Descending | Select-Object -First 20)
    } catch {}

    if ($diskEvents.Count -eq 0) {
        Disk-Log "Disk events" "No disk-related errors in the last 48 hours" "Pass"
    } else {
        $errCount  = ($diskEvents | Where-Object { $_.EntryType -eq "Error"   }).Count
        $warnCount = ($diskEvents | Where-Object { $_.EntryType -eq "Warning" }).Count
        $summaryLvl = if ($errCount -gt 0) { "Fail" } else { "Warn" }
        Disk-Log "Events found" "$errCount error(s), $warnCount warning(s)" $summaryLvl
        if ($summaryLvl -eq "Fail" -and $overallWorst -ne "fail") { $overallWorst = "fail" }
        elseif ($summaryLvl -eq "Warn" -and $overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }

        foreach ($ev in ($diskEvents | Select-Object -First 10)) {
            $evLvl  = if ($ev.EntryType -eq "Error") { "Fail" } else { "Warn" }
            $evTime = $ev.TimeGenerated.ToString("MM/dd HH:mm")
            $evMsg  = ($ev.Message -split "`n")[0].Trim()
            if ($evMsg.Length -gt 100) { $evMsg = $evMsg.Substring(0,97) + "..." }
            Disk-Log "  $evTime  ID $($ev.EventID)  $($ev.Source)" $evMsg $evLvl
        }
        if ($diskEvents.Count -gt 10) {
            Disk-Log "  (and $($diskEvents.Count - 10) more)" "Open Event Logs tab for full list" "Gray"
        }
        Disk-Log "  >> Action" "Disk errors detected — check cables, run chkdsk, or replace suspect drive" "Fail"
        $sync.Cards["DiskStatus"] = @{ Value = "$errCount disk error(s) in event log — $osDrive $cardFreeGB GB free"; Status = $overallWorst }
    }

    # ── 6. System Memory ─────────────────────────────────────────────────────
    if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
    $sync.DiskStep = "Checking memory..."
    Disk-Section "System Memory"

    try {
        $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop
        $uptime   = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
        $totalMem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeMem  = [math]::Round($os.FreePhysicalMemory      / 1MB, 1)
        $usedMem  = [math]::Round($totalMem - $freeMem, 1)
        $memPct   = [math]::Round(($usedMem / $totalMem) * 100)
        $memLvl   = if ($memPct -gt 90) { "Fail" } elseif ($memPct -gt 75) { "Warn" } else { "Pass" }
        Disk-Log "Computer"   $env:COMPUTERNAME "Info"
        Disk-Log "OS"         ($os.Caption -replace "Microsoft ","") "Info"
        Disk-Log "Uptime"     ("{0}d {1}h {2}m" -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes) "Info"
        Disk-Log "RAM Total"  "$totalMem GB" "Info"
        Disk-Log "RAM Used"   "$usedMem GB  ($memPct%)" $memLvl
        Disk-Log "RAM Free"   "$freeMem GB" "Info"
        $sync.Cards["MemStatus"] = @{
            Value  = "$memPct% used  ($usedMem / $totalMem GB)"
            Status = switch ($memLvl) { "Pass"{"ok"} "Warn"{"warn"} "Fail"{"fail"} }
        }
    } catch { Disk-Log "Memory" "Error reading system info" "Warn" }

    $sync.DiskStep = "Complete"; $sync.DiskRunning=$false; $sync.DiskComplete=$true
}


# ---------- Disk timer ------------------------------------------------------
$diskTimer = New-Object System.Windows.Forms.Timer; $diskTimer.Interval = 300
$diskTimer.Add_Tick({
    $diskItem = $null
    while ($sync.DiskQueue.TryDequeue([ref]$diskItem)) {
        Add-LogRow $dgvDiskLog $diskItem.Label $diskItem.Result $diskItem.L
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
$pnlDisk.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlDisk.BackColor = $ColBg; $pnlDisk.Visible = $false; $pnlDisk.Anchor = $AnchorTLRB
$form.Controls.Add($pnlDisk)
$lblDiskTitle = New-Object System.Windows.Forms.Label; $lblDiskTitle.Text = "System & Disk Health"
$lblDiskTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblDiskTitle.ForeColor = $ColText
$lblDiskTitle.Location = New-Object System.Drawing.Point(10,16); $lblDiskTitle.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskTitle)
$lblDiskSub = New-Object System.Windows.Forms.Label
$lblDiskSub.Text = "Physical drive health, volume free space, Pixellot storage paths, top space consumers, disk errors, and system memory."
$lblDiskSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblDiskSub.ForeColor = $ColMuted
$lblDiskSub.Location = New-Object System.Drawing.Point(10,42); $lblDiskSub.Size = New-Object System.Drawing.Size(1240,18)
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
$lblDiskStatus.Location = New-Object System.Drawing.Point(10,218); $lblDiskStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlDisk.Controls.Add($lblDiskStatus)
$lblDiskLogHdr = New-Object System.Windows.Forms.Label; $lblDiskLogHdr.Text = "Health Report"
$lblDiskLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblDiskLogHdr.ForeColor = $ColText
$lblDiskLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblDiskLogHdr.AutoSize = $true
$pnlDisk.Controls.Add($lblDiskLogHdr)
$dgvDiskLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlDisk.Controls.Add($dgvDiskLog)
$script:diskRunspace = $null; $script:diskSpinIdx = 0


$btnDiskRun.Add_Click({
    if ($sync.DiskRunning) { return }
    $sync.DiskCancelled = $false
    foreach ($key in @("DiskStatus","MemStatus")) { $sync.Cards[$key]=@{Value="--";Status="neutral"} }
    foreach ($key in $diskCards.Keys) { Update-CardStatus -Card $diskCards[$key] -Value "--" -Status "neutral" }
    $dgvDiskLog.Rows.Clear(); $btnDiskRun.Enabled=$false; $btnDiskRun.Text="  Running..."
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

