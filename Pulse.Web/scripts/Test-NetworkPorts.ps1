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
        @{ protocol = 'TCP'; port = 443; host = 'pixellot.tv';        purpose = 'Pixellot Cloud';    optional = $false }
        @{ protocol = 'TCP'; port = 443; host = 'nfhsnetwork.com';    purpose = 'NFHS Network';      optional = $false }
        @{ protocol = 'TCP'; port = 443; host = 'software.pixellot.tv'; purpose = 'Software Updates'; optional = $false }
        @{ protocol = 'TCP'; port = 443; host = 's3.amazonaws.com';   purpose = 'AWS S3';            optional = $false }
        @{ protocol = 'TCP'; port = 443; host = 'app.singular.live';  purpose = 'Singular Overlay';  optional = $false }
        @{ protocol = 'TCP'; port = 443; host = 'balena-cloud.com';   purpose = 'Balena Cloud';      optional = $false }
        @{ protocol = 'TCP'; port = 53;  host = '8.8.8.8';           purpose = 'Google DNS';         optional = $false }
        @{ protocol = 'UDP'; port = 123; host = 'pool.ntp.org';      purpose = 'NTP';                optional = $false }
        @{ protocol = 'TCP'; port = 443; host = 'logmein.com';       purpose = 'LogMeIn';            optional = $true }
        @{ protocol = 'TCP'; port = 1402; host = 'sportzcast.net';   purpose = 'SportzCast';         optional = $true }
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
            # For UDP NTP, verify DNS resolution as a proxy test
            try {
                $resolved = Resolve-DnsName -Name $test.host -ErrorAction Stop
                if ($resolved) {
                    $status = 'pass'
                }
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
