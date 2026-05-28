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

    Real SC III get-status shape (v1.4.x):
      { botNumber, scoreBoardData: {id, messageType, description},
        network: {id, messageType, description}, isConnectedToBotServer,
        hasLocalStream, updateInProgress, data, botConfigurationInProgress }
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
# NOTE: Requires admin/elevated access on some VPU builds. Returns '' on access-denied.
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
# get-status has no version field — this is the only reliable source.
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
            if ($v) {
                # Trim git commit hash suffix: "1.4.0.10+bf99cfe..." → "1.4.0.10"
                $v = $v.Trim()
                $plusIdx = $v.IndexOf('+')
                if ($plusIdx -gt 0) { $v = $v.Substring(0, $plusIdx) }
                return $v
            }
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

    # get-status is the primary endpoint — it carries BOT status, score data
    # status, network state, and the raw scoreboard data string.
    $sr = Invoke-SafeGet "$BaseUrl/api/configuration/get-status"
    if ($sr.ok) {
        $reachable = $true
        try { $statusData = $sr.content | ConvertFrom-Json } catch {}
    }

    # Fallback: if get-status fails, try get-current-configuration to confirm
    # reachability (root is too broad — matches any HTTP server).
    if (-not $reachable) {
        $sr2 = Invoke-SafeGet "$BaseUrl/api/configuration/get-current-configuration"
        if ($sr2.ok) { $reachable = $true }
    }

    if (-not $reachable) {
        $errorMsg = "ScoreConnect III not reachable at $BaseUrl"
    }

    # Version: get-status has no version field — always use exe on disk.
    $version = Get-ScoreConnectExeVersion

    # ── 2. Extract status fields ────────────────────────────────────────────
    # Real get-status shape (v1.4.x):
    #   { botNumber: 0,
    #     scoreBoardData: { id, messageType, description },
    #     network: { id, messageType, description },
    #     isConnectedToBotServer: bool,
    #     hasLocalStream: bool,
    #     data: "raw RTD string",
    #     updateInProgress: bool,
    #     botConfigurationInProgress: bool }

    $dataStatus    = $null   # "Data is present..." or "No Scoreboard data..."
    $rawData       = $null   # Raw RTD protocol string from scoreboard
    $networkStatus = $null   # "Internet is detected" etc.
    $hasLocalStream = $null
    $isConnectedToBotServer = $null

    if ($statusData) {
        # scoreBoardData.description — tells us if data is flowing
        if ($statusData.PSObject.Properties['scoreBoardData'] -and $statusData.scoreBoardData) {
            $dataStatus = $statusData.scoreBoardData.description
        }

        # Raw data string (Daktronics RTD etc.) — trim whitespace padding
        if ($statusData.PSObject.Properties['data']) {
            $rawStr = "$($statusData.data)".Trim()
            if ($rawStr -ne '') { $rawData = $rawStr }
        }

        # Network status
        if ($statusData.PSObject.Properties['network'] -and $statusData.network) {
            $networkStatus = $statusData.network.description
        }

        # Booleans
        if ($statusData.PSObject.Properties['hasLocalStream']) {
            $hasLocalStream = [bool]$statusData.hasLocalStream
        }
        if ($statusData.PSObject.Properties['isConnectedToBotServer']) {
            $isConnectedToBotServer = [bool]$statusData.isConnectedToBotServer
        }
    }

    # ── 3. Extended configuration ────────────────────────────────────────────
    # Try extended first (carries vendor/sport names), fall back to plain
    # (only numeric IDs — less useful but confirms the config endpoint works).
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

    # ── 4. BOT status ────────────────────────────────────────────────────────
    # Primary: extract from get-status (botNumber + isConnectedToBotServer).
    # Fallback: dedicated get-bot-number endpoint (bare integer or JSON object).
    $botStatus = $null
    if ($reachable) {
        $botIsConnected    = $false
        $botScoreConnectId = $null
        $botServerAddress  = $null
        $botLastError      = $null

        # Prefer get-status fields — already parsed above
        if ($null -ne $isConnectedToBotServer) {
            $botIsConnected = $isConnectedToBotServer
            if ($statusData.PSObject.Properties['botNumber']) {
                $bn = [long]$statusData.botNumber
                if ($bn -gt 0) { $botScoreConnectId = "$bn" }
            }
        } else {
            # Fallback to dedicated endpoint
            $br = Invoke-SafeGet "$BaseUrl/api/configuration/get-bot-number"
            if (-not $br.ok) {
                $br = Invoke-SafeGet "$BaseUrl/api/v2/configuration/get-bot-configuration-status"
            }

            if ($br.ok -and $br.content) {
                $trimmed = $br.content.Trim()
                if ($trimmed -match '^\d+$') {
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
                            $connStr        = Pick-First $botMap @('botOnline', 'isConnected', 'cloudConnection', 'isCloudMode')
                            $botIsConnected = ($connStr -eq 'True' -or $connStr -eq 'true' -or $connStr -eq '1')
                            $botScoreConnectId = Pick-First $botMap @('scoreConnectId', 'id')
                        }
                        $botServerAddress = Pick-First $botMap @('botServerAddress', 'botAddress', 'botServer')
                        $botLastError     = Pick-First $botMap @('lastErrorMessage', 'lastError', 'errorMessage')
                    } catch {}
                }
            }
        }

        $botStatus = [ordered]@{
            isConnected      = $botIsConnected
            scoreConnectId   = $botScoreConnectId
            botServerAddress = $botServerAddress
            lastErrorMessage = $botLastError
        }
    }

    # ── 5. ScoreLink USB detection ───────────────────────────────────────────
    # Detection priority:
    #   1. Bus-reported description (DEVPKEY_Device_BusReportedDeviceDesc) —
    #      requires admin access, may fail with SecurityException.
    #   2. Caption / Description / Name string matching — secondary.
    #   3. VID/PID matching — tertiary fallback when bus-reported is access-
    #      denied and generic driver names ("USB Serial Device") don't match.
    #      Known VID/PID pairs for Sportzcast hardware:
    #        VID_04D8 & PID_00DD = Microchip MCP2221 (ScoreLink / ScoreLinkII)
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

    # VID/PID pairs for Sportzcast hardware — fallback when bus-reported
    # description is access-denied and Caption is generic ("USB Serial Device").
    $vidPidMap = @{
        'VID_04D8&PID_00DD' = 'ScoreLink'
    }

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
            $pnpId       = [string]$dev.PNPDeviceID

            # Must expose a COM port number in Name or Caption
            $pm = $comRx.Match($name)
            if (-not $pm.Success) { $pm = $comRx.Match($caption) }
            if (-not $pm.Success) { continue }
            $portName = 'COM' + $pm.Groups[1].Value

            # Strategy 1: bus-reported + Caption/Description needle matching
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

            # Strategy 2: VID/PID fallback — needed when bus-reported description
            # is access-denied and Caption is generic ("USB Serial Device").
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

    # ── 6. Output ────────────────────────────────────────────────────────────
    [ordered]@{
        reachable            = $reachable
        baseUrl              = $BaseUrl
        version              = $version
        dataStatus           = $dataStatus
        rawData              = $rawData
        networkStatus        = $networkStatus
        hasLocalStream       = $hasLocalStream
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
        dataStatus           = $null
        rawData              = $null
        networkStatus        = $null
        hasLocalStream       = $null
        configuration        = $null
        botStatus            = $null
        scoreLinkConnected   = $false
        scoreLinkPort        = ''
        scoreLinkModel       = ''
        scoreLinkStatusLabel = 'ScoreLink not connected'
        error                = $_.Exception.Message
    } | ConvertTo-Json -Compress
}
