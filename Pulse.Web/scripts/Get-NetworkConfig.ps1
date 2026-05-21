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

    # IP configurations
    $ipConfigs = Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{
            interfaceAlias   = $_.InterfaceAlias
            interfaceIndex   = $_.InterfaceIndex
            ipv4Address      = if ($_.IPv4Address) { ($_.IPv4Address | ForEach-Object { $_.IPAddress }) } else { @() }
            ipv4DefaultGateway = if ($_.IPv4DefaultGateway) { ($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) } else { @() }
            dnsServers       = if ($_.DNSServer) { ($_.DNSServer | ForEach-Object { $_.ServerAddresses }) | Select-Object -Unique } else { @() }
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

    # Internet reachability
    $internetReachable = $false
    $reachHost = $null
    try {
        $ping = Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($ping) {
            $internetReachable = $true
            $reachHost = '8.8.8.8'
        }
    }
    catch { }

    if (-not $internetReachable) {
        try {
            $ping = Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($ping) {
                $internetReachable = $true
                $reachHost = '1.1.1.1'
            }
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
