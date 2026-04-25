# =============================================================================
#  Test-PixellotCameraLinks.ps1
#  Diagnoses camera connection link speed issues on Pixellot VPUs.
#
#  Targets the Intel(R) 82574L 4-port POE NIC used for camera connections.
#  Checks each port for link speed, attempts to force 1 Gbps if degraded,
#  and scans the Windows event log for Intel SmartSpeed downgrade messages.
#
#  HOW TO RUN (one-liner - no file transfer needed):
#    Open any PowerShell window (does NOT need to be elevated - script self-elevates) and run:
#
#      irm 'https://raw.githubusercontent.com/ianmoore-playon/pixellot-vpu-tools/refs/heads/main/TestCameraConnectivity.ps1' | iex
#
#    Results are saved to the Desktop as CameraLink_Results_YYYYMMDD_HHMMSS.txt.
#    When run from a local copy, results save next to the script instead.
#
#  WHAT IT DOES:
#    1. Finds all Intel 82574L NIC ports by driver description
#    2. Reports current link speed for each port
#    3. For any port running at 100 Mbps:
#       a. Attempts to force the adapter to 1 Gbps Full Duplex
#       b. Waits for re-negotiation
#       c. Checks the resulting link speed
#       d. If still not 1 Gbps, resets back to Auto Negotiation
#    4. Scans Windows System event log for Intel SmartSpeed downgrade messages
#    5. Shows a clear summary and saves full results to a .txt file
# =============================================================================

# GitHub raw URL - update this after creating the repo so self-elevation works via irm | iex
$ScriptUrl = "https://raw.githubusercontent.com/ianmoore-playon/pixellot-vpu-tools/refs/heads/main/TestCameraConnectivity.ps1"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        # Running from a local file - re-launch the file as admin
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # Running via irm | iex - re-launch by downloading again as admin
        Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$ScriptUrl' | iex`""
    }
    exit
}

# ---------- Configuration ----------------------------------------------------

$ScriptVersion     = "2.7"
$RunId             = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputBaseDir     = if ($PSScriptRoot) { $PSScriptRoot } else { [Environment]::GetFolderPath('Desktop') }
$OutputDir         = Join-Path $OutputBaseDir "CameraLink_Results"
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }
$OutputFile        = Join-Path $OutputDir "CameraLink_Results_$RunId.txt"
$NicDriverPatterns = @(                   # Driver descriptions to match camera NIC ports
    "Intel(R) 82574L*"                    #   4-port POE NIC (most VPUs)
    "Intel(R) I210*"                      #   I210 NIC (newer VPU models)
)
$RenegotiateWaitSec = 30                  # Seconds to wait after forcing speed change
$EventLogHours     = 48                   # How many hours back to scan the event log
$PixellotLogPaths  = @(                   # Pixellot application log search paths
    "C:\Pixellot\Data\Log"               #   Primary (confirmed path)
    "C:\Pixellot\logs"
    "C:\Pixellot\Logs"
    "C:\Program Files\Pixellot\logs"
    "C:\ProgramData\Pixellot\logs"
)
$CameraIPs         = @(                   # Fixed link-local IPs assigned by Pixellot firmware
    [PSCustomObject]@{ IP = "169.254.16.50"; Label = "Camera 1 (main)";       Optional = $false }
    [PSCustomObject]@{ IP = "169.254.16.51"; Label = "Camera 2 / DoublePlay"; Optional = $false }
    # OCR camera at .52 is optional — not all units are configured with one
    [PSCustomObject]@{ IP = "169.254.16.52"; Label = "OCR camera (optional)"; Optional = $true  }
)
$RtspPort          = 554                  # Standard RTSP port used by all Pixellot cameras

# ---------- Helper Functions -------------------------------------------------

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
    Add-Content -Path $OutputFile -Value $Message
}

function Write-LogOnly {
    param([string]$Message)
    Add-Content -Path $OutputFile -Value $Message
}

function Get-AdapterSpeedMbps {
    param([string]$AdapterName)
    # Returns current link speed in Mbps, or 0 if disconnected/unknown
    # LinkSpeed is a formatted string ("100 Mbps", "1 Gbps") on Windows Server / PS 5.1
    try {
        $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction Stop
        if ($adapter.Status -ne "Up") { return 0 }
        $ls = $adapter.LinkSpeed.ToString()
        if ($ls -match '(\d+(?:\.\d+)?)\s*Gbps') { return [int]([double]$Matches[1] * 1000) }
        if ($ls -match '(\d+(?:\.\d+)?)\s*Mbps') { return [int]$Matches[1] }
        # Fallback: raw bits/sec (numeric string)
        if ($ls -match '^\d+$') { return [math]::Round([double]$ls / 1e6) }
        return -1
    } catch {
        return -1
    }
}

function Get-AdapterPeakSpeedMbps {
    param([string]$AdapterName, [int]$SampleSeconds = 12, [int]$IntervalMs = 750)
    # Samples repeatedly to catch intermittent links that blink due to SmartSpeed
    # retry cycles — a degraded port can appear disconnected for several seconds at
    # a time while the NIC reattempts gigabit negotiation.
    $peak     = 0
    $deadline = (Get-Date).AddSeconds($SampleSeconds)
    while ((Get-Date) -lt $deadline) {
        $s = Get-AdapterSpeedMbps -AdapterName $AdapterName
        if ($s -gt $peak) { $peak = $s }
        if ($peak -ge 1000) { break }   # Gigabit confirmed — no need to keep sampling
        Start-Sleep -Milliseconds $IntervalMs
    }
    return $peak
}

function Get-SpeedDisplayString {
    param([int]$Mbps)
    switch ($Mbps) {
        0    { return "Disconnected / No Link" }
        -1   { return "Unknown" }
        100  { return "100 Mbps  *** DEGRADED ***" }
        1000 { return "1 Gbps  (OK)" }
        default { return "$Mbps Mbps" }
    }
}

function Set-AdapterSpeedDuplex {
    param([string]$AdapterName, [string]$SpeedDuplexValue)
    # SpeedDuplexValue registry values for Intel 82574L:
    #   "0"  = Auto Negotiation
    #   "6"  = 1.0 Gbps Full Duplex
    #   "4"  = 100 Mbps Full Duplex
    # Modern Intel drivers register as "*SpeedDuplex"; older as "SpeedDuplex"
    foreach ($kw in @('*SpeedDuplex', 'SpeedDuplex')) {
        try {
            Get-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -ErrorAction Stop | Out-Null
            Set-NetAdapterAdvancedProperty -Name $AdapterName `
                -RegistryKeyword $kw -RegistryValue $SpeedDuplexValue -ErrorAction Stop
            return $true
        } catch { continue }
    }
    return $false
}

function Get-CurrentSpeedDuplexSetting {
    param([string]$AdapterName)
    try {
        $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName `
                -RegistryKeyword "SpeedDuplex" -ErrorAction Stop
        return $prop.RegistryValue
    } catch {
        return $null
    }
}

function Test-TcpPort {
    param([string]$IP, [int]$Port, [int]$TimeoutMs = 2000)
    # Uses raw sockets to avoid Test-NetConnection's verbose console output
    try {
        $tcp     = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($IP, $Port, $null, $null)
        $ok      = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok) { $tcp.EndConnect($connect) }
        $tcp.Close()
        return $ok
    } catch {
        return $false
    }
}

function Wait-WithSpinner {
    param([int]$Seconds, [string]$Message)
    $spinner = @('|', '/', '-', '\')
    $i = 0
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $remaining = [math]::Max(0, [int]($deadline - (Get-Date)).TotalSeconds)
        Write-Host ("`r  {0}  {1} ({2}s remaining)  " -f $spinner[$i % 4], $Message, $remaining) -NoNewline -ForegroundColor Yellow
        $i++
        Start-Sleep -Milliseconds 250
    }
    Write-Host ("`r" + (" " * 72) + "`r") -NoNewline
}

function Get-EventAdapterName {
    param($WinEvt, [string[]]$KnownDescriptions)
    # Method 1: formatted message text — first line is the adapter name when DLL is available
    $name = try {
        $msg = $WinEvt.Message
        if ($msg -and $msg -notlike "*description string*") {
            ($msg -split "`n")[0].Trim()
        } else { "" }
    } catch { "" }
    if ($KnownDescriptions -contains $name) { return $name }

    # Method 2: XML data elements matched against known descriptions
    $name = try {
        $data = @(([xml]$WinEvt.ToXml()).Event.EventData.Data)
        $found = ""
        foreach ($d in $data) {
            $text = $d.InnerText
            if ($KnownDescriptions -contains $text.Trim()) { $found = $text.Trim(); break }
        }
        $found
    } catch { "" }
    if ($KnownDescriptions -contains $name) { return $name }

    # Method 3: Properties collection
    $name = try {
        $found = ""
        foreach ($prop in $WinEvt.Properties) {
            $val = $prop.Value.ToString().Trim()
            if ($KnownDescriptions -contains $val) { $found = $val; break }
        }
        $found
    } catch { "" }
    return $name
}

# ---------- Main Script ------------------------------------------------------

"" | Set-Content -Path $OutputFile
$timestamp       = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$ScriptStartTime = Get-Date

$portResults     = @()   # Collect per-port results for summary
$ocrAdapters     = @{}   # Adapter descriptions identified as OCR / 100 Mbps-only
$cameraAppIssues = @()   # Camera failures found in Pixellot application log
$cameraConnResults = @() # Ping + RTSP connectivity results per camera IP
$latestLog       = $null # Most recent CamerasTester log found during analysis

# ── VPU model detection ───────────────────────────────────────────────────────
$VpuModel  = $null
$VpuUnitId = $null
$VpuType   = $null

# Primary: agent_*.log is written every 5 min by the Pixellot agent process,
# independent of whether VPU Manager is open in a browser.
foreach ($logPath in $PixellotLogPaths) {
    if (-not (Test-Path $logPath)) { continue }
    $agentLog = Get-ChildItem -Path $logPath -Filter "agent_*.log" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $agentLog) { continue }
    $agentLines = Get-Content -Path $agentLog.FullName -ErrorAction SilentlyContinue
    if (-not $agentLines) { continue }
    foreach ($line in $agentLines) {
        if (-not $VpuModel -and $line -match '"paramName"\s*:\s*"vpuName"[^}]*"paramValue"\s*:\s*"([^"]+)"') {
            $raw = $Matches[1]
            if ($raw -match '^(PXL\w+?)_(\d+)') { $VpuModel = $Matches[1]; $VpuUnitId = $Matches[2] }
        }
        if (-not $VpuType -and $line -match '"paramName"\s*:\s*"presentedProductType"[^}]*"paramValue"\s*:\s*"([^"]+)"') {
            $VpuType = $Matches[1]
        }
        if ($VpuModel -and $VpuType) { break }
    }
    if ($VpuModel) { break }
}

# Fallback: scrape VPU Manager SPA title (only resolves when browser is open)
if (-not $VpuModel) {
    try {
        $page = Invoke-WebRequest -Uri "http://localhost:32323/" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($page.Content -match '<title>[^<]*(PXL\w+?)_(\d+)') {
            $VpuModel  = $Matches[1]
            $VpuUnitId = $Matches[2]
        }
    } catch { }
}

$VpuModelDisplay = if ($VpuModel) {
    $typeStr = if ($VpuType) { " / $VpuType" } else { "" }
    "$VpuModel  (Unit ID: $VpuUnitId)$typeStr"
} else { "Not detected (VPU Manager offline?)" }

$header = @"
================================================================
 Pixellot VPU - Camera Link Speed Diagnostic  v$ScriptVersion
================================================================
 Computer : $($env:COMPUTERNAME)
 User     : $($env:USERNAME)
 Date/Time: $timestamp
 Run ID   : $RunId
 VPU Model: $VpuModelDisplay
 NIC      : Intel(R) 82574L / I210 (camera POE ports)
================================================================
"@
Write-Host $header -ForegroundColor White
Add-Content -Path $OutputFile -Value $header

# ── Find all camera NIC ports ─────────────────────────────────────────────────
Write-Log ""
Write-Log "-- Detecting Camera NIC Ports -----------------------------------" "Cyan"
Write-Log ""

$nicPorts = Get-NetAdapter | Where-Object {
    $desc = $_.InterfaceDescription
    ($NicDriverPatterns | Where-Object { $desc -like $_ }).Count -gt 0
} | Sort-Object Name

if ($nicPorts.Count -eq 0) {
    Write-Log "  [FAIL] No camera NIC adapters found on this system." "Red"
    Write-Log "         Expected: $($NicDriverPatterns -join ', ')" "Red"
    Write-Log "         Verify the NIC is installed and drivers are loaded." "Red"
    Write-Log ""
    Write-Log " Press any key to close..."
    [void][System.Console]::ReadKey($true)
    exit
}

Write-Log ("  Found {0} camera NIC port(s):" -f $nicPorts.Count) "White"
foreach ($n in $nicPorts) {
    Write-Log ("    - {0}  ({1})" -f $n.Name, $n.InterfaceDescription) "White"
}
Write-Log ""

# ── SmartSpeed Pre-Scan (runs before port tests to gate remediation) ──────────
# Collects events from the look-back window up to the moment the script started,
# so that actions taken by this script cannot falsify the results.
$cutoffTime          = (Get-Date).AddHours(-$EventLogHours)
$intelProviders      = @('e1iexpress', 'e1dexpress', 'e1rexpress')
$smartSpeedEventIds  = @(27, 33, 40)
$knownAdapterDescs   = @($nicPorts | ForEach-Object { $_.InterfaceDescription })

$events = @()
$smartSpeedAdapterHistory = @{}   # adapter description -> count of ID 40 events (pre-script only)

foreach ($provider in $intelProviders) {
    $provEvents = Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        StartTime    = $cutoffTime
        EndTime      = $ScriptStartTime
        ProviderName = $provider
        Id           = $smartSpeedEventIds
    } -ErrorAction SilentlyContinue
    if ($provEvents) {
        $events += $provEvents
        foreach ($evt in ($provEvents | Where-Object { $_.Id -eq 40 })) {
            $adName = Get-EventAdapterName -WinEvt $evt -KnownDescriptions $knownAdapterDescs
            if ($adName) {
                $smartSpeedAdapterHistory[$adName] = ($smartSpeedAdapterHistory[$adName] -as [int]) + 1
            }
        }
    }
}

# ── Check each port ───────────────────────────────────────────────────────────
Write-Log "-- Link Speed Check ---------------------------------------------" "Cyan"
Write-Log ""

foreach ($nic in $nicPorts) {
    $name        = $nic.Name
    $status      = $nic.Status
    $speedMbps   = Get-AdapterSpeedMbps -AdapterName $name
    $blinking    = $false

    Write-Log ("  Adapter  : {0}" -f $name) "White"
    Write-Log ("  Driver   : {0}" -f $nic.InterfaceDescription) "White"
    Write-Log ("  Status   : {0}" -f $status) "White"
    Write-Log ("  MAC      : {0}" -f $nic.MacAddress) "White"

    # If no link on the first read, sample for 12 seconds before concluding NO LINK.
    # A degraded port undergoing SmartSpeed retry cycles can blink every few seconds —
    # the NIC drops the link briefly each time it reattempts gigabit negotiation.
    if ($speedMbps -eq 0) {
        Write-Log "  [INFO]   No link on initial check - sampling for 12 seconds to catch intermittent connections..." "Yellow"
        $peak = Get-AdapterPeakSpeedMbps -AdapterName $name -SampleSeconds 12
        if ($peak -gt 0) {
            $blinking  = $true
            $speedMbps = $peak
            Write-Log ("  [INFO]   Intermittent link detected - port is blinking at {0} (SmartSpeed retry cycle)" -f (Get-SpeedDisplayString -Mbps $speedMbps)) "Yellow"
        }
    }

    $speedString = Get-SpeedDisplayString -Mbps $speedMbps

    if ($speedMbps -eq 1000) {
        Write-Log ("  Speed    : {0}" -f $speedString) "Green"
        Write-Log ""
        $portResults += [PSCustomObject]@{
            Name = $name; Speed = $speedMbps; Result = "PASS"; Action = "None"; Blinking = $blinking
        }

    } elseif ($speedMbps -eq 100) {
        Write-Log ("  Speed    : {0}" -f $speedString) "Red"
        Write-Log ""

        # Gate remediation on pre-existing SmartSpeed ID 40 history for this adapter.
        # No history = 100 Mbps-only device (OCR camera). SmartSpeed only fires when
        # the physical medium fails to sustain gigabit — not when the device simply
        # doesn't advertise it.
        if (-not $smartSpeedAdapterHistory.ContainsKey($nic.InterfaceDescription)) {
            Write-Log "  [PASS]   No SmartSpeed downgrade history for this adapter." "Green"
            Write-Log "           100 Mbps-only device detected (OCR scoreboard camera)." "Green"
            Write-Log "           Skipping remediation - 100 Mbps is expected on this port." "Green"
            $ocrAdapters[$nic.InterfaceDescription] = $true
            $portResults += [PSCustomObject]@{
                Name = $name; Speed = $speedMbps; Result = "PASS (OCR)"; Action = "OCR scoreboard camera - 100 Mbps is expected"; Blinking = $blinking
            }
            Write-Log ""
            continue
        }

        Write-Log "  [ACTION] SmartSpeed downgrade history confirmed - attempting to force 1 Gbps..." "Yellow"

        # Step 1: Force 1 Gbps Full Duplex (registry value "6")
        $forceOk = Set-AdapterSpeedDuplex -AdapterName $name -SpeedDuplexValue "6"

        if (-not $forceOk) {
            Write-Log "  [FAIL]   Could not apply speed change. SpeedDuplex property not found on this adapter." "Red"
            Write-Log "           Open Device Manager > adapter Properties > Advanced tab to verify." "Red"
            $portResults += [PSCustomObject]@{
                Name = $name; Speed = $speedMbps; Result = "FAIL"; Action = "Could not apply SpeedDuplex setting - check Device Manager Advanced tab"; Blinking = $blinking
            }
            Write-Log ""
            continue
        }

        Write-Log ("  [INFO]   Speed set to 1 Gbps Full Duplex. Waiting {0} seconds for re-negotiation..." -f $RenegotiateWaitSec) "Yellow"
        Wait-WithSpinner -Seconds $RenegotiateWaitSec -Message "Waiting for re-negotiation"

        # Step 2: Check resulting speed
        $newSpeedMbps = Get-AdapterSpeedMbps -AdapterName $name
        $newSpeedString = Get-SpeedDisplayString -Mbps $newSpeedMbps

        if ($newSpeedMbps -eq 1000) {
            Write-Log "  [PASS]   Successfully negotiated 1 Gbps after forcing speed." "Green"
            Write-Log "           NOTE: This may indicate the connected device needed" "Yellow"
            Write-Log "           a manual push to negotiate gigabit. Monitor this port." "Yellow"
            Write-Log "           Speed setting left at 1 Gbps Full Duplex (not Auto)." "Yellow"
            $portResults += [PSCustomObject]@{
                Name = $name; Speed = $newSpeedMbps; Result = "PASS (forced)"
                Action = "Forced to 1 Gbps - monitor port; connected device may not support auto-negotiation"; Blinking = $blinking
            }
        } else {
            # Step 3: Forcing failed - reset to Auto Negotiation (registry value "0")
            Write-Log ("  [FAIL]   Still not at 1 Gbps after forcing (current: {0})." -f $newSpeedString) "Red"
            Write-Log "           Physical layer issue likely (cable, termination, RJ45 pins, or camera port)." "Red"
            Write-Log "           Resetting adapter back to Auto Negotiation..." "Yellow"

            $resetOk = Set-AdapterSpeedDuplex -AdapterName $name -SpeedDuplexValue "0"
            if ($resetOk) {
                Write-Log "  [INFO]   Adapter reset to Auto Negotiation. Waiting for link to restore..." "Yellow"
                $autoElapsed = 0
                $autoSpeed   = 0
                while ($autoElapsed -lt $RenegotiateWaitSec) {
                    Wait-WithSpinner -Seconds 2 -Message "Waiting for link to restore ($autoElapsed`s elapsed)"
                    $autoElapsed += 2
                    $autoSpeed = Get-AdapterSpeedMbps -AdapterName $name
                    if ($autoSpeed -gt 0) { break }
                }
                if ($autoSpeed -gt 0) {
                    Write-Log ("  [INFO]   Link restored at: {0}" -f (Get-SpeedDisplayString -Mbps $autoSpeed)) "Yellow"
                } else {
                    Write-Log "  [WARN]   Link did not restore within $RenegotiateWaitSec seconds after reset." "Red"
                }
            } else {
                Write-Log "  [WARN]   Could not reset to Auto Negotiation - set manually in Device Manager." "Red"
                $autoSpeed = 0
            }

            $portResults += [PSCustomObject]@{
                Name = $name; Speed = $autoSpeed; Result = "FAIL"
                Action = "Physical layer issue - check cable, termination, RJ45 pins, and camera port"; Blinking = $blinking
            }
        }
        Write-Log ""

    } elseif ($speedMbps -eq 0) {
        Write-Log ("  Speed    : {0}" -f $speedString) "DarkGray"
        Write-Log "  [INFO]   No cable connected or device powered off." "DarkGray"
        Write-Log ""
        $portResults += [PSCustomObject]@{
            Name = $name; Speed = 0; Result = "NO LINK"; Action = "No cable or device connected"; Blinking = $false
        }

    } else {
        Write-Log ("  Speed    : {0}" -f $speedString) "Yellow"
        Write-Log ""
        $portResults += [PSCustomObject]@{
            Name = $name; Speed = $speedMbps; Result = "UNKNOWN"; Action = "Unexpected speed - investigate"; Blinking = $blinking
        }
    }
}

# ── Intel SmartSpeed Event Log Scan ──────────────────────────────────────────
Write-Log "-- Intel SmartSpeed Event Log Scan (last $EventLogHours hours) ---" "Cyan"
Write-Log ""

# Filter out events belonging to OCR/100 Mbps-only adapters — those ports are
# expected to run at 100 Mbps and their events are not evidence of cable faults.
$chuEvents = $events | Where-Object {
    $adName = Get-EventAdapterName -WinEvt $_ -KnownDescriptions $knownAdapterDescs
    -not $ocrAdapters.ContainsKey($adName)
}

$smartSpeedMessages = @()

if ($chuEvents.Count -gt 0) {
    $downgradeCount = ($chuEvents | Where-Object { $_.Id -eq 40 }).Count
    $warningCount   = ($chuEvents | Where-Object { $_.Id -eq 27 }).Count
    Write-Log ("  [WARN] Found {0} SmartSpeed downgrade(s) and {1} link warning(s) on CHU ports in the last {2} hours:" -f $downgradeCount, $warningCount, $EventLogHours) "Red"
    Write-Log ""
    foreach ($evt in $chuEvents | Sort-Object @{Expression='TimeCreated'; Descending=$true}, @{Expression='RecordId'; Descending=$true} | Select-Object -First 20) {
        $adapterName = Get-EventAdapterName -WinEvt $evt -KnownDescriptions $knownAdapterDescs
        if (-not $adapterName) { $adapterName = "Unknown adapter" }

        $msg = switch ($evt.Id) {
            40 { "$adapterName`: Intel SmartSpeed has downgraded the link speed from the maximum advertised." }
            33 { "$adapterName`: Network link has been established at 100 Mbps (confirmed post-downgrade speed)." }
            27 { "$adapterName`: Intel NIC link warning (check cable and termination)." }
            default { "$adapterName`: Intel NIC event (ID $($evt.Id))." }
        }
        $evtLabel = switch ($evt.Id) {
            40 { "SmartSpeed Downgrade" }
            33 { "Link Established at 100 Mbps" }
            27 { "Link Warning" }
            default { "NIC Event" }
        }

        Write-Log ("  Time    : {0}" -f $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")) "Yellow"
        Write-Log ("  Adapter : {0}" -f $adapterName) "Yellow"
        Write-Log ("  Event   : ID {0} - {1}" -f $evt.Id, $evtLabel) "Yellow"
        Write-Log ("  Message : {0}" -f $msg) "Yellow"
        Write-Log ""
        $smartSpeedMessages += $evt
    }
    if ($downgradeCount -gt 0) {
        Write-Log "  -> These events confirm the NIC detected a physical layer limitation" "White"
        Write-Log "     and downshifted from gigabit. Likely cause: faulty/degraded cable" "White"
        Write-Log "     or improper termination. This is irrefutable Layer 1 evidence." "White"
    } else {
        Write-Log "  -> Link warnings detected but no SmartSpeed downgrades confirmed." "White"
        Write-Log "     Monitor for recurrence." "White"
    }
} else {
    Write-Log "  [PASS] No SmartSpeed downgrade events found on CHU ports in the last $EventLogHours hours." "Green"
    if ($ocrAdapters.Count -gt 0) {
        Write-Log ("  [INFO] OCR adapter event(s) excluded from above: {0}" -f ($ocrAdapters.Keys -join ', ')) "DarkGray"
    }
}

Write-Log ""

# ── Connected Device Speed Check ─────────────────────────────────────────────
Write-Log "-- Connected Device Gigabit Support Check -----------------------" "Cyan"
Write-Log ""
Write-Log "  Checking ARP/neighbor table for connected device information..." "White"
Write-Log ""

foreach ($nic in $nicPorts) {
    $ifIndex = (Get-NetAdapter -Name $nic.Name).ifIndex
    $neighbors = Get-NetNeighbor -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue |
                 Where-Object {
                     $_.State -ne "Unreachable" -and
                     # Exclude multicast/broadcast: first MAC octet with LSB set = multicast
                     ([Convert]::ToInt32(($_.LinkLayerAddress -split '-')[0], 16) -band 1) -eq 0
                 }

    if ($neighbors -and $neighbors.Count -gt 0) {
        Write-Log ("  {0} - Connected device(s) detected:" -f $nic.Name) "White"
        foreach ($n in $neighbors) {
            Write-Log ("    IP  : {0}" -f $n.IPAddress) "White"
            Write-Log ("    MAC : {0}" -f $n.LinkLayerAddress) "White"

            $oui = $n.LinkLayerAddress.Replace("-","").Substring(0,6).ToUpper()
            Write-Log ("    OUI : {0}  (https://www.wireshark.org/tools/oui-lookup.html)" -f $oui) "DarkGray"
        }
    } else {
        Write-Log ("  {0} - No connected devices detected in ARP table." -f $nic.Name) "DarkGray"
    }
    Write-Log ""
}

Write-Log "  NOTE: If the connected camera only supports 100 Mbps (Fast Ethernet)," "DarkGray"
Write-Log "        the link will always negotiate at 100 Mbps regardless of cable" "DarkGray"
Write-Log "        quality. Check the camera specifications." "DarkGray"
Write-Log ""

# ── Camera Connectivity Test (Ping + RTSP) ────────────────────────────────────
Write-Log "-- Camera Connectivity Test (Ping + RTSP Port $RtspPort) ---------------" "Cyan"
Write-Log ""

foreach ($cam in $CameraIPs) {
    Write-Log ("  {0,-18} {1}" -f $cam.IP, $cam.Label) "White"

    # Layer 3 - ICMP ping
    $pingOk = Test-Connection -ComputerName $cam.IP -Count 2 -Quiet -ErrorAction SilentlyContinue
    if ($pingOk) {
        Write-Log "  Ping     : Responding" "Green"
    } else {
        Write-Log "  Ping     : No response  (camera offline, no link, or wrong IP)" "DarkGray"
    }

    # Layer 7 - RTSP TCP port reachability
    $rtspOk = $false
    if ($pingOk) {
        $rtspOk = Test-TcpPort -IP $cam.IP -Port $RtspPort
        if ($rtspOk) {
            Write-Log "  RTSP 554 : Port open  (camera stream reachable)" "Green"
        } else {
            Write-Log "  RTSP 554 : Port closed or no response  (camera may be booting or faulted)" "Red"
        }
    } else {
        $noRespNote = if ($cam.Optional) { " - expected if no OCR camera installed on this unit" } else { "" }
        Write-Log ("  RTSP 554 : Skipped (no ping$noRespNote)") "DarkGray"
    }

    $cameraConnResults += [PSCustomObject]@{
        IP       = $cam.IP
        Label    = $cam.Label
        Ping     = $pingOk
        Rtsp     = $rtspOk
        Optional = $cam.Optional
    }
    Write-Log ""
}

# ── Pixellot Application Log Analysis ────────────────────────────────────────
Write-Log "-- Pixellot Application Log Analysis --------------------------------" "Cyan"
Write-Log ""

foreach ($logPath in $PixellotLogPaths) {
    if (Test-Path $logPath) {
        $found = Get-ChildItem -Path $logPath -Filter "CamerasTester_*.log" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($found) { $latestLog = $found; break }
    }
}

if (-not $latestLog) {
    Write-Log "  [INFO] No CamerasTester log files found. Skipping application log analysis." "DarkGray"
    Write-Log ("  Searched: {0}" -f ($PixellotLogPaths -join ', ')) "DarkGray"
    Write-Log ""
} else {
    Write-Log ("  Log file  : {0}" -f $latestLog.FullName) "White"
    Write-Log ("  Log size  : {0} KB  |  Modified: {1}" -f [math]::Round($latestLog.Length / 1KB, 1), $latestLog.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")) "White"
    Write-Log ""

    $logContent = Get-Content -Path $latestLog.FullName -ErrorAction SilentlyContinue

    if (-not $logContent) {
        Write-Log "  [WARN] Could not read log file contents." "Yellow"
        Write-Log ""
    } else {
        $appFailCounts   = @{}   # IP -> total 'no response' failure count
        $appSuccessIPs   = @{}   # IP -> $true if connected at least once
        $appCameraModels = @{}   # IP -> model name string
        $appExitCodes    = @{}   # IP -> last exit code seen
        $appSessionCount = 0
        $appLastIP       = $null

        foreach ($line in $logContent) {
            if ($line -match 'START NEW LOG SESSION') { $appSessionCount++ }

            # Track active camera context from bracket notation: [rtsp://IP/...]
            if ($line -match '\[rtsp://([\d.]+)/') { $appLastIP = $Matches[1] }

            # Connection failure - no response from camera
            if ($line -match "Couldn't get response from camera\s+rtsp://([\d.]+)") {
                $appIp = $Matches[1]
                $appFailCounts[$appIp] = ($appFailCounts[$appIp] -as [int]) + 1
                $appLastIP = $appIp
            }

            # Successful camera parameter exchange
            if ($line -match 'Done Setting camera parameters' -and $appLastIP) {
                $appSuccessIPs[$appLastIP] = $true
            }

            # Camera model identification
            if ($line -match 'Found modelName:\s*(\S+)' -and $appLastIP) {
                $appCameraModels[$appLastIP] = $Matches[1].Trim()
            }

            # Process exit code - prefer first non-zero code; never let clean app shutdown (0) overwrite a failure code
            if ($line -match 'Process exiting with result:\s*(\d+)' -and $appLastIP) {
                $code = [int]$Matches[1]
                if ($code -ne 0 -or -not $appExitCodes.ContainsKey($appLastIP)) {
                    $appExitCodes[$appLastIP] = $code
                }
            }
        }

        Write-Log ("  Sessions in log : {0}" -f $appSessionCount) "White"
        Write-Log ""

        $allLogIPs = (@($appFailCounts.Keys) + @($appSuccessIPs.Keys) + @($appCameraModels.Keys)) |
                     Sort-Object -Unique

        if ($allLogIPs.Count -eq 0) {
            Write-Log "  [INFO] No camera connection activity found in log file." "DarkGray"
        } else {
            foreach ($appIp in $allLogIPs) {
                $appFails    = $appFailCounts[$appIp] -as [int]
                $appModel    = if ($appCameraModels[$appIp]) { $appCameraModels[$appIp] } else { "Unknown" }
                $appExitCode = $appExitCodes[$appIp]

                Write-Log ("  Camera IP : {0}" -f $appIp) "White"
                Write-Log ("  Model     : {0}" -f $appModel) "White"

                if ($appFails -gt 0) {
                    # Suppress failures for optional cameras that had no network presence —
                    # app errors are expected when the camera is simply not installed on this unit.
                    $camDef     = $CameraIPs | Where-Object { $_.IP -eq $appIp } | Select-Object -First 1
                    $connResult = $cameraConnResults | Where-Object { $_.IP -eq $appIp } | Select-Object -First 1
                    if ($camDef -and $camDef.Optional -and $connResult -and (-not $connResult.Ping)) {
                        Write-Log "  Status    : Expected - optional camera (OCR) not installed on this unit." "DarkGray"
                        Write-Log ""
                        continue
                    }

                    Write-Log ("  Errors    : {0} 'Couldn't get response' failure(s) across {1} session(s)" -f $appFails, $appSessionCount) "Red"
                    if ($null -ne $appExitCode) {
                        $exitMsg = switch ($appExitCode) {
                            11      { "Camera not found / no response before timeout" }
                            12      { "Camera first connection problem" }
                            default { "Exit code $appExitCode" }
                        }
                        Write-Log ("  Exit Code : {0}  ({1})" -f $appExitCode, $exitMsg) "Red"
                    }

                    # Correlate camera IP to NIC port
                    $matchedNic      = $null
                    $usedSubnetMatch = $false

                    # Method 1: ARP/neighbor table lookup by IP
                    $arpEntry = Get-NetNeighbor -IPAddress $appIp -ErrorAction SilentlyContinue |
                                Where-Object { $_.State -ne "Unreachable" } | Select-Object -First 1
                    if ($arpEntry) {
                        $matchedNic = Get-NetAdapter -InterfaceIndex $arpEntry.InterfaceIndex -ErrorAction SilentlyContinue
                    }

                    # Method 2: /24 subnet match against camera NIC port IP addresses
                    if (-not $matchedNic) {
                        $targetSubnet    = ($appIp -split '\.')[0..2] -join '.'
                        $usedSubnetMatch = $true
                        foreach ($nic in $nicPorts) {
                            $nicIfIdx  = (Get-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue).ifIndex
                            $nicAddrs  = Get-NetIPAddress -InterfaceIndex $nicIfIdx -AddressFamily IPv4 -ErrorAction SilentlyContinue
                            foreach ($addr in $nicAddrs) {
                                if ($addr.IPAddress -and (($addr.IPAddress -split '\.')[0..2] -join '.') -eq $targetSubnet) {
                                    $matchedNic = Get-NetAdapter -Name $nic.Name -ErrorAction SilentlyContinue
                                    break
                                }
                            }
                            if ($matchedNic) { break }
                        }
                    }

                    if ($matchedNic) {
                        $nicPortLabel = if ($usedSubnetMatch) { "  NIC Port  : {0}  ({1})  [subnet match - ARP unavailable]" } else { "  NIC Port  : {0}  ({1})" }
                        Write-Log ($nicPortLabel -f $matchedNic.Name, $matchedNic.InterfaceDescription) "Yellow"

                        if ($usedSubnetMatch) {
                            # ARP was empty (common after adapter reset during this run). Check whether a FAIL
                            # port is also on the same subnet - if so, it is more likely the actual camera port.
                            $degradedOnSubnet = $null
                            foreach ($fr in ($portResults | Where-Object { $_.Result -eq "FAIL" -and $_.Name -ne $matchedNic.Name })) {
                                $frIfIdx = (Get-NetAdapter -Name $fr.Name -ErrorAction SilentlyContinue).ifIndex
                                $frAddrs = Get-NetIPAddress -InterfaceIndex $frIfIdx -AddressFamily IPv4 -ErrorAction SilentlyContinue
                                if ($frAddrs | Where-Object { $_.IPAddress -and (($_.IPAddress -split '\.')[0..2] -join '.') -eq $targetSubnet }) {
                                    $degradedOnSubnet = $fr; break
                                }
                            }
                            if ($degradedOnSubnet) {
                                Write-Log "  [CAUTION] ARP table empty - may have been cleared after adapter reset this run." "Yellow"
                                Write-Log ("            Degraded port {0} is also on subnet {1}.x and is the more likely camera port." -f $degradedOnSubnet.Name, $targetSubnet) "Yellow"
                                Write-Log "            Verify physical cable mapping before concluding." "Yellow"
                            } else {
                                Write-Log "  [NOTE]    ARP table unavailable - port identified by /24 subnet match only." "DarkGray"
                            }
                        }

                        $portResult = $portResults | Where-Object { $_.Name -eq $matchedNic.Name } | Select-Object -First 1
                        if ($portResult) {
                            if ($portResult.Result -eq "FAIL") {
                                Write-Log "  [CONFIRM] NIC port was DEGRADED - application failures corroborate physical layer fault." "Red"
                                $cameraAppIssues += ("{0} ({1}) on {2}: app failures ({3}x) + NIC degraded = CONFIRMED physical fault" -f $appIp, $appModel, $matchedNic.Name, $appFails)
                            } elseif ($portResult.Result -like "PASS*") {
                                Write-Log "  [NOTE]    NIC port link speed is OK (1 Gbps) - fault is not in the physical layer." "Yellow"
                                Write-Log "            Check camera power supply, configuration, or internal hardware." "Yellow"
                                $cameraAppIssues += ("{0} ({1}) on {2}: app failures ({3}x) but NIC OK - check camera hardware/config" -f $appIp, $appModel, $matchedNic.Name, $appFails)
                            } else {
                                $cameraAppIssues += ("{0} ({1}): {2} app failure(s) detected" -f $appIp, $appModel, $appFails)
                            }
                        } else {
                            $cameraAppIssues += ("{0} ({1}): {2} app failure(s) detected" -f $appIp, $appModel, $appFails)
                        }
                    } else {
                        Write-Log "  NIC Port  : Could not correlate to a camera NIC port via ARP or subnet match." "DarkGray"
                        $cameraAppIssues += ("{0} ({1}): {2} app failure(s) - NIC port not identified" -f $appIp, $appModel, $appFails)
                    }
                } else {
                    Write-Log "  Status    : Connected successfully - no application-level failures." "Green"
                }
                Write-Log ""
            }
        }
    }
}

Add-Content -Path $OutputFile -Value "Full results saved: $OutputFile"

# ── Clear screen and show summary ─────────────────────────────────────────────
Clear-Host

$passCount         = ($portResults | Where-Object { $_.Result -like "PASS*" }).Count
$failCount         = ($portResults | Where-Object { $_.Result -eq "FAIL" }).Count
$noLinkCount       = ($portResults | Where-Object { $_.Result -eq "NO LINK" }).Count
$unknownCount      = ($portResults | Where-Object { $_.Result -eq "UNKNOWN" }).Count
$chuDowngradeCount = ($smartSpeedMessages | Where-Object { $_.Id -eq 40 }).Count
$rtspFaultCount    = ($cameraConnResults | Where-Object { $_.Ping -and -not $_.Rtsp }).Count
$allClear          = ($failCount -eq 0) -and ($unknownCount -eq 0) -and ($chuDowngradeCount -eq 0) -and ($rtspFaultCount -eq 0)

Write-Host "================================================================" -ForegroundColor White
Write-Host " Pixellot VPU - Camera Link Speed Diagnostic - COMPLETE" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host " Computer : $($env:COMPUTERNAME)" -ForegroundColor White
Write-Host " Date/Time: $timestamp" -ForegroundColor White
Write-Host " VPU Model: $VpuModelDisplay" -ForegroundColor White
Write-Host " NIC      : Intel(R) 82574L / I210 (camera POE ports)" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host ""

# Per-port results
Write-Host " PORT RESULTS" -ForegroundColor Cyan
Write-Host ("-" * 64) -ForegroundColor DarkGray
Write-Host ""

foreach ($r in $portResults) {
    switch -Wildcard ($r.Result) {
        "PASS*" {
            $color = "Green"
            $speedLabel = if ($r.Speed -eq 1000) { "1 Gbps" } else { "$($r.Speed) Mbps" }
            Write-Host ("  [PASS] {0,-20} {1}" -f $r.Name, $speedLabel) -ForegroundColor $color
            if ($r.Action -ne "None") {
                Write-Host ("         -> {0}" -f $r.Action) -ForegroundColor Yellow
            }
        }
        "FAIL" {
            $blinkNote = if ($r.Blinking) { " (intermittent - link was blinking)" } else { "" }
            Write-Host ("  [FAIL] {0,-20} $($r.Speed) Mbps - DEGRADED$blinkNote" -f $r.Name) -ForegroundColor Red
            Write-Host ("         -> {0}" -f $r.Action) -ForegroundColor Red
        }
        "NO LINK" {
            Write-Host ("  [----] {0,-20} No link / not connected" -f $r.Name) -ForegroundColor DarkGray
        }
        default {
            Write-Host ("  [UNK?] {0,-20} $($r.Speed) Mbps - unexpected" -f $r.Name) -ForegroundColor Yellow
        }
    }
}

Write-Host ""

# Camera connectivity summary
Write-Host " CAMERA CONNECTIVITY" -ForegroundColor Cyan
Write-Host ("-" * 64) -ForegroundColor DarkGray
foreach ($c in $cameraConnResults) {
    if ($c.Ping -and $c.Rtsp) {
        Write-Host ("  [OK  ] {0,-18} {1}  —  Ping OK, RTSP open" -f $c.IP, $c.Label) -ForegroundColor Green
    } elseif ($c.Ping -and -not $c.Rtsp) {
        Write-Host ("  [WARN] {0,-18} {1}  —  Ping OK, RTSP closed" -f $c.IP, $c.Label) -ForegroundColor Yellow
    } elseif ($c.Optional) {
        Write-Host ("  [----] {0,-18} {1}  —  No device  (normal — OCR camera not installed on this unit)" -f $c.IP, $c.Label) -ForegroundColor DarkGray
    } else {
        Write-Host ("  [----] {0,-18} {1}  —  No response" -f $c.IP, $c.Label) -ForegroundColor DarkGray
    }
}
Write-Host ""

# SmartSpeed summary
Write-Host " INTEL SMARTSPEED EVENT LOG" -ForegroundColor Cyan
Write-Host ("-" * 64) -ForegroundColor DarkGray
if ($smartSpeedMessages.Count -gt 0) {
    Write-Host ("  [WARN] {0} downgrade event(s) found in last {1} hours." -f $smartSpeedMessages.Count, $EventLogHours) -ForegroundColor Red
    Write-Host "         NIC confirmed physical layer limitation on at least one port." -ForegroundColor Red
} else {
    Write-Host "  [PASS] No SmartSpeed downgrade events detected." -ForegroundColor Green
}
Write-Host ""

# Pixellot application log summary
Write-Host " PIXELLOT APPLICATION LOG" -ForegroundColor Cyan
Write-Host ("-" * 64) -ForegroundColor DarkGray
if ($cameraAppIssues.Count -gt 0) {
    foreach ($issue in $cameraAppIssues) {
        Write-Host ("  [WARN] {0}" -f $issue) -ForegroundColor Red
    }
} elseif ($latestLog) {
    Write-Host "  [PASS] No camera connection failures found in application log." -ForegroundColor Green
} else {
    Write-Host "  [INFO] No Pixellot application log found - skipped." -ForegroundColor DarkGray
}
Write-Host ""

# Verdict
if ($allClear) {
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  ALL PORTS AT 1 GBPS - Camera connections appear healthy." -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
} else {
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "  ISSUES DETECTED" -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    if ($failCount -gt 0) {
        Write-Host "  DEGRADED PORT(S) FOUND:" -ForegroundColor Red
        Write-Host "  Forcing to 1 Gbps failed - physical layer issue confirmed." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Recommended steps:" -ForegroundColor White
        Write-Host "   1. Replace the Ethernet cable on the affected port(s)" -ForegroundColor White
        Write-Host "   2. Check cable termination - gigabit requires all 4 pairs" -ForegroundColor White
        Write-Host "   3. Inspect RJ45 connector pins on cable and camera port for damage/corrosion" -ForegroundColor White
        Write-Host "   4. Try a different port on the camera" -ForegroundColor White
        Write-Host "   5. Verify the camera supports gigabit (1000BASE-T)" -ForegroundColor White
        Write-Host "      Look up the MAC OUI in the full results file to identify" -ForegroundColor White
        Write-Host "      the camera manufacturer." -ForegroundColor White
    }
    if ($unknownCount -gt 0) {
        Write-Host "  UNEXPECTED SPEED DETECTED ON $unknownCount PORT(S):" -ForegroundColor Yellow
        Write-Host "  Could not determine a standard link speed (not 100/1000 Mbps)." -ForegroundColor Yellow
        Write-Host "  Check the full results file for the raw speed value." -ForegroundColor Yellow
        Write-Host "  The connected device may only support 10 Mbps or an unusual rate." -ForegroundColor Yellow
    }
    if ($rtspFaultCount -gt 0) {
        Write-Host ""
        Write-Host "  RTSP PORT CLOSED ON $rtspFaultCount CAMERA(S):" -ForegroundColor Yellow
        Write-Host "  Camera responds to ping but is not accepting RTSP connections." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Recommended steps:" -ForegroundColor White
        Write-Host "   1. Check VPU Manager camera status panel for error codes" -ForegroundColor White
        Write-Host "   2. Try a PoE reset via VPU Manager (power-cycles the camera)" -ForegroundColor White
        Write-Host "   3. If RTSP remains closed after reset, the camera may need replacement" -ForegroundColor White
    }
}

Write-Host ""
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Full detailed results saved to:" -ForegroundColor White
Write-Host " $OutputFile" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " Press any key to close..." -ForegroundColor DarkGray
[void][System.Console]::ReadKey($true)