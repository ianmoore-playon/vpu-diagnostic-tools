#Requires -Version 5.1
<#
.SYNOPSIS
    Detects SSL/TLS interception (firewall certificate substitution) on the
    HTTPS services Pixellot depends on.
.DESCRIPTION
    Completes a real TLS handshake to each service while accepting ANY
    certificate, captures the certificate the far end actually presented, then
    validates that certificate against the VPU's own trust store. A cert that
    doesn't chain to a trusted root means a middlebox (a school firewall doing
    SSL deep-packet inspection) is substituting its own certificate — the
    failure mode where video streams fine but Singular graphics never load,
    because the graphics data channel correctly rejects the firewall's cert.
    Field-proven signature: Kent School District 2026-07 — the district's DPI
    bypass covered only *.app.singular.live, so datastream.singular.live got a
    "KSD-FW1-DPI" cert and overlays died at every school in the district.
    Plain reachability tests can't see this (TCP/443 connects fine), which is
    why this check exists alongside Test-NetworkPorts. Outputs JSON to stdout.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    # Known-HTTPS endpoints only. prod-echo.pixellot.tv:443 is intentionally
    # absent — it's a Zixi tunnel, not TLS, and would false-fail the handshake.
    # The full singular.live family is listed host-by-host because DPI bypass
    # lists are scoped by pattern; at Kent, *.app.singular.live was exempt while
    # datastream/api/apex were still decrypted — only per-host checks catch a
    # partial bypass. www.python.org is the Pulse installer's own download
    # source (its SEC_E_UNTRUSTED_ROOT failure is the same root cause).
    $targets = @(
        @{ domain = 'singular.live';            purpose = 'Singular graphics (apex)' }
        @{ domain = 'app.singular.live';        purpose = 'Singular graphics app' }
        @{ domain = 'api.singular.live';        purpose = 'Singular graphics API' }
        @{ domain = 'datastream.singular.live'; purpose = 'Singular graphics data feed' }
        @{ domain = 'service.singular.live';    purpose = 'Singular overlay service' }
        @{ domain = 'pixellot.tv';              purpose = 'Pixellot cloud' }
        @{ domain = 'software.pixellot.tv';     purpose = 'Pixellot software updates' }
        @{ domain = 'nfhsnetwork.com';          purpose = 'NFHS Network' }
        @{ domain = 's3.amazonaws.com';         purpose = 'Recording uploads (AWS S3)' }
        @{ domain = 'secure.logmein.com';       purpose = 'Remote support (LogMeIn)' }
        @{ domain = 'www.python.org';           purpose = 'Pulse installer download' }
    )

    $results = foreach ($t in $targets) {
        $status = 'blocked'; $detail = $null
        $issuer = $null; $issuerCn = $null; $issuerOrg = $null; $subjectCn = $null
        $trusted = $null; $chainErrors = $null; $notAfter = $null
        $tcp = $null; $ssl = $null
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connect = $tcp.BeginConnect($t.domain, 443, $null, $null)
            $waited = $connect.AsyncWaitHandle.WaitOne(4000, $false)
            if (-not ($waited -and $tcp.Connected)) {
                $detail = 'TCP connect to 443 timed out or was refused'
            }
            else {
                $tcp.EndConnect($connect)

                # Accept every certificate during the handshake — validation is
                # done explicitly below, so an intercepted (untrusted) cert is
                # CAPTURED and reported instead of just aborting the handshake.
                # Clone in the callback: SslStream may dispose its copy after.
                $script:PresentedCert = $null
                $cb = {
                    param($sender, $cert, $chain, $errors)
                    if ($cert) {
                        $script:PresentedCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
                    }
                    return $true
                }
                $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $cb)
                $ssl.ReadTimeout = 6000
                $ssl.WriteTimeout = 6000
                try {
                    # No explicit SslProtocols: the parameterless overload takes
                    # the OS schannel defaults, matching what Pixellot's own
                    # clients negotiate on this box.
                    $ssl.AuthenticateAsClient($t.domain)
                }
                catch {
                    # Even with an accept-all callback the handshake can die
                    # (RST mid-handshake, protocol downgrade tampering) — the
                    # same SSPI/schannel failures Kent showed on the decrypted
                    # singular.live hosts. Classified below only if no cert was
                    # captured; with a cert in hand we can still judge trust.
                    $inner = $_.Exception
                    while ($inner.InnerException) { $inner = $inner.InnerException }
                    $detail = $inner.Message
                    $status = 'handshake-fail'
                }

                if ($script:PresentedCert) {
                    $cert2 = $script:PresentedCert
                    $issuer = $cert2.Issuer
                    $issuerCn = $cert2.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $true)
                    $subjectCn = $cert2.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
                    if ($cert2.Issuer -match '(?:^|,\s*)O=("[^"]*"|[^,]+)') {
                        $issuerOrg = $Matches[1].Trim('"')
                    }
                    $notAfter = $cert2.NotAfter.ToString('yyyy-MM-dd')

                    # Validate against the VPU's trust store. Revocation is
                    # skipped: it needs its own outbound lookups (often blocked
                    # on these same networks) and isn't the signal — chain
                    # trust is.
                    $x509chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                    $x509chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
                    $built = $x509chain.Build($cert2)
                    $statuses = @($x509chain.ChainStatus | ForEach-Object { $_.Status.ToString() })
                    $chainErrors = $statuses -join ', '
                    $x509chain.Reset()

                    # ANY time-related chain status is NOT interception: a
                    # wrong VPU clock (or a genuinely expired cert) fails the
                    # date check, and an expired cert also drags in
                    # PartialChain — its expired issuer can't be resolved — so
                    # requiring time-ONLY would misread it as interception
                    # (verified against expired.badssl.com). DPI certs are
                    # minted on the fly with fresh validity, so a genuinely
                    # intercepted connection never shows NotTimeValid. Keep it
                    # a distinct status so techs chase the clock, not the
                    # firewall.
                    $timeInvolved = [bool]($statuses | Where-Object { $_ -in @('NotTimeValid', 'NotTimeNested') })

                    if ($built) { $status = 'pass'; $trusted = $true }
                    elseif ($timeInvolved) { $status = 'cert-time'; $trusted = $false }
                    else {
                        # UntrustedRoot / PartialChain: the presented chain
                        # doesn't reach a trusted root — certificate
                        # substitution by an inspecting middlebox.
                        $status = 'intercepted'; $trusted = $false
                    }
                }
            }
        }
        catch {
            # DNS failure or socket-level error before the handshake.
            $status = 'blocked'
            $detail = $_.Exception.Message
        }
        finally {
            if ($ssl) { $ssl.Dispose() }
            if ($tcp) { $tcp.Close() }
        }

        $sw.Stop()

        [ordered]@{
            domain      = $t.domain
            purpose     = $t.purpose
            status      = $status
            trusted     = $trusted
            issuer      = $issuer
            issuerCn    = $issuerCn
            issuerOrg   = $issuerOrg
            subjectCn   = $subjectCn
            chainErrors = $chainErrors
            notAfter    = $notAfter
            latencyMs   = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
            detail      = $detail
        }
    }

    # Who is intercepting — the distinct issuer identities on substituted
    # certs (e.g. "KSD-FW1-DPI (Kent School District)"). Naming the device
    # gives the district's IT team an unambiguous pointer to their own box.
    $interceptors = @(
        $results | Where-Object { $_.status -eq 'intercepted' } | ForEach-Object {
            if ($_.issuerOrg -and $_.issuerCn -ne $_.issuerOrg) { "$($_.issuerCn) ($($_.issuerOrg))" }
            elseif ($_.issuerCn) { $_.issuerCn }
            else { $_.issuer }
        } | Where-Object { $_ } | Select-Object -Unique
    )

    [ordered]@{
        results            = @($results)
        interceptorIssuers = $interceptors
    } | ConvertTo-Json -Depth 5 -Compress
}
catch {
    [ordered]@{
        error   = $true
        message = $_.Exception.Message
        script  = 'Test-TlsInspection.ps1'
    } | ConvertTo-Json -Compress
}
