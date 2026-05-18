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
    # Per-card aggregates surfaced as DiskSmart (#8) and DiskErrors (#9)
    $smartFailCount = 0
    $smartTotal     = 0

    # ── 1. Physical Drives ────────────────────────────────────────────────────
    $sync.DiskStep = "Inventorying physical drives..."
    Disk-Section "Physical Drives"

    # Try Storage module for MediaType & HealthStatus (PS 5.1+, Storage cmdlets)
    # R6 fix: track whether the Storage module is actually available so we can
    # surface "SMART data unavailable" instead of silently reporting all-healthy
    # on a Server Core / locked-down LTSC where Get-PhysicalDisk is missing or
    # the root\wmi namespace is gone.
    $pdHealth         = @{}
    $smartDataMissing = $false
    $smartReason      = ""
    try {
        if (-not (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
            $smartDataMissing = $true
            $smartReason      = "Storage module not available"
        } else {
            @(Get-PhysicalDisk -ErrorAction Stop) | ForEach-Object {
                $pdHealth[$_.FriendlyName] = $_
            }
        }
    } catch {
        $smartDataMissing = $true
        $smartReason      = "Get-PhysicalDisk failed: $($_.Exception.Message)"
    }

    # SMART failure prediction - build per-disk-index hashtable so attribution is correct on multi-disk systems
    $smartFails = @{}
    try {
        $msPredict = @(Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction Stop)
        $msPredict | Where-Object { $_.PredictFailure } |
            ForEach-Object { if ($_.InstanceName -match '(\d+)') { $smartFails[[string]$Matches[1]] = $true } }
    } catch {
        # Most common: not running elevated, or root\wmi namespace blocked.
        $smartDataMissing = $true
        if (-not $smartReason) { $smartReason = "MSStorageDriver_FailurePredictStatus unavailable (admin or root\wmi access required)" }
    }

    $physDisks = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Sort-Object Index)
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
        if ($smartFails.ContainsKey([string]$phys.Index) -and $healthLvl -eq "Pass") { $healthStr = "SMART Predict Failure"; $healthLvl = "Fail" }
        if ($healthLvl -in @("Warn","Fail")) {
            $overallWorst = if ($healthLvl -eq "Fail") { "fail" } elseif ($overallWorst -ne "fail") { "warn" } else { $overallWorst }
            $smartFailCount++
        }
        $smartTotal++

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

    $volumes = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
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
        $isRecording = ($roles -contains "Recording / Storage")

        # Thresholds: absolute free space + percentage. D20 fix: tighter absolute
        # floors for recording volumes, since 15 GB on a 4 TB drive is 0.4 % —
        # the 90 % rule used to wait until the drive was 99.6 % full before
        # firing a Warning. Recording / Storage gets 50 GB warn / 20 GB fail
        # regardless of percentage; OS Drive keeps the old 15/5 GB floors.
        $absFailGB = if ($isRecording) { 20 } else { 5 }
        $absWarnGB = if ($isRecording) { 50 } else { 15 }
        $lvl = "Pass"
        if ($freeGB -lt $absFailGB -or $usedPct -gt 97) { $lvl = "Fail" }
        elseif ($freeGB -lt $absWarnGB -or $usedPct -gt 90) { $lvl = "Warn" }

        if ($lvl -eq "Fail" -and $overallWorst -ne "fail")            { $overallWorst = "fail" }
        elseif ($lvl -eq "Warn" -and $overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }

        $volName  = if ($vol.VolumeName) { "  $($vol.VolumeName)" } else { "" }
        $headline = "$($vol.DeviceID)$volName$roleLabel"
        $detail   = "{0} GB used  /  {1} GB free  /  {2} GB total   ({3}% used  |  {4}% free)" -f $usedGB,$freeGB,$totalGB,$usedPct,$freePct
        Disk-Log $headline $detail $lvl

        # Threshold guidance
        if ($lvl -eq "Fail") {
            Disk-Log "  >> Action" "Critically low - free space immediately or VPU may stop recording" "Fail"
        } elseif ($lvl -eq "Warn") {
            Disk-Log "  >> Action" "Space getting low - review large files and clear old recordings or logs" "Warn"
        }

        $volKey = "DiskVol_$($vol.DeviceID -replace ':','')"
        $volSt  = if ($lvl -eq "Fail") { "fail" } elseif ($lvl -eq "Warn") { "warn" } else { "ok" }
        $sync.Cards[$volKey] = @{ Value = "$freeGB GB free  ($freePct% free)"; Status = $volSt }
        if ($vol.DeviceID -eq $osDrive) { $cardFreeGB = $freeGB; $cardPct = $usedPct }
    }

    if ($volumes.Count -eq 0) { Disk-Log "Volumes" "No fixed volumes detected" "Warn"; $overallWorst = "fail" }

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

    # R17 fix: aggregate timeout. A C: with millions of small log files under
    # C:\Pixellot\Data\Log used to stall the entire runspace for minutes here.
    # Stop scanning further paths if we've already spent 30 s in total.
    $pixScanStart    = Get-Date
    $pixScanBudgetMs = 30000
    foreach ($pp in $pixPaths) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
        $elapsedMs = ((Get-Date) - $pixScanStart).TotalMilliseconds
        if ($elapsedMs -ge $pixScanBudgetMs) {
            Disk-Log $pp.Label "Skipped - scan budget exceeded (this and later paths)" "Warn"
            continue
        }
        if (-not (Test-Path $pp.Path -ErrorAction SilentlyContinue)) {
            Disk-Log $pp.Label "Path not found" "Gray"
            continue
        }
        try {
            $sz = (Get-ChildItem $pp.Path -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
                   Measure-Object Length -Sum).Sum
            if (-not $sz) { $sz = 0 }
            $szStr = Format-Size $sz
            $lvl   = if ($sz -ge $pp.Crit) { "Fail" }
                     elseif ($sz -ge $pp.Warn) { "Warn" }
                     else { "Pass" }
            Disk-Log $pp.Label $szStr $lvl
            if ($lvl -eq "Fail") {
                Disk-Log "  >> Action" "Unusually large - investigate and clear if safe" "Fail"
            } elseif ($lvl -eq "Warn") {
                Disk-Log "  >> Action" "Growing large - consider cleaning up old files" "Warn"
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
                    $sz = (Get-ChildItem $testPath -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
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

    $scanSw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($vol in $volumes) {
        if ($sync.DiskCancelled) { $sync.DiskRunning=$false; $sync.DiskComplete=$true; return }
        # Global 30s budget across all volumes — previously the inner break only exited
        # the directory loop, so a 4-volume system could spend 120s scanning.
        if ($scanSw.Elapsed.TotalSeconds -gt 30) {
            Disk-Log "Top folder scan" "Stopped after 30s budget — partial results above" "Gray"
            break
        }
        if (-not $vol.Size -or $vol.Size -eq 0) { continue }

        $topDirs = @(Get-ChildItem "$($vol.DeviceID)\" -Directory -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -notin @("System Volume Information","$RECYCLE.BIN","Recovery") })

        $dirSizes = @()
        foreach ($dir in $topDirs) {
            if ($sync.DiskCancelled -or $scanSw.Elapsed.TotalSeconds -gt 30) { break }
            try {
                $sz = (Get-ChildItem $dir.FullName -Recurse -Depth 3 -File -Force -ErrorAction SilentlyContinue |
                       Measure-Object Length -Sum).Sum
                if ($sz -gt 0) { $dirSizes += [PSCustomObject]@{ Name=$dir.Name; Path=$dir.FullName; Size=$sz } }
            } catch { }
        }

        $top = $dirSizes | Sort-Object Size -Descending | Select-Object -First 8
        if ($top.Count -gt 0) {
            Disk-Log "$($vol.DeviceID)\ - top folders" "" "Section"
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

    $diskEvents     = @()
    $diskEvtReadOk  = $true
    $diskEvtReadErr = ""
    try {
        $diskEvents = @(Get-WinEvent -FilterHashtable @{ LogName='System'; Level=@(1,2,3); StartTime=$since } -ErrorAction Stop |
            Where-Object {
                ($diskEvtSources -contains $_.ProviderName) -or ($diskEvtIds -contains $_.Id)
            } | Select-Object -First 20)
    } catch {
        # D5 fix: previously this catch was empty, leaving $diskEvents = @() and
        # the downstream `if ($diskEvents.Count -eq 0)` branch printed
        # "No disk-related errors in the last 48 hours" with status Pass —
        # silently identical to a clean log even when the event log was
        # corrupt, full, or the source filter was rejected.
        $diskEvtReadOk  = $false
        $diskEvtReadErr = $_.Exception.Message -replace "[\r\n]+"," "
    }

    if (-not $diskEvtReadOk) {
        Disk-Log "Disk events" "Event log unreadable: $diskEvtReadErr" "Warn"
        if ($overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }
    } elseif ($diskEvents.Count -eq 0) {
        Disk-Log "Disk events" "No disk-related errors in the last 48 hours" "Pass"
    } else {
        $errCount  = ($diskEvents | Where-Object { $_.Level -in @(1,2) }).Count
        $warnCount = ($diskEvents | Where-Object { $_.Level -eq 3 }).Count
        $summaryLvl = if ($errCount -gt 0) { "Fail" } else { "Warn" }
        Disk-Log "Events found" "$errCount error(s), $warnCount warning(s)" $summaryLvl
        if ($summaryLvl -eq "Fail" -and $overallWorst -ne "fail") { $overallWorst = "fail" }
        elseif ($summaryLvl -eq "Warn" -and $overallWorst -notin @("fail","warn")) { $overallWorst = "warn" }

        foreach ($ev in ($diskEvents | Select-Object -First 10)) {
            $evLvl  = if ($ev.Level -in @(1,2)) { "Fail" } else { "Warn" }
            $evTime = $ev.TimeCreated.ToString("MM/dd HH:mm")
            $evMsg  = ($ev.Message -split "`n")[0].Trim()
            if ($evMsg.Length -gt 100) { $evMsg = $evMsg.Substring(0,97) + "..." }
            Disk-Log "  $evTime  ID $($ev.Id)  $($ev.ProviderName)" $evMsg $evLvl
        }
        if ($diskEvents.Count -gt 10) {
            Disk-Log "  (and $($diskEvents.Count - 10) more)" "Open Event Logs tab for full list" "Gray"
        }
        Disk-Log "  >> Action" "Disk errors detected - check cables, run chkdsk, or replace suspect drive" "Fail"
        $sync.Cards["DiskVol_$($osDrive -replace ':','')"] = @{ Value = "$errCount disk error(s) - $cardFreeGB GB free"; Status = $overallWorst }
    }

    $diskStatusVal = switch ($overallWorst) { "fail"{"Issues detected"} "warn"{"Warnings found"} default{"Healthy"} }
    $sync.Cards["DiskStatus"] = @{ Value=$diskStatusVal; Status=$overallWorst }

    # SMART summary card (#8) — counts unhealthy/predict-failure drives among physical disks.
    # R6 fix: surface "data unavailable" instead of silently green when admin or
    # the Storage module / root\wmi namespace aren't accessible.
    if ($smartTotal -eq 0) {
        $smartVal    = "No disks detected"
        $smartStatus = "neutral"
    } elseif ($smartDataMissing -and $smartFailCount -eq 0) {
        $smartVal    = "SMART data unavailable"
        $smartStatus = "warn"
        Disk-Log "SMART data" $smartReason "Warn"
    } elseif ($smartFailCount -eq 0) {
        $smartVal    = "All $smartTotal healthy"
        $smartStatus = "ok"
    } else {
        $smartVal    = "$smartFailCount of $smartTotal unhealthy"
        $smartStatus = "fail"
    }
    $sync.Cards["DiskSmart"] = @{ Value=$smartVal; Status=$smartStatus }

    # Disk errors card (#9) — count from the disk-related event log scan above
    $diskErrCount = ($diskEvents | Where-Object { $_.Level -in @(1,2) }).Count
    $diskWarnCount = ($diskEvents | Where-Object { $_.Level -eq 3 }).Count
    if (-not $diskEvtReadOk) {
        $errVal    = "Log unreadable"
        $errStatus = "warn"
    } else {
        $errVal = if ($diskErrCount -eq 0 -and $diskWarnCount -eq 0) { "Clean (48 h)" } `
                  elseif ($diskErrCount -gt 0) { "$diskErrCount error(s)" } `
                  else { "$diskWarnCount warning(s)" }
        $errStatus = if ($diskErrCount -gt 0) { "fail" } `
                     elseif ($diskWarnCount -gt 0) { "warn" } `
                     else { "ok" }
    }
    $sync.Cards["DiskErrors"] = @{ Value=$errVal; Status=$errStatus }

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
        $btnDiskRun.Enabled=$true; $btnDiskRun.Text=[char]0x25B6+"  Run Test"
        $lblDiskStatus.ForeColor=$ColMuted; $lblDiskStatus.Text="Last run: $(Get-Date -Format 'h:mm tt')"

        # R2: surface any runspace errors that accumulated during the run.
        $diskErrs = Get-DiagRunspaceErrors $script:diskState
        foreach ($em in $diskErrs) {
            Add-LogRow $dgvDiskLog "Runspace error" $em "Fail"
        }

        # Update Overall Status pill
        $diskWorst = "ok"
        $pri = @{ fail=3; warn=2; ok=1; neutral=0 }
        foreach ($k in $diskCards.Keys) {
            if ($sync.Cards.ContainsKey($k)) {
                $s = $sync.Cards[$k].Status
                if ($s -and $pri[$s] -gt $pri[$diskWorst]) { $diskWorst = $s }
            }
        }
        Set-SectionPill $diskHeader $diskWorst

        # Build Summary
        $sumItems = @()
        $smartC = $sync.Cards["DiskSmart"]
        if ($smartC) { $sumItems += @{ Status=$smartC.Status; Text="SMART: $($smartC.Value)" } }
        $errC   = $sync.Cards["DiskErrors"]
        if ($errC -and $errC.Value -ne "--") {
            if ($errC.Status -eq "ok") { $sumItems += @{ Status="ok"; Text="No disk-related event log errors in the last 48 h" } }
            else { $sumItems += @{ Status=$errC.Status; Text="Disk event log: $($errC.Value)" } }
        }
        foreach ($k in $diskCards.Keys) {
            if ($k -notlike "DiskVol_*") { continue }
            $vc = $sync.Cards[$k]
            if ($vc -and $vc.Value -ne "--") {
                $drv = $k -replace 'DiskVol_',''
                $sumItems += @{ Status=$vc.Status; Text="$($drv): $($vc.Value)" }
            }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No disk data collected" }) }
        Set-SummaryItems $diskSummary $sumItems
    }
})


# ---- System & Disk Health Panel --------------------------------------------
$pnlDisk = New-Object System.Windows.Forms.Panel
$pnlDisk.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlDisk.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlDisk.BackColor = $ColBg; $pnlDisk.Visible = $false; $pnlDisk.Anchor = $AnchorTLRB
$form.Controls.Add($pnlDisk)
# v1.0.43 redesign — section header + cards row + log/summary split + action bar
$diskHeader = New-SectionHeader -Parent $pnlDisk `
    -Title    "Disk & System Health" `
    -Subtitle "Physical drive health, free space, Pixellot storage paths, and disk-related event log errors."

$diskVolumes = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | Sort-Object DeviceID)
$diskCardDefs = @(
    @{ Key="DiskSmart";  Title="SMART Health";  Sub="Per-drive predictive failure" ;Icon=[char]0xE9D9 }
    @{ Key="DiskErrors"; Title="Disk Errors";   Sub="System log, last 48 h"        ;Icon=[char]0xE7BA }
)
foreach ($diskVol in $diskVolumes) {
    $drvKey = "DiskVol_$($diskVol.DeviceID -replace ':','')"
    $diskCardDefs += @{ Key=$drvKey; Title="$($diskVol.DeviceID) Space"; Sub="$($diskVol.DeviceID) free space"; Icon=[char]0xEDA2 }
}
if ($diskVolumes.Count -eq 0) {
    $diskCardDefs += @{ Key="DiskVol_C"; Title="C: Space"; Sub="C: free space"; Icon=[char]0xEDA2 }
}

$diskCards = @{}
$diskCardW = 240; $diskCardGap = 12; $diskCardX = 28
foreach ($cd in $diskCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $diskCardX -Y 110 -Icon $cd.Icon -Sub $cd.Sub -CardW $diskCardW -CardH 90
    $diskCards[$cd.Key] = $c
    $pnlDisk.Controls.Add($c.Panel)
    $diskCardX += $diskCardW + $diskCardGap
}

# Log card (left) + Summary panel (right)
$diskLogCard = New-Object System.Windows.Forms.Panel
$diskLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$diskLogCard.Location  = New-Object System.Drawing.Point(28, 220)
$diskLogCard.BackColor = $ColCard
$diskLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlDisk.Controls.Add($diskLogCard)

$lblDiskLogHdr = New-Object System.Windows.Forms.Label
$lblDiskLogHdr.Text      = "Health Report"
$lblDiskLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblDiskLogHdr.ForeColor = $ColText
$lblDiskLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblDiskLogHdr.AutoSize  = $true
$diskLogCard.Controls.Add($lblDiskLogHdr)

$dgvDiskLog = New-LogGrid -X 8 -Y 38 -W 784 -H 414
$diskLogCard.Controls.Add($dgvDiskLog)

$diskSummary = New-SummaryPanel -Parent $pnlDisk -X 844 -Y 220 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $diskSummary @(@{ Status="neutral"; Text="Run Test to populate the summary" })

# Bottom action bar
$diskActions = New-ActionBar -Parent $pnlDisk -Y 698 -ExportText "Export Report" -PrimaryText ([char]0x25B6 + "  Run Test")
$btnDiskRun    = $diskActions.PrimaryBtn
$btnDiskExport = $diskActions.ExportBtn

$btnDiskCancel = New-Object System.Windows.Forms.Button
$btnDiskCancel.Text      = "Cancel"
$btnDiskCancel.Size      = New-Object System.Drawing.Size(110, 36)
$btnDiskCancel.Location  = New-Object System.Drawing.Point(168, 10)
$btnDiskCancel.BackColor = $ColRed
$btnDiskCancel.ForeColor = [System.Drawing.Color]::White
$btnDiskCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnDiskCancel.FlatAppearance.BorderSize = 0
$btnDiskCancel.Font      = New-Object System.Drawing.Font("Segoe UI", 9.5)
$btnDiskCancel.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnDiskCancel.Visible   = $false
$btnDiskCancel.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 110, 36)), 6))
$diskActions.Bar.Controls.Add($btnDiskCancel)

$lblDiskStatus = New-Object System.Windows.Forms.Label
$lblDiskStatus.Text      = ""
$lblDiskStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$lblDiskStatus.ForeColor = $ColMuted
$lblDiskStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblDiskStatus.Size      = New-Object System.Drawing.Size(($pnlDisk.Width - 56), 16)
$lblDiskStatus.Anchor    = $AnchorBLR
$pnlDisk.Controls.Add($lblDiskStatus)

$lblDiskEta = New-Object System.Windows.Forms.Label
$lblDiskEta.Visible = $false
$pnlDisk.Controls.Add($lblDiskEta)
$script:diskRunspace = $null; $script:diskPs = $null; $script:diskSpinIdx = 0


function Start-DiskDiagnostic {
    if ($sync.DiskRunning) { return }
    $sync.DiskCancelled = $false
    foreach ($key in $diskCards.Keys) {
        $sync.Cards[$key] = @{ Value="--"; Status="neutral" }
        Update-CardStatus -Card $diskCards[$key] -Value "--" -Status "neutral"
    }
    $dgvDiskLog.Rows.Clear(); $btnDiskRun.Enabled=$false; $btnDiskRun.Text="  Running..."
    $btnDiskCancel.Visible=$true; $script:diskSpinIdx=0
    $lblDiskStatus.ForeColor=$ColAccent; $lblDiskStatus.Text=" |  Starting..."
    # R2/R13: Start-DiagRunspace handles cleanup of $script:diskState, TLS-1.2
    # bump inside the runspace, and captures the IAsyncResult so EndInvoke can
    # surface errors in the timer's Complete branch.
    $script:diskState = Start-DiagRunspace `
        -Script    $DiskScript `
        -Parameters @{ sync = $sync } `
        -Previous   $script:diskState
    # Back-compat shims for any consumer still reading the legacy script-scoped
    # names (FormClosing dispose, etc.).
    $script:diskRunspace = $script:diskState.Runspace
    $script:diskPs       = $script:diskState.Ps
    $diskTimer.Start()
}

$btnDiskRun.Add_Click({ Start-DiskDiagnostic })
$btnDiskCancel.Add_Click({ $sync.DiskCancelled=$true; $btnDiskCancel.Visible=$false })

