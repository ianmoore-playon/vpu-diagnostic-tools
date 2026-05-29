#Requires -Version 5.1
<#
.SYNOPSIS
    Detects active Wi-Fi network adapters on the VPU.
.DESCRIPTION
    Pixellot VPUs are wired-only by design — an active Wi-Fi adapter
    indicates either bench-test residue, a faulty network configuration,
    or someone tethering to a phone. Either way the dashboard flags it
    as a warning so the field tech can disable the radio.

    For each Wi-Fi adapter found, returns interface description, MAC,
    link speed, status, and (if connected) the SSID and IPv4/IPv6
    connectivity classification. Wired adapters are explicitly ignored.

    Adapted from Canopy's reportWifiConnection.ps1 — the Banyan POST
    envelope is replaced with stdout JSON for run_ps consumption.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Get-NetAdapter is the standard discovery primitive; filter to Wi-Fi
    # specifically so virtual / loopback / Ethernet adapters never appear here.
    # Match either the PhysicalMediaType (most reliable) or the description
    # for hosts where the PMT is reported as "Unspecified".
    $candidates = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.PhysicalMediaType -eq 'Native 802.11' -or
        $_.InterfaceDescription -like '*Wi-Fi*'  -or
        $_.InterfaceDescription -like '*Wireless*' -or
        $_.InterfaceDescription -like '*WLAN*'
    }

    $adapters = @()
    foreach ($a in $candidates) {
        $isUp = ($a.Status -eq 'Up')
        $detail = [ordered]@{
            name                 = $a.Name
            interfaceAlias       = $a.InterfaceAlias
            interfaceDescription = $a.InterfaceDescription
            macAddress           = $a.MacAddress
            linkSpeed            = $a.LinkSpeed
            status               = $a.Status.ToString()
            isUp                 = $isUp
            connected            = $false
            ssid                 = $null
            networkCategory      = $null
            ipv4Connectivity     = $null
            ipv6Connectivity     = $null
        }

        if ($isUp) {
            # Only adapters that are Up can be on a Wi-Fi network. Get-NetConnectionProfile
            # returns "NoTraffic" / "LocalNetwork" / "Internet" for ipv4Connectivity, which
            # is the signal we surface to the tech.
            # $profile is a PowerShell automatic variable (profile script path);
            # use $connProfile to avoid shadowing it.
            try {
                $connProfile = Get-NetConnectionProfile -InterfaceAlias $a.Name -ErrorAction Stop
                if ($connProfile) {
                    $detail.connected        = $true
                    $detail.ssid             = $connProfile.Name
                    $detail.networkCategory  = "$($connProfile.NetworkCategory)"
                    $detail.ipv4Connectivity = "$($connProfile.IPv4Connectivity)"
                    $detail.ipv6Connectivity = "$($connProfile.IPv6Connectivity)"
                }
            }
            catch { }  # Up but not on a profile — leave connected=false
        }

        $adapters += $detail
    }

    $activeCount = ($adapters | Where-Object { $_.isUp }).Count

    [ordered]@{
        adapters    = @($adapters)
        anyActive   = ($activeCount -gt 0)
        activeCount = $activeCount
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-WifiAdapters.ps1'
    } | ConvertTo-Json -Compress
}
