#Requires -Version 5.1
<#
.SYNOPSIS
    Tests DNS resolution for required domains.
.DESCRIPTION
    Resolves each domain and returns the first IP or a failure status.
    Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    $domains = @(
        'nfhsnetwork.com'
        'pixellot.tv'
        'software.pixellot.tv'
        'sportzcast.net'
        'app.singular.live'
        'logmein.com'
        's3.amazonaws.com'
        'leaf-uploads.s3.amazonaws.com'
        'leaf-downloads.s3.amazonaws.com'
    )

    $results = foreach ($domain in $domains) {
        $resolvedTo = $null
        $status = 'fail'
        $resolutionMs = $null

        try {
            # DnsOnly avoids slow LLMNR/NetBIOS fallback; 3s timeout via wrapper
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $dns = Resolve-DnsName -Name $domain -Type A -DnsOnly -ErrorAction Stop
            $sw.Stop()
            $resolutionMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)

            $ipRecord = $dns | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1
            if ($ipRecord) {
                $resolvedTo = $ipRecord.IPAddress
                $status = 'pass'
            }
            else {
                # May have CNAME only; grab whatever resolved
                $anyRecord = $dns | Select-Object -First 1
                if ($anyRecord -and $anyRecord.IPAddress) {
                    $resolvedTo = $anyRecord.IPAddress
                    $status = 'pass'
                }
                elseif ($anyRecord -and $anyRecord.NameHost) {
                    $resolvedTo = $anyRecord.NameHost
                    $status = 'pass'
                }
            }
        }
        catch {
            if ($sw -and $sw.IsRunning) { $sw.Stop() }
            if ($sw) { $resolutionMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1) }
            $status = 'fail'
        }

        [ordered]@{
            domain       = $domain
            resolvedTo   = $resolvedTo
            status       = $status
            resolutionMs = $resolutionMs
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
        script  = 'Test-NetworkDomains.ps1'
    } | ConvertTo-Json -Compress
}
