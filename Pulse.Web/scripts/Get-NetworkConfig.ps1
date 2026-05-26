#Requires -Version 5.1
<#
.SYNOPSIS
    Collects network configuration for VPU diagnostics.
.DESCRIPTION
    Gathers adapter info, IP configuration, internet reachability,
    NTP source, and identifies the uplink adapter. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Net adapters
    $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{
            name                 = $_.Name
            interfaceDescription = $_.InterfaceDescription
            status               = $_.Status
            macAddress           = $_.MacAddress
            linkSpeed            = $_.LinkSpeed
            interfaceIndex       = $_.InterfaceIndex
        }
    }

    # Build lookup tables keyed by InterfaceIndex for DHCP status and prefix length
    $ipIfaceMap = @{}
    Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        $ipIfaceMap[$_.InterfaceIndex] = $_
    }
    $ipAddrMap = @{}
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $ipAddrMap.ContainsKey($_.InterfaceIndex)) {
            $ipAddrMap[$_.InterfaceIndex] = $_
        }
    }

    # IP configurations
    $ipConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
        $idx   = $_.InterfaceIndex
        $iface = $ipIfaceMap[$idx]
        $addr  = $ipAddrMap[$idx]
        [ordered]@{
            interfaceAlias     = $_.InterfaceAlias
            interfaceIndex     = $idx
            ipv4Address        = if ($_.IPv4Address) { ($_.IPv4Address | ForEach-Object { $_.IPAddress }) } else { @() }
            ipv4DefaultGateway = if ($_.IPv4DefaultGateway) { ($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) } else { @() }
            dnsServers         = if ($_.DNSServer) { ($_.DNSServer | ForEach-Object { $_.ServerAddresses }) | Select-Object -Unique } else { @() }
            dhcpEnabled        = if ($iface) { $iface.Dhcp -eq 'Enabled' } else { $false }
            prefixLength       = if ($_.IPv4Address) { [int]($_.IPv4Address | Select-Object -First 1).PrefixLength } else { if ($addr) { [int]$addr.PrefixLength } else { $null } }
        }
    }

    # Identify uplink adapter (has a non-APIPA default gateway)
    $uplinkAdapter = $null
    foreach ($ipc in $ipConfigs) {
        $gateways = $ipc.ipv4DefaultGateway
        if ($gateways) {
            $validGw = $gateways | Where-Object { $_ -and -not $_.StartsWith('169.254.') }
            if ($validGw) {
                $uplinkAdapter = [ordered]@{
                    interfaceAlias = $ipc.interfaceAlias
                    interfaceIndex = $ipc.interfaceIndex
                    gateway        = ($validGw | Select-Object -First 1)
                }
                break
            }
        }
    }

    # Internet reachability — use .NET Ping with explicit 2s timeout
    # (Test-Connection can hang for 10+ seconds on VPU hardware)
    $internetReachable = $false
    $reachHost = $null
    foreach ($target in @('8.8.8.8', '1.1.1.1')) {
        if ($internetReachable) { break }
        try {
            $pinger = New-Object System.Net.NetworkInformation.Ping
            $reply = $pinger.Send($target, 2000)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $internetReachable = $true
                $reachHost = $target
            }
            $pinger.Dispose()
        }
        catch { }
    }

    # NTP source
    $ntpSource = $null
    try {
        $ntpOutput = & w32tm /query /source 2>&1
        if ($LASTEXITCODE -eq 0 -and $ntpOutput) {
            $ntpSource = ($ntpOutput | Out-String).Trim()
        }
    }
    catch { }

    $result = [ordered]@{
        adapters         = @($adapters)
        ipConfigurations = @($ipConfigs)
        uplinkAdapter    = $uplinkAdapter
        internet = [ordered]@{
            reachable = $internetReachable
            testedHost = $reachHost
        }
        ntpSource = $ntpSource
    }

    $result | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-NetworkConfig.ps1'
    } | ConvertTo-Json -Compress
}
