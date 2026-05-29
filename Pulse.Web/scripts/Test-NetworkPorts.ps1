#Requires -Version 5.1
<#
.SYNOPSIS
    Tests network port connectivity for VPU diagnostics.
.DESCRIPTION
    Tests TCP and UDP connectivity to required service endpoints.
    Outputs a JSON array of test results to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Port list audited against Canopy connections.csv (the canonical Pixellot
    # port reference). Notes:
    #  - prod-echo.pixellot.tv covers TCP 443 + UDP 123/443/2088 per the CSV;
    #    we hit those specific subdomain entries in addition to the wider
    #    pixellot.tv apex test (some venues filter on FQDN, not IP).
    #  - scorebot.sportzcast.net binds to TCP 1400–1405 for ScoreConnect; the
    #    range is venue-dependent so every port is marked optional. Not all
    #    schools have ScoreConnect.
    # Discover the VPU's configured DNS server so the DNS check tests the
    # resolver the box actually uses — not a hardcoded public IP like 8.8.8.8,
    # which locked-down venue networks block by design (the VPU resolves names
    # through the venue's internal DNS instead).
    $primaryDns = $null
    try {
        $primaryDns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
            ForEach-Object { $_.ServerAddresses } |
            Where-Object { $_ -and -not $_.StartsWith('127.') -and -not $_.StartsWith('169.254.') } |
            Select-Object -First 1
    }
    catch { }

    $portTests = @(
        # Required — core Pixellot streaming + cloud services
        @{ protocol = 'TCP'; port = 443;  host = 'pixellot.tv';            purpose = 'Pixellot';          optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'prod-echo.pixellot.tv';  purpose = 'Pixellot Echo';     optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'nfhsnetwork.com';        purpose = 'NFHS Network';      optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 's3.amazonaws.com';       purpose = 'AWS S3';            optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'service.singular.live';  purpose = 'Singular Overlay';  optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'logmein.com';            purpose = 'LogMeIn';           optional = $false }
        @{ protocol = 'UDP'; port = 123;  host = 'prod-echo.pixellot.tv';  purpose = 'NTP';               optional = $false }
        @{ protocol = 'UDP'; port = 443;  host = 'prod-echo.pixellot.tv';  purpose = 'Zixi QUIC';         optional = $false }
        @{ protocol = 'UDP'; port = 2088; host = 'prod-echo.pixellot.tv';  purpose = 'Zixi Streaming';    optional = $false }
        # Optional — RTMP fallback (legacy ingest)
        @{ protocol = 'TCP'; port = 1935; host = 'sportzcast.net';         purpose = 'RTMP Ingest';       optional = $true }
        # Optional — Sportzcast Scorebot range (ScoreConnect deployments only)
        @{ protocol = 'TCP'; port = 1400; host = 'scorebot.sportzcast.net'; purpose = 'Scorebot';         optional = $true }
        @{ protocol = 'TCP'; port = 1401; host = 'scorebot.sportzcast.net'; purpose = 'Scorebot';         optional = $true }
        @{ protocol = 'TCP'; port = 1402; host = 'scorebot.sportzcast.net'; purpose = 'Scorebot';         optional = $true }
        @{ protocol = 'TCP'; port = 1403; host = 'scorebot.sportzcast.net'; purpose = 'Scorebot';         optional = $true }
        @{ protocol = 'TCP'; port = 1404; host = 'scorebot.sportzcast.net'; purpose = 'Scorebot';         optional = $true }
        @{ protocol = 'TCP'; port = 1405; host = 'scorebot.sportzcast.net'; purpose = 'Scorebot';         optional = $true }
    )

    # DNS reachability against the *configured* resolver (prepended so it
    # leads the list). Skipped — not failed — when no resolver is configured;
    # a missing/broken resolver still surfaces via the domain-resolution tests.
    if ($primaryDns) {
        $portTests = @(
            @{ protocol = 'UDP'; port = 53; host = $primaryDns; purpose = 'DNS'; optional = $false }
        ) + $portTests
    }

    $results = foreach ($test in $portTests) {
        $status = 'fail'

        if ($test.protocol -eq 'TCP') {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connect = $tcp.BeginConnect($test.host, $test.port, $null, $null)
                $waited = $connect.AsyncWaitHandle.WaitOne(3000, $false)
                if ($waited -and $tcp.Connected) {
                    $tcp.EndConnect($connect)
                    $status = 'pass'
                }
                $tcp.Close()
            }
            catch {
                $status = 'fail'
            }
        }
        elseif ($test.protocol -eq 'UDP' -and $test.port -eq 123) {
            # Real NTP UDP test — send an NTP v3 client request and verify response
            try {
                $udp = New-Object System.Net.Sockets.UdpClient
                $udp.Client.ReceiveTimeout = 3000
                $udp.Client.SendTimeout = 3000
                $addr = [System.Net.Dns]::GetHostAddresses($test.host) |
                    Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                    Select-Object -First 1
                if ($addr) {
                    $ep = New-Object System.Net.IPEndPoint($addr, 123)
                    # 48-byte NTP packet: byte 0 = 0x1B (LI=0, Version=3, Mode=3 client)
                    $ntpReq = New-Object byte[] 48
                    $ntpReq[0] = 0x1B
                    $udp.Send($ntpReq, $ntpReq.Length, $ep) | Out-Null
                    $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                    $resp = $udp.Receive([ref]$remoteEP)
                    if ($resp.Length -ge 48) { $status = 'pass' }
                }
                $udp.Close()
            }
            catch {
                $status = 'fail'
            }
        }
        elseif ($test.protocol -eq 'UDP' -and $test.port -eq 53) {
            # Real DNS UDP test — send a minimal NS-root query and check for response
            try {
                $udp = New-Object System.Net.Sockets.UdpClient
                $udp.Client.ReceiveTimeout = 3000
                $udp.Client.SendTimeout = 3000
                $addr = [System.Net.Dns]::GetHostAddresses($test.host) |
                    Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                    Select-Object -First 1
                if ($addr) {
                    $ep = New-Object System.Net.IPEndPoint($addr, 53)
                    # 17-byte DNS query: ID=0x1234, flags=0x0100 (std query, RD), 1 question
                    # Name: root (.), QTYPE=NS (0x0002), QCLASS=IN (0x0001)
                    $dnsReq = [byte[]](
                        0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
                        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01
                    )
                    $udp.Send($dnsReq, $dnsReq.Length, $ep) | Out-Null
                    $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                    $resp = $udp.Receive([ref]$remoteEP)
                    # Reply needs to be at least 12 bytes (header) and echo our ID
                    if ($resp.Length -ge 12 -and $resp[0] -eq 0x12 -and $resp[1] -eq 0x34) {
                        $status = 'pass'
                    }
                }
                $udp.Close()
            }
            catch {
                $status = 'fail'
            }
        }
        elseif ($test.protocol -eq 'UDP') {
            # Generic UDP probe — send a small packet and check for ICMP port-unreachable
            # If we get a response or timeout with no rejection, consider it open
            try {
                $udp = New-Object System.Net.Sockets.UdpClient
                $udp.Client.ReceiveTimeout = 2000
                $udp.Client.SendTimeout = 2000
                $addr = [System.Net.Dns]::GetHostAddresses($test.host) |
                    Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                    Select-Object -First 1
                if ($addr) {
                    $ep = New-Object System.Net.IPEndPoint($addr, $test.port)
                    $probe = New-Object byte[] 4
                    $udp.Send($probe, $probe.Length, $ep) | Out-Null
                    try {
                        $remoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                        $resp = $udp.Receive([ref]$remoteEP)
                        # Got a response — port is open
                        $status = 'pass'
                    }
                    catch [System.Net.Sockets.SocketException] {
                        # ErrorCode 10054 = ICMP port unreachable (connection reset) — port blocked
                        # Timeout (no ICMP rejection) usually means open/filtered — treat as pass
                        if ($_.Exception.InnerException -and $_.Exception.InnerException.ErrorCode -eq 10054) {
                            $status = 'fail'
                        } else {
                            $status = 'pass'
                        }
                    }
                }
                $udp.Close()
            }
            catch {
                $status = 'fail'
            }
        }

        [ordered]@{
            protocol = $test.protocol
            port     = $test.port
            host     = $test.host
            purpose  = $test.purpose
            optional = $test.optional
            status   = $status
        }
    }

    [ordered]@{
        results = @($results)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-NetworkPorts.ps1'
    } | ConvertTo-Json -Compress
}
