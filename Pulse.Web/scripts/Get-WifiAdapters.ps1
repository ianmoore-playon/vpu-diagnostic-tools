#Requires -Version 5.1
<#
.SYNOPSIS
    Detects whether the VPU is reaching the internet over Wi-Fi.
.DESCRIPTION
    Pixellot VPUs are wired-only by design. The condition worth flagging is
    not "a Wi-Fi adapter exists" -- Windows always has Wi-Fi Direct / hosted-
    network *virtual* adapters that show as connected -- but "Wi-Fi is the
    VPU's actual internet uplink." That is true only when a real Wi-Fi NIC
    carries the default route (0.0.0.0/0) AND no wired adapter does.

    Returns every Wi-Fi-class adapter with isVirtual / hasDefaultRoute flags,
    plus a top-level `uplinkIsWifi` the dashboard gates its warning on.

    Adapted from Canopy's reportWifiConnection.ps1 -- the Banyan POST envelope
    is replaced with stdout JSON for run_ps consumption.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-IsWifi {
    param($Adapter)
    return ($Adapter.PhysicalMediaType -eq 'Native 802.11' -or
            $Adapter.InterfaceDescription -like '*Wi-Fi*'   -or
            $Adapter.InterfaceDescription -like '*Wireless*' -or
            $Adapter.InterfaceDescription -like '*WLAN*')
}

function Test-IsVirtualWifi {
    param($Adapter)
    # Wi-Fi Direct / Miracast / Microsoft Hosted Network adapters are P2P
    # plumbing, never the real uplink. Match by description and the adapter's
    # Virtual flag when the OS exposes it.
    if ($Adapter.InterfaceDescription -match 'Direct|Virtual') { return $true }
    try { if ($Adapter.Virtual -eq $true) { return $true } } catch { }
    return $false
}

try {
    # -- Which interfaces carry an active default route? ----------
    # Membership here means the interface is currently providing a path to
    # the internet (a real gateway next-hop, not APIPA).
    $defaultRouteIdx = @()
    try {
        $defaultRouteIdx = @(
            Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' -and -not $_.NextHop.StartsWith('169.254.') } |
                Select-Object -ExpandProperty ifIndex -Unique
        )
    }
    catch { }

    $allAdapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)

    # Does a wired adapter hold the default route? If so, Wi-Fi (even if up)
    # is not the primary internet path and we should not warn.
    $ethernetHasDefaultRoute = $false
    foreach ($a in $allAdapters) {
        if ($a.Status -eq 'Up' -and -not (Test-IsWifi $a) -and ($defaultRouteIdx -contains $a.ifIndex)) {
            $ethernetHasDefaultRoute = $true
            break
        }
    }

    # -- Enumerate Wi-Fi-class adapters ---------------------------
    $adapters = @()
    foreach ($a in ($allAdapters | Where-Object { Test-IsWifi $_ })) {
        $isUp = ($a.Status -eq 'Up')
        $detail = [ordered]@{
            name                 = $a.Name
            interfaceAlias       = $a.InterfaceAlias
            interfaceDescription = $a.InterfaceDescription
            macAddress           = $a.MacAddress
            linkSpeed            = $a.LinkSpeed
            status               = $a.Status.ToString()
            isUp                 = $isUp
            isVirtual            = [bool](Test-IsVirtualWifi $a)
            hasDefaultRoute      = [bool]($defaultRouteIdx -contains $a.ifIndex)
            connected            = $false
            ssid                 = $null
            networkCategory      = $null
            ipv4Connectivity     = $null
            ipv6Connectivity     = $null
        }

        if ($isUp) {
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
            catch { }  # Up but not on a profile -- leave connected=false
        }

        $adapters += $detail
    }

    # -- Is Wi-Fi the VPU's actual internet uplink? ---------------
    # A real (non-virtual) Wi-Fi NIC carries the default route, and no wired
    # adapter does. This is the only case worth a warning.
    $uplinkIsWifi = $false
    if (-not $ethernetHasDefaultRoute) {
        foreach ($d in $adapters) {
            if ($d.isUp -and -not $d.isVirtual -and $d.hasDefaultRoute) {
                $uplinkIsWifi = $true
                break
            }
        }
    }

    $activeCount = @($adapters | Where-Object { $_.isUp -and -not $_.isVirtual }).Count

    [ordered]@{
        adapters                = @($adapters)
        anyActive               = ($activeCount -gt 0)
        activeCount             = $activeCount
        ethernetHasDefaultRoute = [bool]$ethernetHasDefaultRoute
        uplinkIsWifi            = [bool]$uplinkIsWifi
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-WifiAdapters.ps1'
    } | ConvertTo-Json -Compress
}
