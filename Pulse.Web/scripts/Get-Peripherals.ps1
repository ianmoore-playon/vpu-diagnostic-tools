#Requires -Version 5.1
<#
.SYNOPSIS
    Detects whether a mouse, keyboard, and monitor are connected.
.DESCRIPTION
    For the System Overview "Peripherals" panel. Reports presence + count +
    device names for pointing devices, keyboards, and displays, as the OS
    currently sees them.

    Detection sources:
      - Mouse    : Win32_PointingDevice
      - Keyboard : Win32_Keyboard
      - Monitor  : Win32_PnPEntity (PNPClass='Monitor', present), with a
                   Win32_DesktopMonitor fallback.

    Caveat surfaced to the UI: over RDP / LogMeIn the OS reports the REMOTE
    session's virtual mouse/keyboard and the remote display, not necessarily
    the physical peripherals at the VPU. The panel notes this.

    Resilient pattern (same as Get-AudioDevices.ps1): always emits one JSON
    object to stdout, even if a class query fails on an odd image.
.OUTPUTS
    JSON to stdout.
#>
[CmdletBinding()]
param()

function _names($items, $prop) {
    @($items | ForEach-Object { $_.$prop } | Where-Object { $_ } | Select-Object -Unique)
}

# ── Mouse ─────────────────────────────────────────────────────
$mouse = [ordered]@{ connected = $false; count = 0; devices = @(); error = $null }
try {
    $m = @(Get-CimInstance Win32_PointingDevice -ErrorAction Stop)
    $mouse.count = $m.Count
    $mouse.connected = $m.Count -gt 0
    $mouse.devices = _names $m 'Name'
} catch { $mouse.error = $_.Exception.Message }

# ── Keyboard ──────────────────────────────────────────────────
$keyboard = [ordered]@{ connected = $false; count = 0; devices = @(); error = $null }
try {
    $k = @(Get-CimInstance Win32_Keyboard -ErrorAction Stop)
    $keyboard.count = $k.Count
    $keyboard.connected = $k.Count -gt 0
    $keyboard.devices = _names $k 'Name'
} catch { $keyboard.error = $_.Exception.Message }

# ── Monitor ───────────────────────────────────────────────────
# Prefer PnP monitor entities that are actually present/OK; fall back to
# Win32_DesktopMonitor. Headless VPUs report 0 here, which is the point.
$monitor = [ordered]@{ connected = $false; count = 0; displays = @(); source = $null; error = $null }
try {
    $mon = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Monitor'" -ErrorAction Stop |
        Where-Object { $_.Status -eq 'OK' -or $_.Present -eq $true })
    if ($mon.Count -gt 0) {
        $monitor.source = 'pnp'
        $monitor.count = $mon.Count
        $monitor.connected = $true
        $monitor.displays = _names $mon 'Name'
    } else {
        # Fallback — some images don't surface monitors via PnPEntity.
        $dm = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction Stop |
            Where-Object { $_.Availability -ne 8 })   # 8 = Off-Line
        $monitor.source = 'desktopmonitor'
        $monitor.count = $dm.Count
        $monitor.connected = $dm.Count -gt 0
        $monitor.displays = _names $dm 'Name'
    }
} catch { $monitor.error = $_.Exception.Message }

[ordered]@{
    mouse    = $mouse
    keyboard = $keyboard
    monitor  = $monitor
} | ConvertTo-Json -Depth 5 -Compress
