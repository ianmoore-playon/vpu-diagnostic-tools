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
    'nfhsnetwork.com',
    's3.amazonaws.com'
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

function Classify-Discrepancy {
    param($Sys, $Goog)
    # If only one resolver succeeded, the other side is the problem.
    if ($Sys.status -eq 'pass' -and $Goog.status -ne 'pass') { return 'google-blocked' }
    if ($Sys.status -ne 'pass' -and $Goog.status -eq 'pass') { return 'system-blocked' }
    # Both passed but pointed at different IPs — could indicate DNS-level
    # redirection (captive portal, school filter, internal mirror).
    if ($Sys.status -eq 'pass' -and $Goog.status -eq 'pass' -and
        $Sys.resolvedTo -and $Goog.resolvedTo -and
        $Sys.resolvedTo -ne $Goog.resolvedTo) { return 'mismatch' }
    return $null
}

try {
    # $host is a PowerShell automatic variable — use a different name to avoid shadowing.
    $results = foreach ($testHost in $testHosts) {
        $sys  = Resolve-Once -Name $testHost
        $goog = Resolve-Once -Name $testHost -Server '8.8.8.8'
        [ordered]@{
            host        = $testHost
            system      = $sys
            google      = $goog
            discrepancy = Classify-Discrepancy -Sys $sys -Goog $goog
        }
    }

    # Aggregate flags so the UI can show a top-level "system DNS is broken" finding.
    $systemBlocked = @($results | Where-Object { $_.discrepancy -eq 'system-blocked' }).Count
    $mismatched    = @($results | Where-Object { $_.discrepancy -eq 'mismatch' }).Count

    [ordered]@{
        googleServer    = '8.8.8.8'
        results         = @($results)
        systemBlockedCount = $systemBlocked
        mismatchCount      = $mismatched
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-DnsResolution.ps1'
    } | ConvertTo-Json -Compress
}
