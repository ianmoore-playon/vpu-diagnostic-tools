# =============================================================================
#  SystemInformation.psm1  -  System Information panel
#  Collects OS, CPU, RAM, GPU, disk and NIC details via CIM in a background
#  runspace and streams them into a DataGridView log.
# =============================================================================

$SysInfoScript = {
    param($sync)
    $sync.SysInfoRunning = $true; $sync.SysInfoComplete = $false
    $item = $null; while ($sync.SysInfoQueue.TryDequeue([ref]$item)) { }

    function Si-Log { param([string]$Label,[string]$Result,[string]$Level="Info")
        $sync.SysInfoQueue.Enqueue(@{ Label=$Label; Result=$Result; L=$Level }) }
    function Si-Section { param([string]$Title)
        $sync.SysInfoQueue.Enqueue(@{ Label=""; Result=$Title; L="Section" }) }

    # -- Pixellot Software -------------------------------------------------------
    $sync.SysInfoStep = "Querying Pixellot software..."
    Si-Section "Pixellot Software"
    try {
        $pxReg  = Get-ItemProperty -Path "HKLM:\SOFTWARE\Pixellot" -ErrorAction Stop
        $pxVer  = if ($pxReg.PSObject.Properties['Version']      -and $pxReg.Version)      { $pxReg.Version }      else { "Not found" }
        $pxImg  = if ($pxReg.PSObject.Properties['ImageVersion'] -and $pxReg.ImageVersion) { $pxReg.ImageVersion } else { "Not found" }
        $pxDeps = if ($pxReg.PSObject.Properties['Dependencies'] -and $pxReg.Dependencies) { $pxReg.Dependencies } else { "Not found" }
        Si-Log "App Version"           $pxVer  "Info"
        Si-Log "System Image Version"  $pxImg  "Info"
        Si-Log "Package Dependencies"  $pxDeps "Info"
    } catch { Si-Log "Pixellot" "Registry key not found (HKLM:\SOFTWARE\Pixellot)" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Operating System --------------------------------------------------------
    $sync.SysInfoStep = "Querying operating system..."
    Si-Section "Operating System"
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        Si-Log "Edition"       $os.Caption                                                         "Info"
        Si-Log "Version"       $os.Version                                                         "Info"
        Si-Log "Build"         ([string]$os.BuildNumber)                                           "Info"
        Si-Log "Architecture"  $os.OSArchitecture                                                  "Info"
        Si-Log "Install Date"  $os.InstallDate.ToString("yyyy-MM-dd")                             "Info"
        $up = (Get-Date) - $os.LastBootUpTime
        $upStr = "$([int][Math]::Floor($up.TotalDays))d $($up.Hours)h $($up.Minutes)m"
        Si-Log "Uptime"        $upStr  "Info"
        # Cards (#5): OS edition (short) + uptime
        $osShort = ($os.Caption -replace '^Microsoft\s+','' -replace 'Windows\s+','Win ')
        $sync.Cards["SiOs"]     = @{ Value = "$osShort  ($($os.BuildNumber))"; Status="ok" }
        $sync.Cards["SiUptime"] = @{ Value = $upStr; Status = if ($up.TotalDays -gt 30) { "warn" } else { "ok" } }
    } catch { Si-Log "OS" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Time & Locale -----------------------------------------------------------
    # Surface timezone, NTP source, and auto-time setting. VPUs deployed across
    # regions sometimes inherit a UTC default which throws off scheduled events
    # and timestamped logs.
    $sync.SysInfoStep = "Querying time settings..."
    Si-Section "Time & Locale"
    try {
        $tz = Get-CimInstance Win32_TimeZone -ErrorAction Stop
        Si-Log "Timezone"       "$($tz.Caption)" "Info"
        Si-Log "System Time"    ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) "Info"

        # NTP server registry (W32Time service)
        try {
            $ntpServer = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ErrorAction Stop).NtpServer
            if ($ntpServer) { Si-Log "NTP Server" $ntpServer "Info" }
        } catch { }

        # "Set time automatically" — controlled by W32Time service start type + NtpClient SpecialPollInterval
        $w32Svc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
        if ($w32Svc) {
            if ($w32Svc.Status -eq "Running") {
                Si-Log "Time Sync" "W32Time service running" "Info"
            } else {
                Si-Log "Time Sync" "W32Time service NOT running — automatic time sync disabled" "Warn"
            }
        }

        # Suspicious-default warning: UTC is rarely the right choice for a deployed VPU
        if ($tz.StandardName -match "^UTC$" -or $tz.Caption -match "^\(UTC\)\s*Coordinated") {
            Si-Log "Timezone Check" "System is set to UTC — confirm this matches the venue's local timezone" "Warn"
        }
    } catch { Si-Log "Time & Locale" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- System ------------------------------------------------------------------
    $sync.SysInfoStep = "Querying system info..."
    Si-Section "System"
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        Si-Log "Computer Name" $cs.Name                                                             "Info"
        Si-Log "Manufacturer"  $cs.Manufacturer                                                     "Info"
        Si-Log "Model"         $cs.Model                                                            "Info"
        $dom = if ($cs.PartOfDomain) { "Domain: $($cs.Domain)" } else { "Workgroup: $($cs.Workgroup)" }
        Si-Log "Network"       $dom                                                                 "Info"
        Si-Log "System Type"   $cs.SystemType                                                       "Info"
        # Card (#5): manufacturer + model trimmed
        $modelStr = if ($cs.Manufacturer -and $cs.Model) { "$($cs.Manufacturer)  $($cs.Model)" } `
                    elseif ($cs.Model) { $cs.Model } else { "Unknown" }
        if ($modelStr.Length -gt 32) { $modelStr = $modelStr.Substring(0,29) + "..." }
        $sync.Cards["SiModel"] = @{ Value = $modelStr; Status="neutral" }
    } catch { Si-Log "System" "Query failed" "Warn" }
    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        Si-Log "BIOS"  "$($bios.SMBIOSBIOSVersion)  ($($bios.ReleaseDate.ToString('yyyy-MM-dd')))"  "Info"
        $ser = $bios.SerialNumber
        if ($ser -and $ser.Trim() -notin @("","System Serial Number","To Be Filled By O.E.M.","Default string")) {
            Si-Log "Serial Number" $ser.Trim()                                                      "Gray"
        }
    } catch { }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Processor ---------------------------------------------------------------
    $sync.SysInfoStep = "Querying processor..."
    Si-Section "Processor"
    $fdCpuShort = "Unknown CPU"
    try {
        $cpus = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        foreach ($cpu in $cpus) {
            Si-Log "Name"         $cpu.Name.Trim()                                                          "Info"
            Si-Log "Manufacturer" $cpu.Manufacturer                                                         "Info"
            Si-Log "Max Speed"    ("{0:F2} GHz" -f ($cpu.MaxClockSpeed / 1000.0))                           "Info"
            Si-Log "Cores"        "$($cpu.NumberOfCores) physical / $($cpu.NumberOfLogicalProcessors) logical"  "Info"
            if ($cpu.SocketDesignation) { Si-Log "Socket" $cpu.SocketDesignation                            "Info" }
        }
        if ($cpus.Count -gt 0) {
            $fdCpuShort = $cpus[0].Name.Trim() -replace 'Intel\(R\) Core\(TM\) ','Core ' -replace '\(R\)|\(TM\)','' -replace '\s+@\s.*','' -replace '\s+',' '
        }
        # Card (#5)
        $cpuCardVal = if ($fdCpuShort.Length -gt 32) { $fdCpuShort.Substring(0,29) + "..." } else { $fdCpuShort }
        $sync.Cards["SiCpu"] = @{ Value = $cpuCardVal; Status="neutral" }
    } catch { Si-Log "CPU" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Memory ------------------------------------------------------------------
    $sync.SysInfoStep = "Querying memory..."
    Si-Section "Memory"
    $fdRamGB = 0
    try {
        $os2 = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $fdRamGB = [int]([double]$os2.TotalVisibleMemorySize / 1048576.0 + 0.5)
        $fdRamFreeGB = [double]$os2.FreePhysicalMemory / 1048576.0
        Si-Log "Total RAM"  ("{0:F1} GB" -f ([double]$os2.TotalVisibleMemorySize / 1048576.0))     "Info"
        Si-Log "Available"  ("{0:F1} GB" -f $fdRamFreeGB)                                          "Info"
        # Card (#5): total + free
        $sync.Cards["SiRam"] = @{ Value = ("{0} GB total / {1:F1} GB free" -f $fdRamGB, $fdRamFreeGB); Status="ok" }
        $slots = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        $n = 1
        foreach ($s in $slots) {
            $sGB     = "{0} GB" -f [int]($s.Capacity / 1073741824)
            $memType = switch ([int]$s.SMBIOSMemoryType) { 24{"DDR3"} 26{"DDR4"} 34{"DDR5"} default{"DDR"} }
            $spd     = if ($s.Speed) { "$($s.Speed) MHz" } else { "" }
            $mfr     = $s.Manufacturer
            $mfrStr  = if ($mfr -and $mfr -notlike "*Unknown*" -and $mfr -notlike "*To Be*" -and $mfr.Trim() -ne "") { "  ($($mfr.Trim()))" } else { "" }
            Si-Log "Slot $n" "$sGB $memType $spd$mfrStr" "Info"
            $n++
        }
    } catch { Si-Log "Memory" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Graphics ----------------------------------------------------------------
    $sync.SysInfoStep = "Querying graphics..."
    Si-Section "Graphics"
    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
                  Where-Object { $_.Name -notlike "*Remote*" -and $_.Name -notlike "*Virtual*" })
        $discrete = @($gpus | Where-Object { $_.Name -notlike "*Intel*" -and $_.Name -notlike "*Microsoft*" })
        if ($discrete.Count -gt 0) { $gpus = $discrete }
        if ($gpus.Count -eq 0) { Si-Log "GPU" "None detected" "Warn" }
        foreach ($gpu in $gpus) {
            Si-Log "Name"   $gpu.Name                                                               "Info"
            if ($gpu.AdapterRAM -gt 0) {
                $vMB = [int]($gpu.AdapterRAM / 1048576)
                $vStr = if ($vMB -ge 1024) { "{0} GB" -f [int]($vMB / 1024) } else { "$vMB MB" }
                Si-Log "VRAM"   $vStr                                                               "Info"
            }
            if ($gpu.DriverVersion) { Si-Log "Driver" $gpu.DriverVersion                           "Gray" }
        }
    } catch { Si-Log "GPU" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Storage -----------------------------------------------------------------
    $sync.SysInfoStep = "Querying storage..."
    Si-Section "Storage"
    try {
        $disks = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Sort-Object Index)
        if ($disks.Count -eq 0) { Si-Log "Disks" "None detected" "Warn" }
        foreach ($d in $disks) {
            $sizeGB = "{0:F0} GB" -f ([double]$d.Size / 1073741824.0)
            Si-Log "Disk $($d.Index) - $($d.Model)" "$sizeGB  [$($d.InterfaceType)]"               "Info"
            if ($d.SerialNumber -and $d.SerialNumber.Trim()) {
                Si-Log "  Serial" $d.SerialNumber.Trim()                                            "Gray"
            }
        }
        # Card (#5): system drive free space
        $sysDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue
        if ($sysDrive) {
            $freeGB  = [math]::Round($sysDrive.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($sysDrive.Size      / 1GB, 1)
            $usedPct = [math]::Round((1 - $sysDrive.FreeSpace/$sysDrive.Size) * 100)
            $stStatus = if ($freeGB -lt 5) { "fail" } elseif ($freeGB -lt 15) { "warn" } else { "ok" }
            $sync.Cards["SiStorage"] = @{ Value = "$freeGB GB free  ($usedPct% used)"; Status=$stStatus }
        }
    } catch { Si-Log "Storage" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Network Adapters --------------------------------------------------------
    $sync.SysInfoStep = "Querying network adapters..."
    Si-Section "Network Adapters"
    try {
        $nics = @(Get-CimInstance Win32_NetworkAdapter -ErrorAction Stop |
                  Where-Object { $_.PhysicalAdapter -eq $true } | Sort-Object Index)
        if ($nics.Count -eq 0) { Si-Log "NICs" "None detected" "Warn" }
        foreach ($nic in $nics) {
            $mac = if ($nic.MACAddress) { $nic.MACAddress } else { "-" }
            Si-Log $nic.Name $mac "Info"
            if ($nic.Speed -and [long]$nic.Speed -gt 0) {
                $spd = [long]$nic.Speed
                $spdStr = if ($spd -ge 1000000000) { "{0} Gbps" -f [int]($spd/1000000000) } `
                          elseif ($spd -ge 1000000)  { "{0} Mbps" -f [int]($spd/1000000) } `
                          else { "$spd bps" }
                Si-Log "  Speed"  $spdStr "Info"
            }
            $connStatus = [int]$nic.NetConnectionStatus
            $connStr = switch ($connStatus) { 2{"Connected"} 7{"Media disconnected"} default{"Not connected"} }
            $connLvl = if ($connStatus -eq 2) { "Pass" } else { "Gray" }
            Si-Log "  Status" $connStr $connLvl
        }
    } catch { Si-Log "NICs" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Pixellot Calibrations ---------------------------------------------------
    # Surface known calibration directories and per-camera calibration files.
    # Helps field techs confirm a calibration was applied and which file is active.
    $sync.SysInfoStep = "Querying camera calibrations..."
    Si-Section "Pixellot Calibrations"
    $calibPaths = @(
        "C:\Pixellot\calibration"
        "C:\Pixellot\Calibration"
        "C:\Pixellot\Data\Calibration"
        "C:\Program Files\Pixellot\calibration"
        "C:\ProgramData\Pixellot\calibration"
    )
    $calibFound = $false
    foreach ($cp in $calibPaths) {
        if (Test-Path $cp) {
            $calibFound = $true
            Si-Log "Calibration Path" $cp "Info"
            try {
                $files = @(Get-ChildItem -Path $cp -File -ErrorAction SilentlyContinue |
                           Sort-Object LastWriteTime -Descending | Select-Object -First 12)
                if ($files.Count -eq 0) {
                    Si-Log "  Files" "Directory exists but is empty" "Warn"
                } else {
                    foreach ($f in $files) {
                        $age = (Get-Date) - $f.LastWriteTime
                        $ageStr = if ($age.TotalDays -ge 1) { "$([int]$age.TotalDays)d ago" } `
                                  elseif ($age.TotalHours -ge 1) { "$([int]$age.TotalHours)h ago" } `
                                  else { "$([int]$age.TotalMinutes)m ago" }
                        Si-Log "  $($f.Name)" "$ageStr   ($('{0:F0}' -f ($f.Length / 1024)) KB)" "Gray"
                    }
                }
            } catch { Si-Log "  Files" "Read failed" "Warn" }
        }
    }
    if (-not $calibFound) {
        Si-Log "Calibrations" "No calibration directory found in standard locations" "Gray"
    }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Installed Software ------------------------------------------------------
    # Scan registry uninstall keys (faster than Win32_Product, which triggers MSI re-validation).
    # Flag anything matching the unwanted-app patterns; surface counts only to keep the log readable.
    $sync.SysInfoStep = "Scanning installed software..."
    Si-Section "Installed Software"
    try {
        $unwantedPatterns = @(
            "OBS Studio", "vMix", "Wirecast", "XSplit",
            "Norton", "McAfee", "Avast", "AVG", "Bitdefender", "Kaspersky",
            "Bonjour", "iTunes", "QuickTime",
            "Yahoo", "Ask Toolbar", "Coupon", "WebDiscover",
            "Steam", "Epic Games", "Origin", "Battle.net",
            "BitTorrent", "uTorrent", "qBittorrent"
        )
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $apps = @(
            foreach ($p in $regPaths) {
                Get-ItemProperty $p -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
                    Select-Object DisplayName, Publisher, DisplayVersion, InstallDate
            }
        ) | Sort-Object DisplayName -Unique
        Si-Log "Total Installed" "$($apps.Count) applications" "Info"

        $flagged = @($apps | Where-Object {
            $name = $_.DisplayName
            $unwantedPatterns | Where-Object { $name -like "*$_*" } | Select-Object -First 1
        })
        if ($flagged.Count -gt 0) {
            Si-Log "Flagged Apps" "$($flagged.Count) potentially-conflicting applications detected" "Warn"
            foreach ($app in $flagged) {
                Si-Log "  $($app.DisplayName)" "$($app.Publisher) — confirm this is intentional" "Warn"
            }
        } else {
            Si-Log "Flagged Apps" "None — no known-conflicting software detected" "Pass"
        }
    } catch { Si-Log "Installed Software" "Scan failed" "Warn" }

    $ramStr = if ($fdRamGB -gt 0) { "$fdRamGB GB RAM" } else { "RAM unknown" }
    $sync.Cards["SysInfo"] = @{ Value = "$fdCpuShort   |   $ramStr"; Status = "ok" }
    $sync.SysInfoRunning = $false
    $sync.SysInfoComplete = $true
}

# ---------- Panel (v1.0.43 redesign) ---------------------------------------
$pnlSysInfo = New-Object System.Windows.Forms.Panel
$pnlSysInfo.Size      = New-Object System.Drawing.Size($WideW, $ContentH)
$pnlSysInfo.Location  = New-Object System.Drawing.Point($SideW, $ContentY)
$pnlSysInfo.BackColor = $ColBg
$pnlSysInfo.Anchor    = $AnchorTLRB
$pnlSysInfo.Visible   = $false
$form.Controls.Add($pnlSysInfo)
$script:allNavPanels += $pnlSysInfo

$siHeader = New-SectionHeader -Parent $pnlSysInfo `
    -Title    "System Information" `
    -Subtitle "Hardware specs, OS version, uptime, time/locale, and Pixellot software inventory."

# Summary cards — Model / OS / Uptime / CPU / RAM / Storage
$siCardDefs = @(
    @{ Key="SiModel";   Title="Model";    Sub="Manufacturer + product";    Icon=[char]0xE7F8 }
    @{ Key="SiOs";      Title="OS";       Sub="Edition + build";           Icon=[char]0xE770 }
    @{ Key="SiUptime";  Title="Uptime";   Sub="Since last boot";           Icon=[char]0xE823 }
    @{ Key="SiCpu";     Title="CPU";      Sub="Processor";                 Icon=[char]0xE950 }
    @{ Key="SiRam";     Title="RAM";      Sub="Installed memory";          Icon=[char]0xEDA2 }
    @{ Key="SiStorage"; Title="Storage";  Sub="System drive free space";   Icon=[char]0xE8B7 }
)
$siCards = @{}
$siCardW = 200; $siCardGap = 10; $siCardX = 28
foreach ($scd in $siCardDefs) {
    $sc = New-StatusCard -Title $scd.Title -X $siCardX -Y 110 -Icon $scd.Icon -Sub $scd.Sub -CardW $siCardW -CardH 80
    $siCards[$scd.Key] = $sc
    $pnlSysInfo.Controls.Add($sc.Panel)
    $siCardX += $siCardW + $siCardGap
}

# Detail log card (left) + Summary panel (right)
$siLogCard = New-Object System.Windows.Forms.Panel
$siLogCard.Size      = New-Object System.Drawing.Size(800, 460)
$siLogCard.Location  = New-Object System.Drawing.Point(28, 210)
$siLogCard.BackColor = $ColCard
$siLogCard.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 800, 460)), 8))
$pnlSysInfo.Controls.Add($siLogCard)

$lblSiLogHdr = New-Object System.Windows.Forms.Label
$lblSiLogHdr.Text      = "System Inventory"
$lblSiLogHdr.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$lblSiLogHdr.ForeColor = $ColText
$lblSiLogHdr.Location  = New-Object System.Drawing.Point(16, 12)
$lblSiLogHdr.AutoSize  = $true
$siLogCard.Controls.Add($lblSiLogHdr)

$siGrid = New-LogGrid -X 8 -Y 38 -W 784 -H 414 -LabelColW 200
$siLogCard.Controls.Add($siGrid)

$siSummary = New-SummaryPanel -Parent $pnlSysInfo -X 844 -Y 210 -W 420 -H 460 -Title "Summary"
Set-SummaryItems $siSummary @(@{ Status="neutral"; Text="Refresh to populate the summary" })

# Action bar — System Info uses Refresh (per-tab) since the engine is fast
$siActions = New-ActionBar -Parent $pnlSysInfo -Y 698 -ExportText "Export Report" -PrimaryText ([char]0xE72C + "  Refresh")
$btnSiRefresh = $siActions.PrimaryBtn
$btnSiExport  = $siActions.ExportBtn

$lblSiStatus = New-Object System.Windows.Forms.Label
$lblSiStatus.Text      = "Ready"
$lblSiStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSiStatus.ForeColor = $ColMuted
$lblSiStatus.Location  = New-Object System.Drawing.Point(28, 686)
$lblSiStatus.Size      = New-Object System.Drawing.Size(($pnlSysInfo.Width - 56), 16)
$lblSiStatus.Anchor    = $AnchorBLR
$pnlSysInfo.Controls.Add($lblSiStatus)

# ---------- Timer -----------------------------------------------------------
$sysInfoTimer = New-Object System.Windows.Forms.Timer
$sysInfoTimer.Interval = 150
$sysInfoTimer.Add_Tick({
    $item = $null
    while ($sync.SysInfoQueue.TryDequeue([ref]$item)) {
        Add-LogRow $siGrid $item.Label $item.Result $item.L
    }
    # Refresh the summary cards from $sync.Cards (#5)
    foreach ($key in $siCards.Keys) {
        $sc = $sync.Cards[$key]
        if ($sc -and $siCards[$key].ValueLabel.Text -ne $sc.Value) {
            Update-CardStatus -Card $siCards[$key] -Value $sc.Value -Status $sc.Status
        }
    }
    if ($sync.SysInfoComplete) {
        $sysInfoTimer.Stop()
        $btnSiRefresh.Enabled = $true
        $btnSiRefresh.Text    = [char]0xE72C + "  Refresh"
        $lblSiStatus.Text     = "Collected at $(Get-Date -Format 'h:mm:ss tt')"
        Set-SectionPill $siHeader "ok"
        $sumItems = @()
        foreach ($k in @("SiModel","SiOs","SiUptime","SiCpu","SiRam","SiStorage")) {
            $c = $sync.Cards[$k]
            if ($c -and $c.Value -ne "--") {
                $label = switch ($k) { "SiModel"{"Model"} "SiOs"{"OS"} "SiUptime"{"Uptime"} "SiCpu"{"CPU"} "SiRam"{"RAM"} "SiStorage"{"Storage"} }
                $st = if ($c.Status -in @("ok","warn","fail")) { $c.Status } else { "ok" }
                $sumItems += @{ Status=$st; Text="$($label): $($c.Value)" }
            }
        }
        if ($sumItems.Count -eq 0) { $sumItems = @(@{ Status="neutral"; Text="No data collected" }) }
        Set-SummaryItems $siSummary $sumItems
    } else {
        $lblSiStatus.Text = $sync.SysInfoStep
    }
})

# ---------- Collection function ---------------------------------------------
function Start-SysInfoCollection {
    if ($sync.SysInfoRunning) { return }
    $siGrid.Rows.Clear()
    # Reset the summary cards on refresh (#5)
    foreach ($key in $siCards.Keys) {
        $sync.Cards[$key] = @{ Value="--"; Status="neutral" }
        Update-CardStatus -Card $siCards[$key] -Value "--" -Status "neutral"
    }
    $btnSiRefresh.Enabled  = $false
    $lblSiStatus.Text      = "Collecting..."
    $sync.SysInfoComplete  = $false
    $sync.SysInfoCancelled = $false
    $sync.SysInfoStep      = "Starting..."
    if ($script:sysInfoRunspace) {
        try { $script:sysInfoRunspace.Close(); $script:sysInfoRunspace.Dispose() } catch { }
    }
    if ($script:sysInfoPs) {
        try { $script:sysInfoPs.Dispose() } catch { }; $script:sysInfoPs = $null
    }
    $script:sysInfoRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:sysInfoRunspace.ApartmentState = "STA"
    $script:sysInfoRunspace.ThreadOptions  = "ReuseThread"
    $script:sysInfoRunspace.Open()
    # Pass $sync to the runspace via AddArgument only — using SessionStateProxy.SetVariable
    # AND AddArgument both was wasted work and made the contract ambiguous.
    $script:sysInfoPs = [System.Management.Automation.PowerShell]::Create()
    $script:sysInfoPs.Runspace = $script:sysInfoRunspace
    $script:sysInfoPs.AddScript($SysInfoScript).AddArgument($sync) | Out-Null
    $script:sysInfoPs.BeginInvoke() | Out-Null
    $sysInfoTimer.Start()
}

$btnSiRefresh.Add_Click({ Start-SysInfoCollection })

$pnlSysInfo.Add_VisibleChanged({
    if ($this.Visible -and -not $sync.SysInfoRunning -and -not $sync.SysInfoComplete) {
        Start-SysInfoCollection
    }
})
