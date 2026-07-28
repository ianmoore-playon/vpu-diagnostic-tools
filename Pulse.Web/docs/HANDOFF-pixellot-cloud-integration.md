# Handoff — Pixellot Cloud API Integration

**Status:** API discovery complete, ready to start implementation.
**Branch to create:** `feature/pixellot-cloud-source` off `dev`.
**Don't touch:** `dev` directly. This feature gates behind a settings flag so the existing Windows-VPU flow stays untouched until the user explicitly opts in.

---

## TL;DR

Pulse currently only works on Windows VPUs because all diagnostics flow through PowerShell scripts. Pixellot's Linux/Balena VPUs are unreachable — no shell access.

**Solution:** Pixellot exposes a Club API at `abe.pixellot.tv` that returns rich diagnostic data for any venue (Windows or Linux). One endpoint gives us ~60% of Pulse's diagnostic capability for Linux VPUs, and adds new fields (camera firmware, calibration, lifecycle) for Windows VPUs too.

The canonical endpoint:

```
GET https://abe.pixellot.tv/api/v3/venues/{venueId}?include=metrics
Authorization: Bearer <jwt>
```

Returns static hardware profile + live `metrics.values` object in one shot.

---

## Why this matters

| Audience | Current state | After this work |
|----------|---------------|-----------------|
| Tech inspecting a Windows VPU | 100% of Pulse | 100–115% (gains: camera firmware, calibration date, dongle ID, lifecycle, install date) |
| Tech inspecting a Linux VPU | **0% — tool doesn't work** | ~60% (full triage capability, just no Windows-specific deep dives) |
| Pixellot fleet engineer cross-venue | N/A | Fleet view becomes possible |

This is the most leveraged architectural change available right now. See `docs/HANDOFF-pixellot-cloud-integration-notes.md` for the full rationale (this file's appendix below).

---

## The API surface — confirmed working

### Authentication

```
POST https://abe.pixellot.tv/api/v3/auth/login
Content-Type: application/json
{
  "email": "user@example.com",
  "password": "..."
}
```

**Response (200):**

```json
{
  "data": {
    "id": "...",
    "type": "user",
    "attributes": {
      "email": "...",
      "tenants": ["playOnPoly"],
      "role": "accountadmin",
      "fullName": "...",
      "permissions": {
        "allowDefaultDemoContent": true,
        "allowOtherPublicEvents": true,
        "allowVideoApi": false,
        "allowSystemsManagement": false
      }
    }
  },
  "token": "eyJ..."
}
```

The token is a JWT (RS256), with no explicit `exp` claim — Pixellot manages session expiry server-side. Pattern from PDF docs suggests 24h, but observe in practice.

**Important note about permissions:** `accountadmin` with `allowSystemsManagement: false` IS sufficient to fetch venues + metrics via `?include=metrics`. The flag must gate other endpoints (TBD).

### Venue + live metrics — THE endpoint

```
GET https://abe.pixellot.tv/api/v3/venues/{venueId}?include=metrics
Authorization: Bearer <token>
```

**Response shape (200):**

```json
{
  "data": {
    "id": "...",
    "name": "PXLS2_16310 National Trail (OH) Field",
    "tenant": "playOnPoly",
    "region": "us-east-1",
    "country": "US",
    "city": "Fairborn",
    "manufacturingDate": "",
    "pixellotPN": "PXL-537-0104",
    "pixellotSN": "LEM68-...",
    "swVersion": "5.13.6",
    "systemType": "S2" | "S3",
    "hwInfo": {
      "intelCpuName": "...",
      "intelGpuName": "...",
      "nvidiaGpuName": "...",
      "nvidiaDriverVersion": "...",
      "oemName": "HP",
      "oemProductName": "HP EliteDesk 800 G4 WKS TWR",
      "oemSerialNumber": "...",
      "poeSerialNumbers": ["PCI\\VEN_8086&...003064FFFF685C6E00", ...],   // 4 entries, one per camera-facing NIC
      "disksSerialNumbers": [...],
      "baseboardSerialNumber": "...",
      "totalMachineRamSize": "32587388 kB",
      "windowsLicenseSerialNumber": "RKW9C-..."   // ⚠️ STRIP THIS
    },
    "dongleIdentifier": "00-30-64-68-5C-6F",
    "cameraHeadInfo": {
      "partNumber": "PXL-422-3580",
      "headType": "2x80x0004_3840x2160",
      "chosenFps": 25,
      "headCameras": [
        {
          "type": "DYNACOLOR" | "Pixellot",
          "uid": "rtsp:////169.254.16.50/h264",
          "firmware": "px20221027T2",
          "version": "T2SF-B_PX02",
          "macAddress": "00:D0:89:1A:CC:36",
          "revision": "T2SF-B_0_3611",
          "ip": "169.254.16.50"
        },
        ...
      ],
      "pairingStatus": "success" | "unknown" | "failed"
    },
    "graphicsInfo": {
      "scoreboardType": "SPORTZCAST" | "NONE",
      "cmsScoreboardCalibration": false,
      "backupFullPIPConfigured": true
    },
    "metrics": {
      "venueId": "...",
      "systemRole": "vpu",
      "status": "Sleep" | "Live" | "Offline" | "Reset" | "Maintenance",
      "values": {
        "cpu":                 { "value": 7.42, "severity": "Ok", "timestamp": 1773047132 },
        "gpu":                 { "value": 0, "severity": "Ok", "timestamp": 1773047132 },
        "camera":              { "value": 1000000000, "severity": "Ok", "timestamp": 1773047132 },
        "health":              { "value": -1, "severity": "Error", "timestamp": 1779870987 },
        "status":              { "value": 2, "severity": "Warning", "timestamp": 1779867641140, "description": "Sleep" },
        "darkCourt":           { "value": -1, "severity": "Error", "timestamp": 1658908249 },
        "connection":          { "value": 1, "severity": "Ok", "timestamp": 1779730650981 },
        "hdBandwidth":         { "value": -1, "severity": "Error", "timestamp": 1775333615 },
        "hdAudioVolume":       { "value": -1, "severity": "Error", "timestamp": 1779870987 },
        "panoBandwidth":       { "value": -1, "severity": "Error", "timestamp": 1614748845 },
        "panoAudioVolume":     { "value": -1, "severity": "Error", "timestamp": 1779870987 },
        "cpuTemperature":      { "value": 27.8, "severity": "Error", "timestamp": 1779867609 },    // ⚠️ see below — severity is unreliable
        "scoreboardData":      { "value": -1, "severity": "Error", "timestamp": 1779870987 },
        "scoreboardConnection":{ "value": -1, "severity": "Error", "timestamp": 1779870987 },
        "audioIndication":     { "value": -1, "severity": "Error", "timestamp": 1779870987 },
        "hardDriveAvailableMB":{ "value": 52070, "severity": "Ok", "timestamp": 1773047132 }
      },
      "createdAt": "2021-03-03T07:17:57.614Z",
      "updatedAt": "2026-05-27T08:36:59.886Z",
      "statusChangedAt": "2026-05-25T17:37:30.985Z"
    },
    "lifecycleStatus": "Production",
    "systemInstalledAt": "2021-10-18T21:15:00.000Z",
    "labels": { "premium": false }
  }
}
```

**Important quirks observed:**

1. **`severity` is unreliable.** Example: `cpuTemperature` had `value: 27.8` (perfectly healthy) and `timestamp: today` (fresh reading) — but `severity: "Error"`. Treat `severity` as advisory only. **Derive severity locally from `value` + thresholds**, same as `_compute_findings` does today.

2. **Timestamps are mixed units.** Most are Unix seconds. `status.timestamp` is Unix milliseconds. `connection.timestamp` is Unix milliseconds. Detect by magnitude: > 1e12 = ms, else seconds.

3. **Staleness is metric-by-metric, not uniform.** Some metrics update every few seconds (status, connection, audio). Others only update on specific events (cpu/gpu/disk seem tied to streaming activity). `panoBandwidth` on a Sleep-mode VPU had a 5-year-old timestamp.

4. **`value: -1`** is the API's sentinel for "no current reading." Combined with stale timestamps, it means "not currently being measured." NOT "broken."

### Other endpoints tested

| URL | Result |
|-----|--------|
| `GET /api/v3/venues/{id}/metrics` | **500 Internal Server Error** — endpoint exists but Pixellot's backend crashes |
| `GET /api/v3/venues/{id}/status` | Not tested — likely 500 or 404 |
| `GET /api/v3/monitoring/systemsMetrics?criteria=...` | Not tested |
| `GET /api/v3/systemMetrics?venueId=...` | Not tested |
| `GET /api/v3/venues?limit=N&tenant=playOnPoly` | **Works** — venue listing |

**Use `?include=metrics`. Don't bother with the others.**

### Endpoints that DON'T work (despite the PDF claiming they do)

The PDF `SystemMetrics API Integration Guide.pdf` references `https://api.pixellot.tv/v1/*` and `https://api.stage.pixellot.tv/v1/*`. All paths under those hosts return 404. The PDF is either outdated, partner-tier only, or aspirational. **Ignore it for the Club API integration.**

---

## Self-identification: how Pulse knows which venue is "this VPU"

The `dongleIdentifier` field is one of the MACs in `poeSerialNumbers`. Both formats let us correlate:

| Field | Value example | Format |
|-------|---------------|--------|
| `dongleIdentifier` | `00-30-64-68-5C-6F` | Dashed MAC |
| `poeSerialNumbers[2]` | `PCI\VEN_8086&...003064FFFF685C6F00` | Embedded in PCI path |

Strip non-hex from `poeSerialNumbers` entries and they're recognizable MACs (drop the `003064FFFF` prefix and trailing `00`, you get `685C6F` — last 6 of the dashed dongleIdentifier).

**Implementation:**

1. On first launch (or first cloud-mode enable), Pulse reads local NIC MACs via `Get-NicAdapters.ps1`.
2. Calls `GET /api/v3/venues?tenant={user_tenant}&limit=N` to list venues the user can see.
3. For each venue, fetches `?include=metrics` and compares `dongleIdentifier` (and/or parses `poeSerialNumbers`) against local MACs.
4. Match → cache `venueId` in `pulse-settings.json`.
5. Defensive: on every subsequent fetch, sanity-check MACs still match.

For Linux VPUs (where we can't read local NIC MACs), fall back to manual entry of `venueId` in Settings.

---

## Field → Pulse tab mapping

### Static fields

| Cloud field | Pulse tab/element |
|-------------|---------------------|
| `name` | Dashboard VPU name (matches `BROADCAST_NAME` from agent logs) |
| `id` | Internal — store as venueId |
| `dongleIdentifier` | VPU Identity card |
| `tenant`, `region`, `country`, `city` | VPU Identity — new section |
| `pixellotPN`, `pixellotSN` | VPU Identity — Pixellot-side IDs |
| `swVersion` | Pixellot Software card |
| `systemType` | System Overview — generation badge (S2/S3) |
| `lifecycleStatus` | System Overview — lifecycle banner |
| `systemInstalledAt` | System Overview |
| `manufacturingDate` | System Overview |
| `hwInfo.oemName/oemProductName/oemSerialNumber` | VPU Identity (replaces local WMI source) |
| `hwInfo.intelCpuName` | System Overview — CPU |
| `hwInfo.intelGpuName`, `nvidiaGpuName`, driver versions | System Overview — GPU (new) |
| `hwInfo.totalMachineRamSize` | System Status memory total |
| `hwInfo.poeSerialNumbers` | Camera Connectivity NIC mapping |
| `hwInfo.disksSerialNumbers`, `baseboardSerialNumber` | System Overview |
| `hwInfo.windowsLicenseSerialNumber` | **STRIP — never display, never log** |
| `cameraHeadInfo.partNumber`, `headType`, `chosenFps` | Camera Connectivity — head card |
| `cameraHeadInfo.headCameras[]` (firmware, IP, MAC, revision) | Camera Connectivity — per camera |
| `cameraHeadInfo.pairingStatus` | Camera Connectivity — finding if not "success" |
| `graphicsInfo.scoreboardType` | Score Connect |

### Dynamic fields (`metrics.values`)

| Cloud field | Pulse tab/gauge | Notes |
|-------------|------------------|-------|
| `status` (Live/Sleep/Offline/Reset/Maintenance) | NEW Dashboard "stream state" badge | No local equivalent today |
| `health` | Dashboard severity rollup | Cloud's overall opinion |
| `connection` | Internet/connection tile | Cross-check with local probe |
| `cpu`, `cpuTemperature` | Dashboard CPU + Temp gauges | Cloud as fallback when local unavailable |
| `gpu` | NEW GPU gauge | |
| `hardDriveAvailableMB` | Storage section | Total free only |
| `camera` (numeric, looks like bandwidth) | Camera Connectivity | |
| `darkCourt` | Camera Connectivity finding | Pixellot-specific |
| `hdBandwidth`, `panoBandwidth` | Camera Connectivity / Network — stream bandwidth | |
| `hdAudioVolume`, `panoAudioVolume`, `audioIndication` | Audio tab | Direct levels |
| `scoreboardConnection`, `scoreboardData` | Score Connect tab | |

---

## Auth model — per-user credentials

Decided in the previous chat:

- **Each support employee uses their own Pixellot Club login.** No shared service account.
- On first launch, Pulse shows a credential entry form. User types email + password.
- Token + (optionally encrypted password for refresh) stored via Windows **DPAPI** (per-user OS-level encryption, no plaintext on disk).
- On 401, Pulse silently re-auths.
- If re-auth fails (password changed, account locked), Pulse falls back to **local-only mode** and surfaces a finding: `[Pulse] Pixellot Club session expired — sign in again`.
- Settings tab has a "Pixellot Club account" section showing email + Sign Out button.

Why per-user creds over service account:
- Real audit attribution per call
- Inherits user's existing permission scope
- No "Pixellot conversation" required
- Offboarding is automatic
- One leak = one user, not the fleet

**Known constraint:** if Pixellot Club enforces MFA, programmatic password auth may break. Test before committing. As of this writing, MFA does NOT block `POST /api/v3/auth/login` — confirmed with a real login.

---

## Security non-negotiables

1. **Never display, never log `windowsLicenseSerialNumber`.** Strip on ingest.
2. **Never log Authorization headers.** Pulse already writes to `pulse-server.log`; add a redactor that scrubs `Authorization: Bearer <...>` and `"token": "<...>"` patterns before logging.
3. **Use DPAPI on Windows** for credential storage. Python `ctypes` can call `CryptProtectData` / `CryptUnprotectData` — no new dependencies needed.
4. **Don't bake credentials into the installer.** Each tech enters their own.
5. **On Mac/Linux dev (DEMO_MODE), prompt for creds normally** — DPAPI is Windows-only; on macOS use Keychain via `keyring` package, or fall back to a permission-restricted JSON file in `~/.config/pulse/`.
6. **MAC addresses are PII-adjacent** — they identify physical hardware. Don't leak them in logs that ship to engineering by default.

---

## Implementation plan

### Phase 1: Standalone client module (no UI yet)

Create `Pulse.Web/app/pixellot_cloud.py`:

```python
class PixellotCloudClient:
    def __init__(self, token_store: TokenStore): ...
    async def login(self, email: str, password: str) -> None: ...
    async def fetch_venue(self, venue_id: str) -> dict: ...     # uses ?include=metrics
    async def list_venues(self, tenant: str, limit: int = 50) -> list[dict]: ...
    async def find_venue_for_macs(self, macs: list[str]) -> str | None: ...

class TokenStore:
    """DPAPI on Windows, Keychain on macOS, restricted file fallback."""
    def get_token(self) -> str | None: ...
    def set_token(self, token: str) -> None: ...
    def get_credentials(self) -> tuple[str, str] | None: ...
    def set_credentials(self, email: str, password: str) -> None: ...
    def clear(self) -> None: ...
```

### Phase 2: Data normalization

Create `Pulse.Web/app/pixellot_normalize.py`:

- Convert cloud `metrics.values` into Pulse's internal shape
- Per-metric staleness check: if `now - timestamp > THRESHOLDS[metric]`, mark as `unavailable`
- Recompute severity from value (ignore cloud severity)
- Output matches what `_build_dashboard()` and friends already consume

Suggested staleness thresholds (tweak after observing live VPUs):

| Metric | Stale after |
|--------|-------------|
| status, health, connection | 5 min |
| cpu, gpu, cpuTemperature | 10 min |
| hardDriveAvailableMB | 1 hour |
| hdBandwidth, panoBandwidth, audioIndication, hdAudioVolume, panoAudioVolume | only valid while streaming — treat as "unavailable when status != Live" |
| scoreboardConnection, scoreboardData | only valid when streaming + scoreboard configured |
| darkCourt | only updated during games — long-stale is normal |

### Phase 3: Integration into main.py

- New `data_source` field on each `_build_*` function: `"local"` | `"cloud"` | `"hybrid"`
- Settings flag `cloudSource: "off" | "augment" | "primary"`:
  - `off` (default): today's behavior, Windows-PS-only
  - `augment`: Windows uses local + cross-checks with cloud where available
  - `primary`: cloud is the source of truth (for Linux VPUs or when local fails)
- New endpoints:
  - `POST /api/cloud/login` — user submits credentials
  - `POST /api/cloud/logout` — clear stored creds
  - `GET /api/cloud/status` — show current connection state
  - `GET /api/cloud/venues` — list user-visible venues for first-time mapping
  - `POST /api/cloud/venue/:id/select` — set the active venueId

### Phase 4: UI

- Settings → "Pixellot Club Account" section with sign-in form, status badge, sign-out button
- Dashboard banner if cloud session is broken: `Sign in to Pixellot Club to enable cloud diagnostics`
- All tabs get a small "source" indicator next to data sourced from cloud vs local
- A "data freshness" indicator on the cloud-sourced metrics (e.g., "Updated 2 minutes ago")

### Phase 5: First-launch wizard (for Linux + new installs)

- Detect: no local Pixellot stack → assume cloud-only mode
- Prompt for credentials
- Auto-discover venue via MAC matching (Windows) or manual entry (Linux)

---

## Open questions / TBD

| Question | How to resolve |
|----------|----------------|
| Live-status VPU response shape | Find a venue with `status: "Live"` and re-pull. Should populate hdBandwidth, panoBandwidth, audio metrics with real values + fresh timestamps. |
| Exact token expiry | Observe over a few hours — re-attempt a request periodically until 401. |
| Rate limits | Start conservative (poll every 2–5 min per venue, max 20 venues at once). Observe headers for `X-RateLimit-*`. |
| Whether the same endpoint works for S3 (potentially Linux) VPUs | Try `?include=metrics` against a known-Linux venue. The PXLS3 test venue returned 500 on `/metrics` and the static-only fields seemed to work — but we never saw `metrics.values` from an S3. |
| Pano vs HD camera mapping | The `camera` numeric value (1000000000) needs interpretation. May be bandwidth in bits/sec (1 Gbps?). Confirm with a Live VPU. |
| Webhook integration | Out of scope for v1. Polling-only. Webhooks require a public endpoint Pulse doesn't have. Future: centralized PlayOn-hosted broker could receive webhooks and push to local Pulse over WS. |

---

## What NOT to do

- Don't replace the PowerShell-based path. The cloud is a supplement (or fallback for Linux), not a replacement.
- Don't store credentials in plaintext.
- Don't trust cloud `severity` — derive locally.
- Don't display `windowsLicenseSerialNumber`.
- Don't poll the API faster than every 60 seconds per venue. Start at 5-minute intervals; tighten only if Pixellot's behavior allows.
- Don't ship without a "disconnect / clear credentials" path in Settings.

---

## Recommended starting move

```bash
git checkout dev
git pull origin dev
git checkout -b feature/pixellot-cloud-source
mkdir -p Pulse.Web/app
# Create pixellot_cloud.py with the client class and a simple CLI test
```

A standalone CLI test (no Pulse server required) is the fastest way to validate the client works end-to-end:

```bash
# After implementation:
python -m pulse_web.app.pixellot_cloud login --email "..." --password "..."
python -m pulse_web.app.pixellot_cloud venues --tenant playOnPoly
python -m pulse_web.app.pixellot_cloud venue 603f38150d2eb332be059295
```

Then integrate into main.py once the client is solid.

---

## Test venues confirmed working

| venueId | name | systemType | tenant | Notes |
|---------|------|------------|--------|-------|
| `5def94cd242f712688c04616` | PXL_8150 PlayOn Lab - T3 Test VPU #2 (W10) | S2 | playOnPoly | Sleep mode, Windows 10 test VPU in Denver |
| `603f38150d2eb332be059295` | PXLS2_16310 National Trail (OH) Field | S2 | playOnPoly | Sleep mode, real customer venue, OH |
| `6a1694303dc2cf99d84bfe6e` | PXLS3_39293 | S3 | playOnPoly | Israeli test venue, `/metrics` returned 500 on this one |

Use the National Trail one for development — it's the most representative (real customer, regularly active).

---

## Contact and current state

- Beta testing of Pulse 0.1.0-dev is starting separately on `dev` branch — don't disrupt.
- The Windows VPU codepath stays default. Cloud integration is opt-in via settings flag.
- Audio session and System Tabs sessions are also working on `dev` — coordinate before touching `_compute_findings` or `_build_dashboard` in main.py.
- Existing docs: `Pulse.Web/docs/HOW-TO-USE.md` is the user-facing guide; reference it when designing the Pixellot Club sign-in UX.
