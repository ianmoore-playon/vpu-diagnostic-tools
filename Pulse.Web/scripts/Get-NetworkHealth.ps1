#Requires -Version 5.1
<#
.SYNOPSIS
    Collects live TCP/IP health metrics for real-time network monitoring.
.DESCRIPTION
    Gathers TCP retransmission rate, active connections to known endpoints,
    connection failures/resets, and per-NIC queue depth. Designed to run in
    a tight poll loop (~3s) with minimal CPU cost. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # ── TCP performance counters ────────────────────────────────
    $tcpRetransSec  = $null
    $tcpFailures    = $null
    $tcpResets       = $null
    $tcpCurEstab    = $null
    $tcpSegsOutSec  = $null
    $tcpSegsInSec   = $null

    try {
        $counters = Get-Counter -Counter @(
            '\TCPv4\Segments Retransmitted/sec',
            '\TCPv4\Connection Failures',
            '\TCPv4\Connections Reset',
            '\TCPv4\Connections Established',
            '\TCPv4\Segments Sent/sec',
            '\TCPv4\Segments Received/sec'
        ) -ErrorAction Stop

        $samples = $counters.CounterSamples
        foreach ($s in $samples) {
            $path = $s.Path.ToLower()
            if ($path -match 'retransmitted')      { $tcpRetransSec = [math]::Round($s.CookedValue, 2) }
            elseif ($path -match 'connection failures') { $tcpFailures = [int]$s.CookedValue }
            elseif ($path -match 'connections reset')   { $tcpResets = [int]$s.CookedValue }
            elseif ($path -match 'connections established') { $tcpCurEstab = [int]$s.CookedValue }
            elseif ($path -match 'segments sent')   { $tcpSegsOutSec = [math]::Round($s.CookedValue, 0) }
            elseif ($path -match 'segments received') { $tcpSegsInSec = [math]::Round($s.CookedValue, 0) }
        }
    }
    catch {
        # First invocation can fail while counter infrastructure warms up
    }

    # ── Active TCP connections on service ports ───────────────
    # No reverse DNS here — too slow for a 3s poll loop. Raw IPs only.
    $activeConns = @()
    try {
        $allTcp = Get-NetTCPConnection -State Established, TimeWait, CloseWait, SynSent -ErrorAction SilentlyContinue
        foreach ($conn in $allTcp) {
            $remotePort = $conn.RemotePort
            # Only report connections on common service ports
            if ($remotePort -eq 443 -or $remotePort -eq 1935 -or
                $remotePort -eq 80 -or $remotePort -eq 2088 -or
                $remotePort -eq 1402) {
                $activeConns += [ordered]@{
                    localPort  = $conn.LocalPort
                    remoteAddr = $conn.RemoteAddress
                    remotePort = $remotePort
                    state      = $conn.State.ToString()
                    pid        = $conn.OwningProcess
                }
            }
        }
        # Cap at 50 to keep JSON small
        if ($activeConns.Count -gt 50) {
            $activeConns = $activeConns[0..49]
        }
    }
    catch { }

    # ── Per-NIC queue depth and packet rates ────────────────────
    $nicHealth = @()
    try {
        $nicCounters = Get-Counter -Counter @(
            '\Network Interface(*)\Output Queue Length',
            '\Network Interface(*)\Packets Received Errors',
            '\Network Interface(*)\Packets Outbound Errors',
            '\Network Interface(*)\Packets Received/sec',
            '\Network Interface(*)\Packets Sent/sec'
        ) -ErrorAction Stop

        # Group samples by instance (NIC name)
        $byNic = @{}
        foreach ($s in $nicCounters.CounterSamples) {
            $inst = $s.InstanceName
            if (-not $inst -or $inst -eq '_total') { continue }
            if (-not $byNic.ContainsKey($inst)) {
                $byNic[$inst] = @{}
            }
            $path = $s.Path.ToLower()
            if ($path -match 'output queue length')      { $byNic[$inst].queueLen = [int]$s.CookedValue }
            elseif ($path -match 'received errors')      { $byNic[$inst].rxErrors = [int]$s.CookedValue }
            elseif ($path -match 'outbound errors')      { $byNic[$inst].txErrors = [int]$s.CookedValue }
            elseif ($path -match 'packets received/sec') { $byNic[$inst].rxPktSec = [math]::Round($s.CookedValue, 0) }
            elseif ($path -match 'packets sent/sec')     { $byNic[$inst].txPktSec = [math]::Round($s.CookedValue, 0) }
        }

        foreach ($kv in $byNic.GetEnumerator()) {
            # Skip loopback and virtual adapters
            if ($kv.Key -match 'loopback|isatap|teredo|6to4') { continue }
            $nicHealth += [ordered]@{
                name       = $kv.Key
                queueLen   = $kv.Value.queueLen
                rxErrors   = $kv.Value.rxErrors
                txErrors   = $kv.Value.txErrors
                rxPktSec   = $kv.Value.rxPktSec
                txPktSec   = $kv.Value.txPktSec
            }
        }
    }
    catch { }

    [ordered]@{
        tcp = [ordered]@{
            retransmitsSec  = $tcpRetransSec
            connFailures    = $tcpFailures
            connResets       = $tcpResets
            established     = $tcpCurEstab
            segsOutSec      = $tcpSegsOutSec
            segsInSec       = $tcpSegsInSec
        }
        connections = @($activeConns)
        nics        = @($nicHealth)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-NetworkHealth.ps1'
    } | ConvertTo-Json -Compress
}
