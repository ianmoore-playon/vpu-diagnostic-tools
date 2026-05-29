#Requires -Version 5.1
<#
.SYNOPSIS
    Lightweight check for the ScoreLink USB device (ScoreConnect's serial
    adapter), for live monitoring of USB connect/disconnect.
.DESCRIPTION
    A scoreboard controller reaches ScoreConnect through a ScoreLink USB
    adapter. If that USB device is unplugged, the scoreboard data drops the
    same way it does when the controller is turned off. This script does ONLY
    the USB enumeration (a sub-100ms WMI query) so the frontend can poll it
    every few seconds and flag a USB disconnect distinctly from a controller
    power-off.

    Detection priority (mirrors Get-ScoreConnectStatus.ps1):
      1. Bus-reported description (DEVPKEY_Device_BusReportedDeviceDesc)
      2. Caption / Description / Name string matching
      3. VID/PID fallback (VID_04D8 & PID_00DD = Microchip MCP2221)
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-BusReportedDesc {
    param([string]$PnpDeviceId)
    if (-not $PnpDeviceId) { return '' }
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$PnpDeviceId\Properties\{a45c254e-df1c-4efd-8020-67d146a850e0}\0004"
        $key = Get-Item -LiteralPath $regPath -ErrorAction Stop
        $v = $key.GetValue('')
        if (-not $v) { $v = $key.GetValue('Data') }
        return [string]$v
    } catch { return '' }
}

$scoreLinkConnected = $false
$scoreLinkPort      = ''
$scoreLinkModel     = ''

$busNeedles = @(
    @{ needle = 'scorelinkii';                model = 'ScoreLinkII' },
    @{ needle = 'scorelink ii';               model = 'ScoreLinkII' },
    @{ needle = 'score link ii';              model = 'ScoreLinkII' },
    @{ needle = 'mcp2221 usb-i2c/uart combo'; model = 'ScoreLink'   },
    @{ needle = 'mcp2221';                    model = 'ScoreLink'   }
)
$vidPidMap = @{ 'VID_04D8&PID_00DD' = 'ScoreLink' }
$comRx = [regex]'\bCOM(\d+)\b'

try {
    $pnpDevices = $null
    try {
        $pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity `
            -Filter "PNPDeviceID LIKE 'USB\\%'" -ErrorAction Stop
    } catch {
        $allDevices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop
        $pnpDevices = $allDevices | Where-Object { $_.PNPDeviceID -like 'USB\*' }
    }

    foreach ($dev in $pnpDevices) {
        $caption     = [string]$dev.Caption
        $name        = [string]$dev.Name
        $description = [string]$dev.Description
        $pnpId       = [string]$dev.PNPDeviceID

        $pm = $comRx.Match($name)
        if (-not $pm.Success) { $pm = $comRx.Match($caption) }
        if (-not $pm.Success) { continue }
        $portName = 'COM' + $pm.Groups[1].Value

        $busLow = (Get-BusReportedDesc $dev.PNPDeviceID).ToLower()
        $capLow = $caption.ToLower()
        $drvLow = $description.ToLower()

        $matched = $null
        foreach ($entry in $busNeedles) {
            if ($busLow.Contains($entry.needle) -or
                $capLow.Contains($entry.needle) -or
                $drvLow.Contains($entry.needle)) {
                $matched = $entry; break
            }
        }
        if ($null -eq $matched) {
            $pnpUpper = $pnpId.ToUpper()
            foreach ($vidpid in $vidPidMap.Keys) {
                if ($pnpUpper.Contains($vidpid)) {
                    $matched = @{ needle = $vidpid; model = $vidPidMap[$vidpid] }
                    break
                }
            }
        }
        if ($null -eq $matched) { continue }

        if ($matched.model -eq 'ScoreLinkII' -or -not $scoreLinkConnected) {
            $scoreLinkConnected = $true
            $scoreLinkPort      = $portName
            $scoreLinkModel     = $matched.model
            if ($matched.model -eq 'ScoreLinkII') { break }
        }
    }
} catch {}

$label = if (-not $scoreLinkConnected) {
    'ScoreLink device disconnected'
} elseif (-not $scoreLinkPort) {
    "$scoreLinkModel device connected"
} else {
    "$scoreLinkModel device connected ($scoreLinkPort)"
}

@{
    connected   = $scoreLinkConnected
    port        = $scoreLinkPort
    model       = $scoreLinkModel
    statusLabel = $label
} | ConvertTo-Json
