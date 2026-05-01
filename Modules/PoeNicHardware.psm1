# =============================================================================
#  PoeNicHardware.psm1  -  VPU Hardware panel
#  Shows GPU model, monitor/mouse/keyboard status, NIC link uptime, and PoE data.
#  NIC uptime and PoE data are populated by the Camera Connectivity runspace;
#  this panel reads them from $sync without a second DLL call.
# =============================================================================

# ---------- VPU Hardware background script -----------------------------------
$HwScript = {
    param($sync)
    $sync.HwRunning = $true; $sync.HwComplete = $false; $sync.HwCancelled = $false
    $item = $null; while ($sync.HwQueue.TryDequeue([ref]$item)) { }
    function Hw-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.HwQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Hw-Section { param([string]$Title)
        $sync.HwQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    # -- GPU model ---------------------------------------------------------------
    $sync.HwStep = "Querying GPU..."
    Hw-Section "Graphics"
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop |
               Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" } |
               Select-Object -First 1
        $gpuName = if ($gpu) { $gpu.Name } else { "Not detected" }
        Hw-Log "GPU" $gpuName "Info"
        $sync.Cards["HwGpu"] = @{ Value=$gpuName; Status="neutral" }
    } catch {
        Hw-Log "GPU" "Query failed" "Warn"
        $sync.Cards["HwGpu"] = @{ Value="Error"; Status="warn" }
    }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- Monitor connection -------------------------------------------------------
    $sync.HwStep = "Checking monitor..."
    Hw-Section "Peripherals"
    $monCount = 0
    try {
        $monitors = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction Stop |
                      Where-Object { $_.Availability -eq 3 })
        $monCount = $monitors.Count
        if ($monCount -eq 0) {
            $pnpMon = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Monitor'" -ErrorAction SilentlyContinue)
            $monCount = $pnpMon.Count
        }
        $monStr = if ($monCount -gt 0) { "$monCount connected" } else { "None detected" }
        $monLvl = if ($monCount -gt 0) { "Pass" } else { "Warn" }
        Hw-Log "Monitor" $monStr $monLvl
        $sync.Cards["HwMonitor"] = @{ Value=$monStr; Status=if($monCount -gt 0){"ok"}else{"warn"} }
    } catch {
        Hw-Log "Monitor" "Query failed" "Warn"
        $sync.Cards["HwMonitor"] = @{ Value="Error"; Status="warn" }
    }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- Mouse & keyboard ---------------------------------------------------------
    $sync.HwStep = "Checking peripherals..."
    $mouseOk = $false; $kbdOk = $false
    try {
        $mouseOk = (@(Get-CimInstance Win32_PointingDevice -ErrorAction Stop)).Count -gt 0
        Hw-Log "Mouse"    $(if($mouseOk){"Connected"}else{"None"}) $(if($mouseOk){"Pass"}else{"Warn"})
    } catch { Hw-Log "Mouse"    "Query failed" "Warn" }
    try {
        $kbdOk = (@(Get-CimInstance Win32_Keyboard -ErrorAction Stop)).Count -gt 0
        Hw-Log "Keyboard" $(if($kbdOk){"Connected"}else{"None"}) $(if($kbdOk){"Pass"}else{"Warn"})
    } catch { Hw-Log "Keyboard" "Query failed" "Warn" }

    $ms = if ($mouseOk) { [char]0x2713 } else { [char]0x2717 }
    $kb = if ($kbdOk)   { [char]0x2713 } else { [char]0x2717 }
    $mmkStr    = "Mouse:$ms  KB:$kb"
    $mmkStatus = if ($mouseOk -and $kbdOk) { "ok" } else { "warn" }
    $sync.Cards["HwMmk"] = @{ Value=$mmkStr; Status=$mmkStatus }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- NIC port uptime (cached by Camera Connectivity runspace) ----------------
    $sync.HwStep = "Reading NIC uptime..."
    Hw-Section "NIC Port Uptime"
    if ($sync.NicLinkUptimes.Count -gt 0) {
        foreach ($entry in @($sync.NicLinkUptimes)) {
            $lvl = if ($entry.Uptime -eq ">48h") { "Pass" } else { "Info" }
            Hw-Log $entry.Name "Link up: $($entry.Uptime)" $lvl
        }
    } else {
        Hw-Log "NIC Uptime" "Run Camera Connectivity first to collect uptime data" "Gray"
    }
    if ($sync.HwCancelled) { $sync.HwRunning=$false; $sync.HwComplete=$true; return }

    # -- PoE data (cached by Camera Connectivity runspace) -----------------------
    $sync.HwStep = "Reading PoE data..."
    Hw-Section "PoE Status"
    if ($sync.PoeAvailable -and $sync.PoePortData.Count -gt 0) {
        Hw-Log "Total Budget" ("{0:F1} W  (Consumed: {1:F1} W)" -f $sync.PoeTotal, $sync.PoeConsumed) "Info"
        Hw-Log "NIC Temp"     ("{0:F1} C" -f $sync.PoeTemp) "Info"
        foreach ($p in @($sync.PoePortData)) {
            $stateStr = if ($p.PoeOn) { "PoE ON" } else { "PoE OFF" }
            $lvl      = if ($p.PoeOn) { "Pass" } else { "Gray" }
            Hw-Log $p.Port ("{0:F2} V  {1:F3} A  {2:F1} W  [{3}]" -f $p.Voltage, $p.Current, $p.Watts, $stateStr) $lvl
        }
        if ($sync.PoeBudgetLow) {
            Hw-Log "Budget" ("LOW: {0:F0} W - check Molex connector on PoE NIC" -f $sync.PoeTotal) "Fail"
        }
    } else {
        Hw-Log "PoE Data" "Run Camera Connectivity first to collect PoE data" "Gray"
    }

    $sync.HwStep = "Complete"; $sync.HwRunning=$false; $sync.HwComplete=$true
}


# ---------- VPU Hardware timer -----------------------------------------------
$hwTimer = New-Object System.Windows.Forms.Timer; $hwTimer.Interval = 300
$hwTimer.Add_Tick({
    $hwItem = $null
    while ($sync.HwQueue.TryDequeue([ref]$hwItem)) {
        Add-LogRow $dgvHwLog $hwItem.Label $hwItem.Result $hwItem.L
    }
    foreach ($key in $hwCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $hwCards[$key].ValueLabel.Text -ne $sc.Value) { Update-CardStatus -Card $hwCards[$key] -Value $sc.Value -Status $sc.Status }
    }
    if ($sync.HwRunning) {
        $script:hwSpinIdx=($script:hwSpinIdx+1)%4
        $lblHwStatus.ForeColor=$ColAccent
        $lblHwStatus.Text=" $(@('|','/','-','\')[$script:hwSpinIdx])  $($sync.HwStep)"
    }
    if ($sync.HwComplete -and -not $sync.HwRunning) {
        $hwTimer.Stop(); $btnHwCancel.Visible=$false
        $btnHwRun.Enabled=$true; $btnHwRun.Text=[char]0x25B6+"  Check Hardware"
        $lblHwStatus.ForeColor=$ColMuted; $lblHwStatus.Text="  $($sync.HwStep)"
    }
})


# ---- VPU Hardware Panel -----------------------------------------------------
$pnlPoE = New-Object System.Windows.Forms.Panel
$pnlPoE.Size = New-Object System.Drawing.Size($WideW,$ContentH)
$pnlPoE.Location = New-Object System.Drawing.Point($SideW,$ContentY)
$pnlPoE.BackColor = $ColBg; $pnlPoE.Visible = $false; $pnlPoE.Anchor = $AnchorTLRB
$form.Controls.Add($pnlPoE)

$lblHwTitle = New-Object System.Windows.Forms.Label; $lblHwTitle.Text = "VPU Hardware"
$lblHwTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold",12); $lblHwTitle.ForeColor = $ColText
$lblHwTitle.Location = New-Object System.Drawing.Point(10,16); $lblHwTitle.AutoSize = $true
$pnlPoE.Controls.Add($lblHwTitle)

$lblHwSub = New-Object System.Windows.Forms.Label
$lblHwSub.Text = "GPU model, peripheral connections, NIC link uptime, and PoE power status."
$lblHwSub.Font = New-Object System.Drawing.Font("Segoe UI",8.5); $lblHwSub.ForeColor = $ColMuted
$lblHwSub.Location = New-Object System.Drawing.Point(10,42); $lblHwSub.Size = New-Object System.Drawing.Size(1240,18)
$pnlPoE.Controls.Add($lblHwSub)

$hwCardDefs = @(
    @{ Key="HwGpu";     Title="GPU";     Sub="Graphics adapter";  X=10;  Icon=[char]0xE7F4; W=400 }
    @{ Key="HwMonitor"; Title="Monitor"; Sub="Display connected";  X=420; Icon=[char]0xE7F4; W=400 }
    @{ Key="HwMmk";     Title="Input Devices"; Sub="Keyboard & mouse"; X=830; Icon=[char]0xE7C8; W=400 }
)
$hwCards = @{}
foreach ($cd in $hwCardDefs) {
    $c = New-StatusCard -Title $cd.Title -X $cd.X -Y 68 -Icon $cd.Icon -Sub $cd.Sub -CardW $cd.W -CardH 90
    $hwCards[$cd.Key] = $c; $pnlPoE.Controls.Add($c.Panel)
}

$btnHwRun = New-Object System.Windows.Forms.Button; $btnHwRun.Text = [char]0x25B6 + "  Check Hardware"
$btnHwRun.Size = New-Object System.Drawing.Size(220,40); $btnHwRun.Location = New-Object System.Drawing.Point(10,170)
$btnHwRun.BackColor = $ColAccent; $btnHwRun.ForeColor = [System.Drawing.Color]::White
$btnHwRun.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnHwRun.FlatAppearance.BorderSize = 0
$btnHwRun.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10)
$btnHwRun.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $btnHwRun.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlPoE.Controls.Add($btnHwRun)
$btnHwRun.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,220,40)),6))

$btnHwCancel = New-Object System.Windows.Forms.Button; $btnHwCancel.Text = "Cancel"
$btnHwCancel.Size = New-Object System.Drawing.Size(100,40); $btnHwCancel.Location = New-Object System.Drawing.Point(238,170)
$btnHwCancel.BackColor = $ColRed; $btnHwCancel.ForeColor = [System.Drawing.Color]::White
$btnHwCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $btnHwCancel.FlatAppearance.BorderSize = 0
$btnHwCancel.Font = New-Object System.Drawing.Font("Segoe UI",10); $btnHwCancel.Cursor = [System.Windows.Forms.Cursors]::Hand; $btnHwCancel.Visible = $false
$pnlPoE.Controls.Add($btnHwCancel)
$btnHwCancel.Region = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0,0,100,40)),6))

$lblHwStatus = New-Object System.Windows.Forms.Label; $lblHwStatus.Text = ""
$lblHwStatus.Font = New-Object System.Drawing.Font("Consolas",8); $lblHwStatus.ForeColor = $ColMuted
$lblHwStatus.Location = New-Object System.Drawing.Point(10,218); $lblHwStatus.Size = New-Object System.Drawing.Size(1240,18)
$pnlPoE.Controls.Add($lblHwStatus)

$lblHwLogHdr = New-Object System.Windows.Forms.Label; $lblHwLogHdr.Text = "Hardware Details"
$lblHwLogHdr.Font = New-Object System.Drawing.Font("Segoe UI Semibold",10); $lblHwLogHdr.ForeColor = $ColText
$lblHwLogHdr.Location = New-Object System.Drawing.Point(10,242); $lblHwLogHdr.AutoSize = $true
$pnlPoE.Controls.Add($lblHwLogHdr)

$dgvHwLog = New-LogGrid -X 10 -Y 266 -W 1240 -H 336
$pnlPoE.Controls.Add($dgvHwLog)

$script:hwRunspace = $null; $script:hwSpinIdx = 0


$btnHwRun.Add_Click({
    if ($sync.HwRunning) { return }
    $sync.HwCancelled = $false
    foreach ($key in $hwCards.Keys) { $sync.Cards[$key] = @{ Value="--"; Status="neutral" } }
    foreach ($key in $hwCards.Keys) { Update-CardStatus -Card $hwCards[$key] -Value "--" -Status "neutral" }
    $dgvHwLog.Rows.Clear(); $btnHwRun.Enabled=$false; $btnHwRun.Text="  Running..."
    $btnHwCancel.Visible=$true; $script:hwSpinIdx=0
    $lblHwStatus.ForeColor=$ColAccent; $lblHwStatus.Text=" |  Starting..."
    if ($script:hwRunspace) { try { $script:hwRunspace.Close() } catch { } }
    $script:hwRunspace = [runspacefactory]::CreateRunspace()
    $script:hwRunspace.ApartmentState="STA"; $script:hwRunspace.ThreadOptions="ReuseThread"; $script:hwRunspace.Open()
    $ps = [powershell]::Create(); $ps.Runspace=$script:hwRunspace
    $ps.AddScript($HwScript) | Out-Null
    $ps.AddParameters(@{ sync=$sync }) | Out-Null
    $ps.BeginInvoke() | Out-Null; $hwTimer.Start()
})
$btnHwCancel.Add_Click({ $sync.HwCancelled=$true; $btnHwCancel.Visible=$false })
