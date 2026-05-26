#Requires -Version 5.1
<#
.SYNOPSIS
    Probes ScoreConnect service for status, configuration, BOT status, and ScoreLink detection.
.DESCRIPTION
    Makes HTTP requests to the ScoreConnect local API to check reachability, retrieve
    configuration, and fetch cloud BOT status. Also enumerates Win32_PnPEntity to detect
    whether a ScoreLink hardware box is connected via USB. Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:5000'
)

$ErrorActionPreference = 'Stop'

function Invoke-SafeGet {
    param([string]$Url, [int]$TimeoutSec = 2)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($r.StatusCode -eq 200) { return @{ ok = $true; content = $r.Content } }
    } catch {}
    return @{ ok = $false; content = $null }
}

# Pick the first non-empty string from a list of property names on $Obj.
function Get-FirstProp {
    param($Obj, [string[]]$Names)
    foreach ($n in $Names) {
        $v = $null
        try { $v = $Obj.$n } catch {}
        if ($null -ne $v -and "$v".Trim() -ne '') { return "$v" }
    }
    return $null
}

# Read DEVPKEY_Device_BusReportedDeviceDesc from the PnP property store registry key.
# The WPF ScoreLinkDetector uses the same path; value name is empty string (default).
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

try {
    $BaseUrl = $BaseUrl.TrimEnd('/')

    # ── 1. Status probe ─────────────────────────────────────────────────────
    $reachable  = $false
    $statusData = $null
    $errorMsg   = $null

    $sr = Invoke-SafeGet "$BaseUrl/api/configuration/get-status"
    if ($sr.ok) {
        $reachable = $true
        try { $statusData = $sr.content | ConvertFrom-Json } catch {}
    } else {
        $errorMsg = "ScoreConnect III not reachable at $BaseUrl"
    }

    # ── 2. Extended configuration ────────────────────────────────────────────
    $configuration = $null
    if ($reachable) {
        $cr = Invoke-SafeGet "$BaseUrl/api/configuration/get-current-configuration-extended"
        if ($cr.ok) {
            try { $configuration = $cr.content | ConvertFrom-Json } catch {}
        }
    }

    # ── 3. BOT status ────────────────────────────────────────────────────────
    # Try v1 get-bot-number first (returns bare integer or object); fall back to
    # v2 get-bot-configuration-status for older builds.
    $botStatus = $null
    if ($reachable) {
        $botIsConnected    = $false
        $botScoreConnectId = ''
        $botServerAddress  = ''
        $botLastError      = ''

        $br = Invoke-SafeGet "$BaseUrl/api/configuration/get-bot-number"
        if (-not $br.ok) {
            $br = Invoke-SafeGet "$BaseUrl/api/v2/configuration/get-bot-configuration-status"
        }

        if ($br.ok -and $br.content) {
            $trimmed = $br.content.Trim()
            if ($trimmed -match '^\d+$') {
                # Bare integer — non-zero means paired with Sportzcast cloud
                $bareNumber        = [long]$trimmed
                $botIsConnected    = $bareNumber -gt 0
                $botScoreConnectId = if ($bareNumber -gt 0) { $trimmed } else { '' }
            } else {
                try {
                    $botObj    = $trimmed | ConvertFrom-Json
                    $botNumStr = Get-FirstProp $botObj @('botNumber', 'bot_number')
                    if ($null -ne $botNumStr) {
                        $botIsConnected    = ([long]$botNumStr) -gt 0
                        $botScoreConnectId = if ($botIsConnected) { $botNumStr } else { '' }
                    } else {
                        # Legacy shape: explicit boolean field
                        $connStr        = Get-FirstProp $botObj @('botOnline', 'isConnected', 'cloudConnection', 'isCloudMode')
                        $botIsConnected = ($connStr -eq 'True' -or $connStr -eq 'true' -or $connStr -eq '1')
                        $idStr          = Get-FirstProp $botObj @('scoreConnectId', 'id')
                        $botScoreConnectId = if ($idStr) { $idStr } else { '' }
                    }
                    $addrStr          = Get-FirstProp $botObj @('botServerAddress', 'botAddress', 'botServer')
                    $botServerAddress = if ($addrStr) { $addrStr } else { '' }
                    $errStr           = Get-FirstProp $botObj @('lastErrorMessage', 'lastError', 'errorMessage')
                    $botLastError     = if ($errStr) { $errStr } else { '' }
                } catch {}
            }
        }

        $botStatus = [ordered]@{
            isConnected      = $botIsConnected
            scoreConnectId   = $botScoreConnectId
            botServerAddress = $botServerAddress
            lastErrorMessage = $botLastError
        }
    }

    # ── 4. ScoreLink USB detection ───────────────────────────────────────────
    # Matches bus-reported device description from the PnP property store
    # (DEVPKEY_Device_BusReportedDeviceDesc) against known ScoreLink needle
    # strings — mirrors the WPF ScoreLinkDetector logic.
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

    $comRx = [regex]'\bCOM(\d+)\b'

    try {
        $pnpDevices = Get-CimInstance -ClassName Win32_PnPEntity `
            -Filter "PNPDeviceID LIKE 'USB%'" -ErrorAction Stop

        foreach ($dev in $pnpDevices) {
            $caption = [string]$dev.Caption
            $name    = [string]$dev.Name

            # Must expose a COM port number in Name or Caption
            $pm = $comRx.Match($name)
            if (-not $pm.Success) { $pm = $comRx.Match($caption) }
            if (-not $pm.Success) { continue }
            $portName = 'COM' + $pm.Groups[1].Value

            $busDesc = Get-BusReportedDesc $dev.PNPDeviceID
            $busLow  = $busDesc.ToLower()
            $capLow  = $caption.ToLower()

            $matched = $null
            foreach ($entry in $busNeedles) {
                if ($busLow.Contains($entry.needle) -or $capLow.Contains($entry.needle)) {
                    $matched = $entry; break
                }
            }
            if ($null -eq $matched) { continue }

            # ScoreLinkII wins over ScoreLink when both are present
            if ($matched.model -eq 'ScoreLinkII' -or -not $scoreLinkConnected) {
                $scoreLinkConnected = $true
                $scoreLinkPort      = $portName
                $scoreLinkModel     = $matched.model
                if ($matched.model -eq 'ScoreLinkII') { break }
            }
        }
    } catch {}

    $scoreLinkLabel = if (-not $scoreLinkConnected) {
        'ScoreLink not connected'
    } elseif (-not $scoreLinkPort) {
        "$scoreLinkModel device connected"
    } else {
        "$scoreLinkModel device connected ($scoreLinkPort)"
    }

    # ── 5. Output ────────────────────────────────────────────────────────────
    [ordered]@{
        reachable            = $reachable
        baseUrl              = $BaseUrl
        status               = $statusData
        configuration        = $configuration
        botStatus            = $botStatus
        scoreLinkConnected   = $scoreLinkConnected
        scoreLinkPort        = $scoreLinkPort
        scoreLinkModel       = $scoreLinkModel
        scoreLinkStatusLabel = $scoreLinkLabel
        error                = $errorMsg
    } | ConvertTo-Json -Depth 10 -Compress
}
catch {
    [ordered]@{
        reachable            = $false
        baseUrl              = $BaseUrl
        status               = $null
        configuration        = $null
        botStatus            = $null
        scoreLinkConnected   = $false
        scoreLinkPort        = ''
        scoreLinkModel       = ''
        scoreLinkStatusLabel = 'ScoreLink not connected'
        error                = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
