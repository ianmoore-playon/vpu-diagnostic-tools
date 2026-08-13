# Network endpoints Pulse tests

The single reference for every host/port the Network collectors probe, why, and
where the requirement comes from. Update this whenever you add, remove, or
re-scope a network test so future audits have one place to check against.

## Sources of truth

| Source | Covers | Location |
|---|---|---|
| **`connections.csv`** | The canonical Pixellot **firewall port allowlist** (host + protocol + port). | `Resources/Canopy/Leaf/connections.csv` (the "Canopy connections.csv" referenced in the collectors). |
| **Stream-readiness policy v1** | Which ports gate the PASS/WARN/FAIL verdict (UDP/2088 hard-FAIL, TCP+UDP/443, DNS/53). | `Resources/stream-readiness-policy-v1.md` |

`connections.csv` enumerates only the ports a venue firewall must open. Pulse
intentionally tests a **superset**: it also resolves and connects to
application-layer hosts (NFHS, Singular, LogMeIn, S3) that aren't in the CSV,
because some venues filter on FQDN rather than IP and those services still need
to be reachable. Those extra hosts are marked **supporting** below; they are not
firewall-allowlist entries and shouldn't be added to `connections.csv`.

## Firewall ports — authoritative (in `connections.csv`)

| Host | Proto/Port | Purpose | Required | Tested in |
|---|---|---|---|---|
| `prod-echo.pixellot.tv` | UDP/2088 | Zixi live stream (no failover — hard FAIL if blocked) | yes | `Test-NetworkPorts.ps1` |
| `prod-echo.pixellot.tv` | UDP/443 | Zixi backup | yes | `Test-NetworkPorts.ps1` |
| `prod-echo.pixellot.tv` | TCP/443 | Pixellot Echo control | yes | `Test-NetworkPorts.ps1` |
| `prod-echo.pixellot.tv` | UDP/123 | NTP | yes | `Test-NetworkPorts.ps1` |
| `scorebot.sportzcast.net` | TCP/1400–1405 | ScoreConnect Scorebot (venue-dependent) | optional | `Test-NetworkPorts.ps1` |

## Application-layer hosts — supporting (not in `connections.csv`)

| Host | Proto/Port | Purpose | Status | Tested in |
|---|---|---|---|---|
| `pixellot.tv` | TCP/443 | Pixellot apex (FQDN-filter coverage) | current | `Test-NetworkPorts.ps1` |
| `nfhsnetwork.com` | TCP/443 | NFHS Network | current | `Test-NetworkPorts.ps1` |
| `secure.logmein.com` | TCP/443 | Remote access (the apex points at GoTo marketing; `secure.` rides the real service block) | current | `Test-NetworkPorts.ps1` |
| `service.singular.live` | TCP/443 | Singular overlay graphics | **review** — not in CSV; confirm still required | `Test-NetworkPorts.ps1` |
| `sportzcast.net` | TCP/1935 | RTMP fallback (legacy ingest) | **review** — optional/legacy, not in CSV | `Test-NetworkPorts.ps1` |
| configured resolver | UDP/53 | DNS reachability (scoped to the active-uplink resolver) | current | `Test-NetworkPorts.ps1` |

DNS name-resolution tests (`Test-NetworkDomains.ps1`, `Test-DnsResolution.ps1`)
cover the same hosts plus `software.pixellot.tv` and `www.pixellot.tv`.

## Diagnostic probe targets — NOT firewall requirements

These are reference targets for measuring reachability/latency, not endpoints a
venue must allow:

- `8.8.8.8`, `1.1.1.1`, `9.9.9.9` — internet-reachability probe (`Get-NetworkConfig.ps1`) and the Google-DNS comparison (`Test-DnsResolution.ps1`).
- `pixellot.tv` — default traceroute target (`Test-Traceroute.ps1`).

## Removed endpoints

| Host | Removed | Reason |
|---|---|---|
| `leaf-uploads.s3.amazonaws.com` | 2026-06-23 | Canopy leaf upload bucket — Canopy backend retired; no longer resolves. |
| `leaf-downloads.s3.amazonaws.com` | 2026-06-23 | Canopy leaf download bucket — same. |

> **No AMQP / port 5672, no `gocanopy.io`, and no Canopy connectivity probe** are
> tested anywhere in the collectors — confirmed by the 2026-06-23 network audit.
