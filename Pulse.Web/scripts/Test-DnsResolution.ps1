#Requires -Version 5.1
<#
.SYNOPSIS
    Resolves Pixellot domains via the configured DNS server AND via Google DNS
    (8.8.8.8) so a misconfigured school resolver can be detected.
.DESCRIPTION
    Per Pixellot Troubleshooting Tips PDF #10, the standard DNS triage is to
    compare `nslookup www.pixellot.tv` (system resolver) with
    `nslookup www.pixellot.tv 8.8.8.8`. If Google resolves but the system
    doesn't, the school's internal DNS is blocking Pixellot infrastructure.

    For each test host the script returns:
        {
          host: <fqdn>,
          system:  { resolvedTo, status, resolutionMs, error },
          google:  { resolvedTo, status, resolutionMs, error },
          discrepancy: 'system-blocked' | 'google-blocked' | 'mismatch' | null
        }
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Hosts that must resolve consistently across resolvers. Includes the
# specific "www" hosts called out in the PDF plus the apex domains we
# already test elsewhere.
$testHosts = @(
    'www.pixellot.tv',
    'pixellot.tv',
    'software.pixellot.tv',
    'nfhsnetwork.com'
)

function Resolve-Once {
    param(
        [string]$Name,
        [string]$Server = $null   # null = use the system resolver
    )
    $out = [ordered]@{
        resolvedTo   = $null
        status       = 'fail'
        resolutionMs = $null
        error        = $null
    }
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $params = @{
            Name        = $Name
            Type        = 'A'
            DnsOnly     = $true
            ErrorAction = 'Stop'
        }
        if ($Server) { $params.Server = $Server }
        $dns = Resolve-DnsName @params
        $sw.Stop()
        $out.resolutionMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)

        $ipRecord = $dns | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1
        if ($ipRecord) {
            $out.resolvedTo = $ipRecord.IPAddress
            $out.status = 'pass'
        }
        else {
            $any = $dns | Select-Object -First 1
            if ($any) {
                if ($any.IPAddress) { $out.resolvedTo = $any.IPAddress; $out.status = 'pass' }
                elseif ($any.NameHost) { $out.resolvedTo = $any.NameHost; $out.status = 'pass' }
            }
        }
    }
    catch {
        if ($sw -and $sw.IsRunning) { $sw.Stop() }
        if ($sw) { $out.resolutionMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1) }
        $out.error = $_.Exception.Message
    }
    return $out
}

try {
    # Collect raw resolution results only. The discrepancy classification
    # (system-blocked / redirect / benign) lives in the Python backend
    # (_classify_dns_row) so the rule is in one tested place — telling a real
    # DNS redirect from benign CDN/GeoDNS load balancing needs public-vs-
    # private IP reasoning that doesn't belong in the collector.
    # $host is a PowerShell automatic variable — use a different name.
    $results = foreach ($testHost in $testHosts) {
        [ordered]@{
            host   = $testHost
            system = Resolve-Once -Name $testHost
            google = Resolve-Once -Name $testHost -Server '8.8.8.8'
        }
    }

    [ordered]@{
        googleServer = '8.8.8.8'
        results      = @($results)
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-DnsResolution.ps1'
    } | ConvertTo-Json -Compress
}
