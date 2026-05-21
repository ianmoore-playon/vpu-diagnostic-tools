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

        # Adapter statistics
        $rxErrors = 0
        $txErrors = 0
        $rxBytes  = 0
        $txBytes  = 0
        try {
            $stats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction Stop
            $rxErrors = $stats.ReceivedUnicastPacketsWithErrors + $stats.ReceivedDiscards
            $txErrors = $stats.OutboundPacketErrors + $stats.OutboundDiscards
            $rxBytes  = $stats.ReceivedBytes
            $txBytes  = $stats.SentBytes
        }
        catch {
            # Some adapters may not support all stats
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

        $ports += [ordered]@{
            name                = $adapter.Name
            interfaceDescription = $adapter.InterfaceDescription
            mac                 = $adapter.MacAddress
            status              = $adapter.Status
            linkSpeedMbps       = $linkSpeedMbps
            mediaConnectionState = $adapter.MediaConnectionState
            rxBytes             = $rxBytes
            txBytes             = $txBytes
            rxErrors            = $rxErrors
            txErrors            = $txErrors
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
