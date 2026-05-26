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
    $portTests = @(
        # Required — core Pixellot services
        @{ protocol = 'TCP'; port = 443;  host = 'pixellot.tv';          purpose = 'Pixellot Cloud';    optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'nfhsnetwork.com';      purpose = 'NFHS Network';      optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'software.pixellot.tv'; purpose = 'Software Updates';  optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 's3.amazonaws.com';     purpose = 'AWS S3';            optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'app.singular.live';    purpose = 'Singular Overlay';  optional = $false }
        @{ protocol = 'TCP'; port = 443;  host = 'logmein.com';          purpose = 'LogMeIn';           optional = $false }
        @{ protocol = 'UDP'; port = 123;  host = 'prod-echo.pixellot.tv'; purpose = 'NTP';               optional = $false }
        @{ protocol = 'UDP'; port = 2088; host = 'pixellot.tv';          purpose = 'Zixi Streaming';    optional = $false }
        # Optional — SportzCast & RTMP
        @{ protocol = 'TCP'; port = 1935; host = 'live.pixellot.tv';     purpose = 'RTMP Ingest';       optional = $true }
        @{ protocol = 'TCP'; port = 1402; host = 'sportzcast.net';       purpose = 'SportzCast';        optional = $true }
    )

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
