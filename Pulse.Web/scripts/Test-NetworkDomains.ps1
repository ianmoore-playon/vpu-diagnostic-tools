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
        'pixellot.stream'
        'pixellot.tv'
        'software.pixellot.tv'
        'sportzcast.net'
        'app.singular.live'
        'balena-cloud.com'
        'logmein.com'
        's3.amazonaws.com'
        'leaf-uploads.s3.amazonaws.com'
        'leaf-downloads.s3.amazonaws.com'
    )

    $results = foreach ($domain in $domains) {
        $resolvedTo = $null
        $status = 'fail'

        try {
            # DnsOnly avoids slow LLMNR/NetBIOS fallback; 3s timeout via wrapper
            $dns = Resolve-DnsName -Name $domain -Type A -DnsOnly -ErrorAction Stop
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
            $status = 'fail'
        }

        [ordered]@{
            domain     = $domain
            resolvedTo = $resolvedTo
            status     = $status
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
