#Requires -Version 5.1
<#
.SYNOPSIS
    Tests local network health by pinging gateway and DNS server.
.DESCRIPTION
    Sends 4 ICMP pings to the default gateway and primary DNS server,
    captures latency (min/avg/max) and packet loss percentage.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    [int]$Count = 4
)

$ErrorActionPreference = 'Stop'

function Test-PingTarget {
    param([string]$Target, [string]$Label, [int]$PingCount = 4)

    $result = [ordered]@{
        target     = $Target
        label      = $Label
        reachable  = $false
        sent       = $PingCount
        received   = 0
        lossPercent = 100
        minMs      = $null
        avgMs      = $null
        maxMs      = $null
        status     = 'fail'
    }

    if (-not $Target -or $Target -eq '') { return $result }

    try {
        $pinger = New-Object System.Net.NetworkInformation.Ping
        $times = @()
        $recv = 0

        for ($i = 0; $i -lt $PingCount; $i++) {
            try {
                # Use Stopwatch for sub-ms precision on LAN pings
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $reply = $pinger.Send($Target, 2000)
                $sw.Stop()
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $recv++
                    $elapsed = $sw.Elapsed.TotalMilliseconds
                    # Use Stopwatch time if .NET reports 0 (sub-ms LAN ping)
                    $ms = if ($reply.RoundtripTime -gt 0) { [double]$reply.RoundtripTime } else { $elapsed }
                    $times += [math]::Round($ms, 2)
                }
            }
            catch { }
        }
        $pinger.Dispose()

        $result.received = $recv
        $result.lossPercent = [math]::Round((($result.sent - $recv) / $result.sent) * 100, 0)

        if ($times.Count -gt 0) {
            $result.reachable = $true
            $result.minMs = [math]::Round(($times | Measure-Object -Minimum).Minimum, 2)
            $result.avgMs = [math]::Round(($times | Measure-Object -Average).Average, 2)
            $result.maxMs = [math]::Round(($times | Measure-Object -Maximum).Maximum, 2)
        }

        # Classify
        if ($recv -eq 0) {
            $result.status = 'fail'
        }
        elseif ($result.lossPercent -gt 0 -or $result.avgMs -gt 50) {
            $result.status = 'warn'
        }
        else {
            $result.status = 'pass'
        }
    }
    catch {
        # leave defaults (fail)
    }

    return $result
}

try {
    # Discover gateway and DNS from the uplink adapter
    $gateway = $null
    $dns = $null

    # Scope to the interface that owns the active default route (lowest-metric
    # 0.0.0.0/0). Walking Get-NetIPConfiguration and taking the first interface
    # with any gateway can land on a secondary/disconnected NIC (camera port,
    # VPN) and ping the wrong gateway/DNS -- reporting local-network health for
    # an adapter that isn't actually carrying traffic.
    $uplinkIdx = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' -and -not $_.NextHop.StartsWith('169.254.') } |
        Sort-Object RouteMetric | Select-Object -First 1).InterfaceIndex

    $ipc = $null
    if ($uplinkIdx) {
        $ipc = Get-NetIPConfiguration -InterfaceIndex $uplinkIdx -ErrorAction SilentlyContinue
    }
    if (-not $ipc) {
        # No default route resolved -- fall back to the first interface that has a
        # usable (non-APIPA) gateway, preserving the prior behaviour.
        $ipc = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
            $_.IPv4DefaultGateway | Where-Object { $_.NextHop -and -not $_.NextHop.StartsWith('169.254.') }
        } | Select-Object -First 1
    }

    if ($ipc) {
        $gw = $ipc.IPv4DefaultGateway | Where-Object {
            $_.NextHop -and -not $_.NextHop.StartsWith('169.254.')
        } | Select-Object -First 1
        if ($gw) { $gateway = $gw.NextHop }
        # DNS from the same (uplink) interface
        if ($ipc.DNSServer) {
            $dns = ($ipc.DNSServer | ForEach-Object { $_.ServerAddresses } |
                    Select-Object -Unique -First 1)
        }
    }

    $gatewayResult = Test-PingTarget -Target $gateway -Label 'Gateway' -PingCount $Count
    $dnsResult     = Test-PingTarget -Target $dns     -Label 'DNS Server' -PingCount $Count

    [ordered]@{
        gateway = $gatewayResult
        dns     = $dnsResult
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-LocalNetwork.ps1'
    } | ConvertTo-Json -Compress
}
