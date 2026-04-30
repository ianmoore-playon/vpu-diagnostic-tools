# =============================================================================
#  HardwareOverview.psm1  -  System Overview panel
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
        Si-Log "Uptime"        "$([int][Math]::Floor($up.TotalDays))d $($up.Hours)h $($up.Minutes)m"  "Info"
    } catch { Si-Log "OS" "Query failed" "Warn" }

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
    } catch { Si-Log "CPU" "Query failed" "Warn" }

    if ($sync.SysInfoCancelled) { $sync.SysInfoRunning=$false; $sync.SysInfoComplete=$true; return }

    # -- Memory ------------------------------------------------------------------
    $sync.SysInfoStep = "Querying memory..."
    Si-Section "Memory"
    $fdRamGB = 0
    try {
        $os2 = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $fdRamGB = [int]([double]$os2.TotalVisibleMemorySize / 1048576.0 + 0.5)
        Si-Log "Total RAM"  ("{0:F1} GB" -f ([double]$os2.TotalVisibleMemorySize / 1048576.0))     "Info"
        Si-Log "Available"  ("{0:F1} GB" -f ([double]$os2.FreePhysicalMemory     / 1048576.0))     "Info"
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
            Si-Log "Disk $($d.Index) — $($d.Model)" "$sizeGB  [$($d.InterfaceType)]"               "Info"
            if ($d.SerialNumber -and $d.SerialNumber.Trim()) {
                Si-Log "  Serial" $d.SerialNumber.Trim()                                            "Gray"
            }
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
            $mac = if ($nic.MACAddress) { $nic.MACAddress } else { "—" }
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

    $ramStr = if ($fdRamGB -gt 0) { "$fdRamGB GB RAM" } else { "RAM unknown" }
    $sync.Cards["SysInfo"] = @{ Value = "$fdCpuShort   |   $ramStr"; Status = "ok" }
    $sync.SysInfoRunning = $false
    $sync.SysInfoComplete = $true
}

# ---------- Panel -----------------------------------------------------------
$pnlSysInfo = New-Object System.Windows.Forms.Panel
$pnlSysInfo.Size      = New-Object System.Drawing.Size($ContentW, $ContentH)
$pnlSysInfo.Location  = New-Object System.Drawing.Point(0, $ContentY)
$pnlSysInfo.BackColor = $ColBg
$pnlSysInfo.Anchor    = $AnchorTLRB
$pnlSysInfo.Visible   = $false
$form.Controls.Add($pnlSysInfo)
$script:allNavPanels += $pnlSysInfo

$lblSiTitle = New-Object System.Windows.Forms.Label
$lblSiTitle.Text      = "System Overview"
$lblSiTitle.Font      = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
$lblSiTitle.ForeColor = $ColText
$lblSiTitle.Location  = New-Object System.Drawing.Point(30, 24)
$lblSiTitle.Size      = New-Object System.Drawing.Size(700, 28)
$pnlSysInfo.Controls.Add($lblSiTitle)

$lblSiSub = New-Object System.Windows.Forms.Label
$lblSiSub.Text      = "Hardware and operating system details for this VPU."
$lblSiSub.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSiSub.ForeColor = $ColMuted
$lblSiSub.Location  = New-Object System.Drawing.Point(30, 56)
$lblSiSub.Size      = New-Object System.Drawing.Size(800, 18)
$pnlSysInfo.Controls.Add($lblSiSub)

$btnSiRefresh = New-Object System.Windows.Forms.Button
$btnSiRefresh.Text      = [char]0xE72C + "  Refresh"
$btnSiRefresh.Size      = New-Object System.Drawing.Size(120, 32)
$btnSiRefresh.Location  = New-Object System.Drawing.Point(30, 86)
$btnSiRefresh.BackColor = $ColCard
$btnSiRefresh.ForeColor = $ColText
$btnSiRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSiRefresh.FlatAppearance.BorderSize = 0
$btnSiRefresh.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
$btnSiRefresh.Cursor    = [System.Windows.Forms.Cursors]::Hand
$btnSiRefresh.Region    = New-Object System.Drawing.Region([GfxHelper]::RoundedRect((New-Object System.Drawing.Rectangle(0, 0, 120, 32)), 6))
$pnlSysInfo.Controls.Add($btnSiRefresh)

$lblSiStatus = New-Object System.Windows.Forms.Label
$lblSiStatus.Text      = "Ready"
$lblSiStatus.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSiStatus.ForeColor = $ColMuted
$lblSiStatus.Location  = New-Object System.Drawing.Point(162, 94)
$lblSiStatus.Size      = New-Object System.Drawing.Size(400, 18)
$pnlSysInfo.Controls.Add($lblSiStatus)

$siGrid = New-LogGrid -X 30 -Y 130 -W ($ContentW - 60) -H ($ContentH - 140) -LabelColW 240
$pnlSysInfo.Controls.Add($siGrid)

# ---------- Timer -----------------------------------------------------------
$sysInfoTimer = New-Object System.Windows.Forms.Timer
$sysInfoTimer.Interval = 150
$sysInfoTimer.Add_Tick({
    $item = $null
    while ($sync.SysInfoQueue.TryDequeue([ref]$item)) {
        Add-LogRow $siGrid $item.Label $item.Result $item.L
    }
    if ($sync.SysInfoComplete) {
        $sysInfoTimer.Stop()
        $btnSiRefresh.Enabled = $true
        $lblSiStatus.Text = "Collected at $(Get-Date -Format 'HH:mm:ss')"
    } else {
        $lblSiStatus.Text = $sync.SysInfoStep
    }
})

# ---------- Collection function ---------------------------------------------
function Start-SysInfoCollection {
    if ($sync.SysInfoRunning) { return }
    $siGrid.Rows.Clear()
    $btnSiRefresh.Enabled  = $false
    $lblSiStatus.Text      = "Collecting..."
    $sync.SysInfoComplete  = $false
    $sync.SysInfoCancelled = $false
    $sync.SysInfoStep      = "Starting..."
    if ($script:sysInfoRunspace) {
        try { $script:sysInfoRunspace.Close(); $script:sysInfoRunspace.Dispose() } catch { }
    }
    $script:sysInfoRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $script:sysInfoRunspace.ApartmentState = "STA"
    $script:sysInfoRunspace.ThreadOptions  = "ReuseThread"
    $script:sysInfoRunspace.Open()
    $script:sysInfoRunspace.SessionStateProxy.SetVariable("sync", $sync)
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $script:sysInfoRunspace
    $ps.AddScript($SysInfoScript).AddArgument($sync) | Out-Null
    $ps.BeginInvoke() | Out-Null
    $sysInfoTimer.Start()
}

$btnSiRefresh.Add_Click({ Start-SysInfoCollection })

$pnlSysInfo.Add_VisibleChanged({
    if ($this.Visible -and -not $sync.SysInfoRunning -and -not $sync.SysInfoComplete) {
        Start-SysInfoCollection
    }
})
