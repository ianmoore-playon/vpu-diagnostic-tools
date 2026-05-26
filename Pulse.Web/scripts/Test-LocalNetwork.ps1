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
                $reply = $pinger.Send($Target, 2000)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $recv++
                    $times += $reply.RoundtripTime
                }
            }
            catch { }
        }
        $pinger.Dispose()

        $result.received = $recv
        $result.lossPercent = [math]::Round((($result.sent - $recv) / $result.sent) * 100, 0)

        if ($times.Count -gt 0) {
            $result.reachable = $true
            $result.minMs = [int]($times | Measure-Object -Minimum).Minimum
            $result.avgMs = [int][math]::Round(($times | Measure-Object -Average).Average, 0)
            $result.maxMs = [int]($times | Measure-Object -Maximum).Maximum
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

    $ipConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue
    foreach ($ipc in $ipConfigs) {
        if ($ipc.IPv4DefaultGateway) {
            $gw = $ipc.IPv4DefaultGateway | Where-Object {
                $_.NextHop -and -not $_.NextHop.StartsWith('169.254.')
            } | Select-Object -First 1
            if ($gw) {
                $gateway = $gw.NextHop
                # Get DNS from the same interface
                if ($ipc.DNSServer) {
                    $dns = ($ipc.DNSServer | ForEach-Object { $_.ServerAddresses } |
                            Select-Object -Unique -First 1)
                }
                break
            }
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
