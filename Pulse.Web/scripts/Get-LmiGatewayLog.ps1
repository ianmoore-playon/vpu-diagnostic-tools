#Requires -Version 5.1
<#
.SYNOPSIS
    Reads LogMeIn's own service log for the SSL-failure signature a venue
    middlebox leaves when it blocks or inspects the LMI gateway connection.
.DESCRIPTION
    The live TLS check (Test-TlsInspection.ps1) can only see the network as it
    is RIGHT NOW - and Pulse usually runs while a tech is standing at the box,
    after IT has already been poked. LogMeIn's service log carries the history:
    every gateway connection attempt, every handshake the venue firewall
    killed, and the exact moment the unit came back.

    Failure signature (field log, 2026-08-28: a VPU dark in LMI all day):
        Socket - <ip>:<port>/websvc - SSL error: SSLv3/TLS write client hello (in connect).
        LoadUrl - SslHandshake() failed: 122
        WebSvc - Failed to connect to web gateway: ... (10060)
    repeating for ~16 hours, then - the minute the district disabled packet
    inspection:
        WebSvc - Server certificate accepted: *.lmi-app25-14.logmein.com
        WebSvc - Logged in to web gateway.
    "SSL error ... write client hello" means the connection died the moment
    LogMeIn STARTED its handshake - the firewall killed it on the hello, the
    same mechanism as the category/SNI blocks Test-TlsInspection classifies
    as 'filtered'. Note the gateways are control.lmi-app*.logmein.com and LMI
    speaks TLS on port 80 as well as 443, so a URL allowlist for
    secure.logmein.com alone does not cover them.

    Scans the live log (LogMeIn.log) plus the daily rotations (LMIyyyyMMdd.log)
    inside the window. A healthy, long-connected unit logs NO gateway lines at
    all for days (verified on VPU2) - zero attempts is normal, not a failure.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param(
    [string]$LogDir = 'C:\ProgramData\LogMeIn',
    [int]$WindowDays = 7
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        [ordered]@{
            installed  = $false
            logsFound  = $false
            logDir     = $LogDir
            windowDays = $WindowDays
        } | ConvertTo-Json -Compress
        return
    }

    # Candidate files: the live log, plus daily rotations whose filename date
    # falls inside the window (cheaper than opening every rotation on a unit
    # with months of history).
    $files = @()
    $livePath = Join-Path $LogDir 'LogMeIn.log'
    if (Test-Path -LiteralPath $livePath) { $files += Get-Item -LiteralPath $livePath }
    $cutoff = (Get-Date).Date.AddDays(-$WindowDays)
    foreach ($f in @(Get-ChildItem -LiteralPath $LogDir -Filter 'LMI*.log' -ErrorAction SilentlyContinue)) {
        if ($f.Name -match '^LMI(\d{8})\.log$') {
            $fileDate = [datetime]::MinValue
            if ([datetime]::TryParseExact($Matches[1], 'yyyyMMdd', $null,
                    [System.Globalization.DateTimeStyles]::None, [ref]$fileDate)) {
                if ($fileDate -ge $cutoff) { $files += $f }
            }
        }
    }

    $attempts = 0; $sslFailures = 0; $handshakeFailures = 0
    $gatewayFailures = 0; $logins = 0
    $firstSslFailure = $null; $lastSslFailure = $null; $lastLogin = $null
    $hostSet = New-Object 'System.Collections.Generic.HashSet[string]'

    # One pre-filter pass per file; only matching lines are classified.
    $pattern = 'Connecting to web gateway |SSL error: SSLv3/TLS write client hello|SslHandshake\(\) failed|Failed to connect to web gateway|Logged in to web gateway'
    foreach ($f in $files) {
        foreach ($m in @(Select-String -LiteralPath $f.FullName -Pattern $pattern)) {
            $line = $m.Line
            # Timestamps sort correctly as strings (yyyy-MM-dd HH:mm:ss);
            # millis are dropped for display.
            $ts = $null
            if ($line -match '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})') { $ts = $Matches[1] }

            if ($line -match 'Connecting to web gateway ([A-Za-z0-9.\-]+):(\d+)') {
                $attempts++
                $null = $hostSet.Add($Matches[1])
            }
            elseif ($line -match 'SSL error: SSLv3/TLS write client hello') {
                $sslFailures++
                if ($ts) {
                    if (-not $firstSslFailure) { $firstSslFailure = $ts }
                    if (-not $lastSslFailure -or $ts -gt $lastSslFailure) { $lastSslFailure = $ts }
                }
            }
            elseif ($line -match 'SslHandshake\(\) failed') { $handshakeFailures++ }
            elseif ($line -match 'Failed to connect to web gateway') { $gatewayFailures++ }
            elseif ($line -match 'Logged in to web gateway') {
                $logins++
                if ($ts -and (-not $lastLogin -or $ts -gt $lastLogin)) { $lastLogin = $ts }
            }
        }
    }

    # Blocked right now = the newest SSL failure is newer than the newest
    # successful gateway login. Recovered = it logged in AFTER the failures
    # stopped (the "IT just turned inspection off" timestamp).
    $blockedNow = [bool]($lastSslFailure -and ((-not $lastLogin) -or ($lastSslFailure -gt $lastLogin)))
    $recoveredAt = $null
    if ($lastSslFailure -and $lastLogin -and ($lastLogin -gt $lastSslFailure)) { $recoveredAt = $lastLogin }

    [ordered]@{
        installed         = $true
        logsFound         = [bool]($files.Count -gt 0)
        logDir            = $LogDir
        windowDays        = $WindowDays
        filesScanned      = $files.Count
        attempts          = $attempts
        sslFailures       = $sslFailures
        handshakeFailures = $handshakeFailures
        gatewayFailures   = $gatewayFailures
        logins            = $logins
        firstSslFailure   = $firstSslFailure
        lastSslFailure    = $lastSslFailure
        lastLogin         = $lastLogin
        blockedNow        = $blockedNow
        recoveredAt       = $recoveredAt
        gatewayHosts      = @($hostSet | Sort-Object)
    } | ConvertTo-Json -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Get-LmiGatewayLog.ps1'
    } | ConvertTo-Json -Compress
}
