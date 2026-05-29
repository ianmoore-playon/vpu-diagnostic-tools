#Requires -Version 5.1
<#
.SYNOPSIS
    Runs a traceroute to a target host for VPU network path diagnostics.
.DESCRIPTION
    Uses ICMP echo with incrementing TTL to trace the path to a target.
    Each hop reports IP, optional hostname, and round-trip time.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    [string]$Target = 'pixellot.tv',
    [int]$MaxHops = 20,
    [int]$TimeoutMs = 2000
)

$ErrorActionPreference = 'Stop'

try {
    # Resolve target to IPv4 first
    $targetIp = $null
    try {
        $resolved = [System.Net.Dns]::GetHostAddresses($Target) |
            Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
            Select-Object -First 1
        if ($resolved) { $targetIp = $resolved.ToString() }
    }
    catch { }

    if (-not $targetIp) {
        [ordered]@{
            error   = $true
            message = "Could not resolve target: $Target"
            script  = 'Test-Traceroute.ps1'
        } | ConvertTo-Json -Compress
        return
    }

    $pinger  = New-Object System.Net.NetworkInformation.Ping
    $options = New-Object System.Net.NetworkInformation.PingOptions
    $options.DontFragment = $true
    $buffer  = [byte[]]::new(32)

    $hops    = @()
    $reached = $false

    for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
        $options.Ttl = $ttl
        $ip       = $null
        $hostname = $null
        $rttMs    = $null
        $hopStatus = 'timeout'

        try {
            $reply = $pinger.Send($targetIp, $TimeoutMs, $buffer, $options)

            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TtlExpired -or
                $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $ip     = $reply.Address.ToString()
                $rttMs  = $reply.RoundtripTime
                $hopStatus = if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { 'reached' } else { 'transit' }

                # Quick reverse DNS — 500ms async timeout so it doesn't stall
                try {
                    $ar = [System.Net.Dns]::BeginGetHostEntry($ip, $null, $null)
                    if ($ar.AsyncWaitHandle.WaitOne(500)) {
                        $entry = [System.Net.Dns]::EndGetHostEntry($ar)
                        if ($entry.HostName -and $entry.HostName -ne $ip) {
                            $hostname = $entry.HostName
                        }
                    }
                }
                catch { }
            }
            elseif ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TimedOut) {
                $hopStatus = 'timeout'
            }
            else {
                $hopStatus = $reply.Status.ToString()
            }
        }
        catch {
            $hopStatus = 'error'
        }

        $hops += [ordered]@{
            hop      = $ttl
            ip       = $ip
            hostname = $hostname
            rttMs    = $rttMs
            status   = $hopStatus
        }

        if ($hopStatus -eq 'reached') {
            $reached = $true
            break
        }
    }

    $pinger.Dispose()

    [ordered]@{
        target   = $Target
        targetIp = $targetIp
        reached  = $reached
        hops     = @($hops)
        hopCount = $hops.Count
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-Traceroute.ps1'
    } | ConvertTo-Json -Compress
}
