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
#      irm 'https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/TestCameraConnectivity.ps1' | iex
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
$ScriptUrl = "https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/TestCameraConnectivity.ps1"

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

$ScriptVersion     = "1.9"
$RunId             = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputDir         = if ($PSScriptRoot) { $PSScriptRoot } else { [Environment]::GetFolderPath('Desktop') }
$OutputFile        = Join-Path $OutputDir "CameraLink_Results_$RunId.txt"
$NicDriverPatterns = @(                   # Driver descriptions to match camera NIC ports
    "Intel(R) 82574L*"                    #   4-port POE NIC (most VPUs)
    "Intel(R) I210*"                      #   I210 NIC (newer VPU models)
)
$RenegotiateWaitSec = 30                  # Seconds to wait after forcing speed change
$EventLogHours     = 48                   # How many hours back to scan the event log

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

$header = @"
================================================================
 Pixellot VPU - Camera Link Speed Diagnostic  v$ScriptVersion
================================================================
 Computer : $($env:COMPUTERNAME)
 User     : $($env:USERNAME)
 Date/Time: $timestamp
 Run ID   : $RunId
 NIC      : Intel(R) 82574L Gigabit Network Connection (4-port POE)
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
    $speedString = Get-SpeedDisplayString -Mbps $speedMbps

    Write-Log ("  Adapter  : {0}" -f $name) "White"
    Write-Log ("  Driver   : {0}" -f $nic.InterfaceDescription) "White"
    Write-Log ("  Status   : {0}" -f $status) "White"
    Write-Log ("  MAC      : {0}" -f $nic.MacAddress) "White"

    if ($speedMbps -eq 1000) {
        Write-Log ("  Speed    : {0}" -f $speedString) "Green"
        Write-Log ""
        $portResults += [PSCustomObject]@{
            Name = $name; Speed = $speedMbps; Result = "PASS"; Action = "None"
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
                Name = $name; Speed = $speedMbps; Result = "PASS (OCR)"; Action = "OCR scoreboard camera - 100 Mbps is expected"
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
                Name = $name; Speed = $speedMbps; Result = "FAIL"; Action = "Could not apply SpeedDuplex setting - check Device Manager Advanced tab"
            }
            Write-Log ""
            continue
        }

        Write-Log ("  [INFO]   Speed set to 1 Gbps Full Duplex. Waiting {0} seconds for re-negotiation..." -f $RenegotiateWaitSec) "Yellow"
        Start-Sleep -Seconds $RenegotiateWaitSec

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
                Action = "Forced to 1 Gbps - monitor port; connected device may not support auto-negotiation"
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
                    Start-Sleep -Seconds 2
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
                Action = "Physical layer issue - check cable, termination, RJ45 pins, and camera port"
            }
        }
        Write-Log ""

    } elseif ($speedMbps -eq 0) {
        Write-Log ("  Speed    : {0}" -f $speedString) "DarkGray"
        Write-Log "  [INFO]   No cable connected or device powered off." "DarkGray"
        Write-Log ""
        $portResults += [PSCustomObject]@{
            Name = $name; Speed = 0; Result = "NO LINK"; Action = "No cable or device connected"
        }

    } else {
        Write-Log ("  Speed    : {0}" -f $speedString) "Yellow"
        Write-Log ""
        $portResults += [PSCustomObject]@{
            Name = $name; Speed = $speedMbps; Result = "UNKNOWN"; Action = "Unexpected speed - investigate"
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

Add-Content -Path $OutputFile -Value "Full results saved: $OutputFile"

# ── Clear screen and show summary ─────────────────────────────────────────────
Clear-Host

$passCount         = ($portResults | Where-Object { $_.Result -like "PASS*" }).Count
$failCount         = ($portResults | Where-Object { $_.Result -eq "FAIL" }).Count
$noLinkCount       = ($portResults | Where-Object { $_.Result -eq "NO LINK" }).Count
$unknownCount      = ($portResults | Where-Object { $_.Result -eq "UNKNOWN" }).Count
$chuDowngradeCount = ($smartSpeedMessages | Where-Object { $_.Id -eq 40 }).Count
$allClear          = ($failCount -eq 0) -and ($unknownCount -eq 0) -and ($chuDowngradeCount -eq 0)

Write-Host "================================================================" -ForegroundColor White
Write-Host " Pixellot VPU - Camera Link Speed Diagnostic - COMPLETE" -ForegroundColor White
Write-Host "================================================================" -ForegroundColor White
Write-Host " Computer : $($env:COMPUTERNAME)" -ForegroundColor White
Write-Host " Date/Time: $timestamp" -ForegroundColor White
Write-Host " NIC      : Intel(R) 82574L (4-port POE)" -ForegroundColor White
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
            Write-Host ("  [FAIL] {0,-20} $($r.Speed) Mbps - DEGRADED" -f $r.Name) -ForegroundColor Red
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
}

Write-Host ""
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host " Full detailed results saved to:" -ForegroundColor White
Write-Host " $OutputFile" -ForegroundColor Cyan
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Write-Host " Press any key to close..." -ForegroundColor DarkGray
[void][System.Console]::ReadKey($true)