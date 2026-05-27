#Requires -Version 5.1
<#
.SYNOPSIS
    Probes ScoreConnect service for status, configuration, BOT status, and ScoreLink detection.
.DESCRIPTION
    Makes HTTP requests to the ScoreConnect local API to check reachability, retrieve
    configuration, and fetch cloud BOT status. Also enumerates Win32_PnPEntity to detect
    whether a ScoreLink hardware box is connected via USB. Outputs JSON to stdout.

    Configuration fields are normalised to renderer-friendly names (vendor, sport, etc.)
    using the same alias tables as the WPF ScoreConnectService.
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://localhost:5000'
)

$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Invoke-SafeGet {
    param([string]$Url, [int]$TimeoutSec = 2)
    try {
        # Pre-check TCP connection with explicit socket timeout.
        # Invoke-WebRequest's -TimeoutSec only covers the response phase;
        # a SYN-blackholed port can hang for 20+ seconds at the TCP layer.
        $uri = [System.Uri]$Url
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $connectTask = $tcp.ConnectAsync($uri.Host, $uri.Port)
            if (-not $connectTask.Wait($TimeoutSec * 1000)) {
                return @{ ok = $false; content = $null }
            }
            if ($connectTask.IsFaulted) {
                return @{ ok = $false; content = $null }
            }
        } finally { $tcp.Dispose() }

        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($r.StatusCode -eq 200) { return @{ ok = $true; content = $r.Content } }
    } catch {}
    return @{ ok = $false; content = $null }
}

# Pick the first non-empty string value from a hashtable by an ordered list of
# candidate keys.  Uses PowerShell's -eq operator which is case-insensitive by
# default (e.g. 'VendorName' -eq 'vendorName' → True).  Do NOT replace with a
# direct hashtable index ($Map[$k]) — that would break the case-insensitive
# matching that SC III's inconsistent casing requires.
function Pick-First {
    param([hashtable]$Map, [string[]]$Keys)
    foreach ($k in $Keys) {
        foreach ($mk in $Map.Keys) {
            if ($mk -eq $k) {
                $v = $Map[$mk]
                if ($null -ne $v -and "$v".Trim() -ne '') { return "$v" }
            }
        }
    }
    return $null
}

# Flatten a PSCustomObject (from ConvertFrom-Json) into a case-insensitive hashtable.
# Only scalar values are kept as strings; nested objects/arrays are skipped so
# Pick-First never sees a "System.Management.Automation.PSCustomObject" string.
function To-Map {
    param($Obj)
    $map = @{}
    if ($null -eq $Obj) { return $map }
    foreach ($p in $Obj.PSObject.Properties) {
        if ($null -eq $p.Value) {
            $map[$p.Name] = $null
        } elseif ($p.Value -is [string] -or $p.Value -is [bool] -or $p.Value -is [ValueType]) {
            $map[$p.Name] = "$($p.Value)"
        }
        # Nested PSCustomObject / arrays are intentionally omitted
    }
    return $map
}

# Read DEVPKEY_Device_BusReportedDeviceDesc from the PnP property store.
# Same registry path as the WPF ScoreLinkDetector; value name is empty string (default).
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

# Read FileVersion from the ScoreConnect III executable on disk.
# WPF uses this fallback because get-status often omits a version field.
function Get-ScoreConnectExeVersion {
    $candidates = @(
        'C:\Program Files (x86)\Sportzcast LLC\ScoreConnectIII\ScoreConnectIII.exe',
        'C:\Program Files\Sportzcast LLC\ScoreConnectIII\ScoreConnectIII.exe'
    )
    foreach ($path in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $v = $info.ProductVersion
            if (-not $v) { $v = $info.FileVersion }
            if ($v) { return $v.Trim() }
        } catch {}
    }
    return $null
}

try {
    $BaseUrl = $BaseUrl.TrimEnd('/')

    # ── 1. Status probe ─────────────────────────────────────────────────────
    $reachable  = $false
    $statusData = $null
    $errorMsg   = $null
    $version    = $null

    # WPF probes get-status → get-current-configuration → root, in order.
    # We try the first two — root is too broad (matches any HTTP server).
    foreach ($path in @(
        "$BaseUrl/api/configuration/get-status",
        "$BaseUrl/api/configuration/get-current-configuration"
    )) {
        $sr = Invoke-SafeGet $path
        if ($sr.ok) {
            $reachable = $true
            try { $statusData = $sr.content | ConvertFrom-Json } catch {}
            break
        }
    }

    if (-not $reachable) {
        $errorMsg = "ScoreConnect III not reachable at $BaseUrl"
    }

    # Resolve version: response field → exe on disk
    if ($statusData) {
        $sMap = To-Map $statusData
        $version = Pick-First $sMap @('version', 'appVersion', 'serviceVersion')
    }
    if (-not $version) {
        $version = Get-ScoreConnectExeVersion
    }

    # ── 2. Extended configuration ────────────────────────────────────────────
    # Try extended first (carries firmware / event-type / vendor-config-id),
    # fall back to plain get-current-configuration like the WPF service does.
    $configuration = $null
    if ($reachable) {
        foreach ($cfgPath in @(
            "$BaseUrl/api/configuration/get-current-configuration-extended",
            "$BaseUrl/api/configuration/get-current-configuration"
        )) {
            $cr = Invoke-SafeGet $cfgPath
            if ($cr.ok) {
                try {
                    $rawCfg = $cr.content | ConvertFrom-Json
                    $cfgMap = To-Map $rawCfg

                    # Normalise field names using the same alias tables as WPF
                    # PopulateConfigurationFromJson.
                    $configuration = [ordered]@{
                        vendor                  = Pick-First $cfgMap @('vendorName', 'vendor', 'currentVendor', 'currentSbvendor')
                        sport                   = Pick-First $cfgMap @('vendorSportName', 'sport', 'vendorSport', 'sportName', 'vendorSportCode', 'currentSbCode')
                        vendorConfigurationName = Pick-First $cfgMap @('vendorConfigurationName', 'configurationName')
                        device                  = Pick-First $cfgMap @('device', 'deviceName', 'deviceId')
                        serialPort              = Pick-First $cfgMap @('serialPort', 'port', 'comPort', 'portName')
                        firmware                = Pick-First $cfgMap @('firmware', 'firmwareVersion', 'fwVersion')
                        eventType               = Pick-First $cfgMap @('eventType', 'eventTypeName', 'eventTypeId')
                    }
                    # If normalization found anything, stop trying endpoints
                    $hasAny = $false
                    foreach ($v in $configuration.Values) { if ($v) { $hasAny = $true; break } }
                    if ($hasAny) { break }
                } catch {}
            }
        }
    }

    # ── 3. BOT status ────────────────────────────────────────────────────────
    # Try v1 get-bot-number first (returns bare integer or object); fall back to
    # v2 get-bot-configuration-status for older builds.
    $botStatus = $null
    if ($reachable) {
        $botIsConnected    = $false
        $botScoreConnectId = $null
        $botServerAddress  = $null
        $botLastError      = $null

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
                $botScoreConnectId = if ($bareNumber -gt 0) { $trimmed } else { $null }
            } else {
                try {
                    $botObj = $trimmed | ConvertFrom-Json
                    $botMap = To-Map $botObj

                    $botNumStr = Pick-First $botMap @('botNumber', 'bot_number')
                    if ($null -ne $botNumStr) {
                        $botIsConnected    = ([long]$botNumStr) -gt 0
                        $botScoreConnectId = if ($botIsConnected) { $botNumStr } else { $null }
                    } else {
                        # Legacy shape: explicit boolean field
                        $connStr        = Pick-First $botMap @('botOnline', 'isConnected', 'cloudConnection', 'isCloudMode')
                        $botIsConnected = ($connStr -eq 'True' -or $connStr -eq 'true' -or $connStr -eq '1')
                        $botScoreConnectId = Pick-First $botMap @('scoreConnectId', 'id')
                    }
                    $botServerAddress = Pick-First $botMap @('botServerAddress', 'botAddress', 'botServer')
                    $botLastError     = Pick-First $botMap @('lastErrorMessage', 'lastError', 'errorMessage')
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
    # strings — mirrors the WPF ScoreLinkDetector logic.  Also checks
    # Caption and Description as secondary fallback.
    #
    # Not cached — runs every poll cycle (~30s).  The WMI USB enumeration is
    # sub-100ms and ScoreLink hardware can be plugged/unplugged between polls.
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
        # USB\ filter — WPF checks pnpId.StartsWith("USB\\").
        # WQL escaping: 'USB\\%' is a literal backslash + wildcard.
        # Some WMI provider builds reject the escaped backslash, so fall back
        # to a broader query with client-side filtering if the first fails.
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

            # Must expose a COM port number in Name or Caption
            $pm = $comRx.Match($name)
            if (-not $pm.Success) { $pm = $comRx.Match($caption) }
            if (-not $pm.Success) { continue }
            $portName = 'COM' + $pm.Groups[1].Value

            # Check bus-reported (primary), Caption, Description (secondary)
            $busDesc = Get-BusReportedDesc $dev.PNPDeviceID
            $busLow  = $busDesc.ToLower()
            $capLow  = $caption.ToLower()
            $drvLow  = $description.ToLower()

            $matched = $null
            foreach ($entry in $busNeedles) {
                if ($busLow.Contains($entry.needle) -or
                    $capLow.Contains($entry.needle) -or
                    $drvLow.Contains($entry.needle)) {
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
        version              = $version
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
        version              = $null
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
