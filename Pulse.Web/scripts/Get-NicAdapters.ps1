#Requires -Version 5.1
<#
.SYNOPSIS
    Collects NIC port status for camera-facing NICs.
.DESCRIPTION
    Enumerates Intel and Realtek adapters commonly used for camera connections.
    Includes link status, error stats, and ARP table entries. Outputs JSON.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Filter for camera-facing NIC chipsets
    $cameraAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.InterfaceDescription -match 'I210|I350|82574L|I211|Realtek'
    }

    # PnP/driver health per network device (by instance ID) — lets us tell a
    # driver fault from a simply-unplugged port when a port is down.
    $pnpStatus = @{}
    try {
        Get-PnpDevice -Class Net -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.InstanceId) { $pnpStatus[$_.InstanceId.ToUpper()] = $_.Status }
        }
    } catch { }

    $ports = @()

    foreach ($adapter in $cameraAdapters) {
        # Parse link speed to Mbps
        $linkSpeedMbps = $null
        if ($adapter.LinkSpeed) {
            $speedStr = $adapter.LinkSpeed
            if ($speedStr -match '(\d+(\.\d+)?)\s*(Gbps|Mbps)') {
                $val  = [double]$Matches[1]
                $unit = $Matches[3]
                $linkSpeedMbps = if ($unit -eq 'Gbps') { [int]($val * 1000) } else { [int]$val }
            }
        }

        # Duplex detection
        $fullDuplex = $null
        try { $fullDuplex = $adapter.FullDuplex } catch { }

        # Adapter statistics — broken out for granular display
        $rxBytes  = 0; $txBytes  = 0
        $rxErrors = 0; $txErrors = 0
        $rxPacketErrors = 0; $rxDiscards = 0
        $txPacketErrors = 0; $txDiscards = 0
        try {
            $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction Stop
            $rxBytes        = $stats.ReceivedBytes
            $txBytes        = $stats.SentBytes
            $rxPacketErrors = $stats.ReceivedUnicastPacketsWithErrors
            $rxDiscards     = $stats.ReceivedDiscards
            $txPacketErrors = $stats.OutboundPacketErrors
            $txDiscards     = $stats.OutboundDiscards
            $rxErrors       = $rxPacketErrors + $rxDiscards
            $txErrors       = $txPacketErrors + $txDiscards
        }
        catch {
            try {
                $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
                if ($stats) {
                    $rxBytes = $stats.ReceivedBytes
                    $txBytes = $stats.SentBytes
                }
            }
            catch { }
        }

        # ARP entries for this adapter
        $arpEntries = @()
        try {
            $neighbors = Get-NetNeighbor -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue |
                Where-Object { $_.State -ne 'Unreachable' -and $_.IPAddress -and $_.LinkLayerAddress }
            $arpEntries = @($neighbors | ForEach-Object {
                [ordered]@{
                    ip  = $_.IPAddress
                    mac = $_.LinkLayerAddress
                }
            })
        }
        catch { }

        # Driver health for this adapter (OK / Error / Degraded / Unknown).
        # NB: avoid $pid — it's a reserved PowerShell automatic variable.
        $driverStatus = $null
        try {
            $pnpId = $adapter.PnPDeviceID
            if ($pnpId -and $pnpStatus.ContainsKey($pnpId.ToUpper())) {
                $driverStatus = $pnpStatus[$pnpId.ToUpper()]
            }
        } catch { }

        $ports += [ordered]@{
            name                = $adapter.Name
            interfaceDescription = $adapter.InterfaceDescription
            mac                 = $adapter.MacAddress
            status              = $adapter.Status
            adminStatus         = "$($adapter.AdminStatus)"
            driverStatus        = $driverStatus
            linkSpeedMbps       = $linkSpeedMbps
            fullDuplex          = $fullDuplex
            mediaConnectionState = $adapter.MediaConnectionState
            rxBytes             = $rxBytes
            txBytes             = $txBytes
            rxErrors            = $rxErrors
            txErrors            = $txErrors
            rxPacketErrors      = $rxPacketErrors
            rxDiscards          = $rxDiscards
            txPacketErrors      = $txPacketErrors
            txDiscards          = $txDiscards
            arpEntries          = $arpEntries
        }
    }

    [ordered]@{
        ports = @($ports)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-NicAdapters.ps1'
    } | ConvertTo-Json -Compress
}
