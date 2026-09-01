#Requires -Version 5.1
<#
.SYNOPSIS
    Runs a short network capture using pktmon and returns a summary of findings.
.DESCRIPTION
    Uses Windows built-in pktmon to capture packet headers for a specified duration,
    then analyzes the capture for retransmissions, resets, and connection issues.
    No third-party drivers or installs required. Outputs JSON to stdout.
.NOTES
    Requires Windows 10 1903+ and elevated privileges.
    Only captures TCP headers (128 bytes) -- no payload inspection.
#>
[CmdletBinding()]
param(
    [int]$DurationSec = 30,
    [int]$MaxPackets = 5000
)

$ErrorActionPreference = 'Stop'

# Clamp duration: 10-60 seconds
$DurationSec = [math]::Max(10, [math]::Min($DurationSec, 60))

try {
    # -- Check pktmon availability --------------------------------
    $pktmonPath = Get-Command pktmon -ErrorAction SilentlyContinue
    if (-not $pktmonPath) {
        [ordered]@{
            error = $true
            message = 'pktmon not available. Requires Windows 10 1903 or later.'
            script = 'Start-NetworkCapture.ps1'
        } | ConvertTo-Json -Compress
        return
    }

    # -- Check for admin elevation (pktmon requires it) -----------
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        [ordered]@{
            error = $true
            message = 'Packet capture requires administrator privileges. Run Pulse as administrator.'
            script = 'Start-NetworkCapture.ps1'
        } | ConvertTo-Json -Compress
        return
    }

    # -- Clean up any prior state ---------------------------------
    try { & pktmon stop 2>&1 | Out-Null } catch { }
    try { & pktmon filter remove 2>&1 | Out-Null } catch { }

    # -- Add filters: TCP on key ports ----------------------------
    try {
        & pktmon filter add PulseTCP -t TCP -p 443 2>&1 | Out-Null
        & pktmon filter add PulseRTMP -t TCP -p 1935 2>&1 | Out-Null
        & pktmon filter add PulseHTTP -t TCP -p 80 2>&1 | Out-Null
        & pktmon filter add PulseZixi -t UDP -p 2088 2>&1 | Out-Null
    }
    catch {
        [ordered]@{
            error = $true
            message = "Failed to add pktmon filters: $($_.Exception.Message)"
            script = 'Start-NetworkCapture.ps1'
        } | ConvertTo-Json -Compress
        return
    }

    # -- Start capture (ETL file, headers only) -------------------
    $etlPath = Join-Path $env:TEMP "pulse_capture.etl"
    if (Test-Path $etlPath) { Remove-Item $etlPath -Force }

    try {
        & pktmon start --capture --pkt-size 128 -f $etlPath -c $MaxPackets 2>&1 | Out-Null
    }
    catch {
        try { & pktmon filter remove 2>&1 | Out-Null } catch { }
        [ordered]@{
            error = $true
            message = "Failed to start pktmon capture: $($_.Exception.Message)"
            script = 'Start-NetworkCapture.ps1'
        } | ConvertTo-Json -Compress
        return
    }

    # -- Wait for capture duration --------------------------------
    Start-Sleep -Seconds $DurationSec

    # -- Stop capture ---------------------------------------------
    $stopOutput = & pktmon stop 2>&1 | Out-String

    # -- Get counters before cleanup ------------------------------
    $counterOutput = & pktmon counters 2>&1 | Out-String

    # -- Remove filters -------------------------------------------
    & pktmon filter remove 2>&1 | Out-Null

    # -- Parse pktmon counters for drop/packet stats --------------
    $totalPackets = 0
    $droppedPackets = 0
    $components = @()

    # Parse counter output lines -- format: "  Name   Packets  Bytes  Drops"
    $counterLines = $counterOutput -split "`n"
    foreach ($line in $counterLines) {
        if ($line -match '^\s*(.+?)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $name = $Matches[1].Trim()
            $pkts = [int]$Matches[2]
            $drops = [int]$Matches[4]
            if ($pkts -gt 0 -or $drops -gt 0) {
                $totalPackets += $pkts
                $droppedPackets += $drops
                $components += [ordered]@{
                    name     = $name
                    packets  = $pkts
                    drops    = $drops
                }
            }
        }
    }

    # -- Convert ETL to text for deeper analysis ------------------
    $txtPath = Join-Path $env:TEMP "pulse_capture.txt"
    if (Test-Path $txtPath) { Remove-Item $txtPath -Force }

    $tcpResets = 0
    $tcpSyns = 0
    $tcpFins = 0
    $tcpRetransmits = 0
    $connectionsByRemote = @{}

    try {
        # pktmon etl2txt converts ETL to a readable text format
        & pktmon etl2txt $etlPath -o $txtPath 2>&1 | Out-Null

        if (Test-Path $txtPath) {
            $lines = Get-Content $txtPath -ErrorAction Stop
            foreach ($pktLine in $lines) {
                # Count TCP flag patterns
                if ($pktLine -match 'TCP.*\bRST\b') { $tcpResets++ }
                if ($pktLine -match 'TCP.*\bSYN\b' -and $pktLine -notmatch 'SYN.ACK') { $tcpSyns++ }
                if ($pktLine -match 'TCP.*\bFIN\b') { $tcpFins++ }
                # Retransmission detection: duplicate seq numbers or retransmit flags
                if ($pktLine -match 'retransmit|retrans') { $tcpRetransmits++ }

                # Track unique remote endpoints
                if ($pktLine -match 'dst[:\s]+(\d+\.\d+\.\d+\.\d+):(\d+)') {
                    $remoteKey = "$($Matches[1]):$($Matches[2])"
                    if (-not $connectionsByRemote.ContainsKey($remoteKey)) {
                        $connectionsByRemote[$remoteKey] = 0
                    }
                    $connectionsByRemote[$remoteKey]++
                }
            }
        }
    }
    catch {
        # etl2txt may not be available on older builds -- counters still work
    }

    # -- Build top talkers list -----------------------------------
    $topTalkers = @()
    $sorted = $connectionsByRemote.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 10
    foreach ($kv in $sorted) {
        $parts = $kv.Key -split ':'
        $hostname = $null
        try {
            $ar = [System.Net.Dns]::BeginGetHostEntry($parts[0], $null, $null)
            if ($ar.AsyncWaitHandle.WaitOne(300)) {
                $entry = [System.Net.Dns]::EndGetHostEntry($ar)
                if ($entry.HostName -ne $parts[0]) { $hostname = $entry.HostName }
            }
        }
        catch { }

        $topTalkers += [ordered]@{
            remoteAddr = $parts[0]
            remotePort = [int]$parts[1]
            remoteHost = $hostname
            packets    = $kv.Value
        }
    }

    # -- Classify findings ----------------------------------------
    $findings = @()

    if ($tcpRetransmits -gt 10) {
        $findings += [ordered]@{
            severity = 'warning'
            title    = "$tcpRetransmits TCP retransmission(s) detected"
            body     = "Retransmissions mean packet loss on the network path. Check for congestion, firewall interference, or a bad cable."
        }
    }
    elseif ($tcpRetransmits -gt 0) {
        $findings += [ordered]@{
            severity = 'info'
            title    = "$tcpRetransmits TCP retransmission(s) detected"
            body     = "Minor retransmissions. These only matter if they are sustained."
        }
    }

    if ($tcpResets -gt 5) {
        $findings += [ordered]@{
            severity = 'warning'
            title    = "$tcpResets TCP reset(s) received"
            body     = "Connections are being forcefully terminated. Common causes: firewall RST injection, server rejecting connections, or idle connection timeouts."
        }
    }

    if ($droppedPackets -gt 0) {
        $findings += [ordered]@{
            severity = 'critical'
            title    = "$droppedPackets packet(s) dropped by the network stack"
            body     = "Packets were dropped before reaching the application. Look at NIC buffer overflow, the network driver, or a security filter blocking traffic."
        }
    }

    if ($findings.Count -eq 0 -and $totalPackets -gt 0) {
        $findings += [ordered]@{
            severity = 'pass'
            title    = 'No issues detected'
            body     = "Captured $totalPackets packets over ${DurationSec}s with no retransmissions, resets, or drops."
        }
    }

    # -- Cleanup temp files ---------------------------------------
    try {
        if (Test-Path $etlPath) { Remove-Item $etlPath -Force }
        if (Test-Path $txtPath) { Remove-Item $txtPath -Force }
    }
    catch { }

    [ordered]@{
        durationSec     = $DurationSec
        totalPackets    = $totalPackets
        droppedPackets  = $droppedPackets
        tcpRetransmits  = $tcpRetransmits
        tcpResets        = $tcpResets
        tcpSyns         = $tcpSyns
        tcpFins         = $tcpFins
        components      = @($components)
        topTalkers      = @($topTalkers)
        findings        = @($findings)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    # Cleanup on error
    try { & pktmon stop 2>&1 | Out-Null } catch { }
    try { & pktmon filter remove 2>&1 | Out-Null } catch { }

    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Start-NetworkCapture.ps1'
    } | ConvertTo-Json -Compress
}
