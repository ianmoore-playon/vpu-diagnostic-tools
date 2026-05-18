# Pulse — QA Checklist

A runnable, ~30-minute smoke test for any release. Pulled from the QA agent's
review, refined to match the v1.0.53-beta surface area.

Pre-flight: have the test VPU online, the Pulse.bat to hand, and a notepad
window for the result template at the bottom of this file.

---

## A. Pre-flight environment matrix

| Variable | Values to cover |
|---|---|
| OS | Win10 LTSC 1809 (oldest field VPU), Win10 22H2, Win11 |
| PowerShell | 5.1 (default Desktop edition on Pixellot VPUs) |
| Elevation | UAC-elevated (normal), unelevated (negative) |
| Pixellot install | `C:\Pixellot\` (normal), `D:\Pixellot\` (alt drive), missing entirely |
| Camera count | 2 (S2 + OCR), 4 (full 4-port), 0 (no cameras connected) |
| NIC chip | Intel I210, Intel 82574L, Intel I350 |
| Network | Online + DNS OK, offline, DNS broken only |
| Display | 1920×1080 (normal), 1366×768 (LogMeIn low-res) |

**Minimal release subset (must pass before tagging):** Win10 LTSC + PS 5.1 +
UAC + `C:\Pixellot\` + 4-camera I210 + online + 1920×1080. Plus a 1366×768
LogMeIn smoke pass.

**Comprehensive subset (quarterly):** every row of the matrix.

---

## B. Happy-path smoke (~10 min)

| # | Action | Expected | Fail signal |
|---|---|---|---|
| 1 | Double-click `Pulse.bat` on a field VPU | UAC prompt → CMD header → "Up to date" / "Updated" line | Window closes immediately, red CMD lines, "ERROR:" prefix |
| 2 | Wait for GUI | Pulse window opens at 1500×800, Home tab visible, 8-tile grid, "Run Full Diagnostic" + "Open Last Report" at the bottom | Black window, blank Home, missing tiles |
| 3 | Click each sidebar entry once | Each panel loads with correct title/subtitle and section-header pill = "Ready" | Wrong panel shown, blank center, console error toast |
| 4 | Return to Home, click **Run Full Diagnostic** | 7 module rows animate Running → resolve to Healthy / Warning / Issues / Unknown; banner appears; single summary toast at end | Any row stuck on "Waiting" or "Running" >3 min |
| 5 | Click **View** on any module row | Jumps to that panel with results populated | Lands on wrong panel, panel empty |
| 6 | Click **Open Last Report** on Home | Default text editor opens the latest `.txt` in `Pulse_Results\` | "File not found" or wrong file |
| 7 | Re-open Home, click **Run Full Diagnostic** again | Old rows reset to neutral, re-run cleanly, no double-toast | Stale state visible, duplicate toasts |
| 8 | Close Pulse window | App exits cleanly, CMD launcher window remains, exit-code line written to `launcher.log` | "exited with error (code: N)" in CMD |

---

## C. Per-panel deep tests

Format per case: **action / expected / fail signal**.

### 1. System Information

- **C1.1** Open panel cold → 6+ inventory cards populate (Model, OS, Uptime, CPU + %, RAM + %, System Drive) — *new in v1.0.53-beta: CPU% and RAM% are real measurements, not hardcoded ok* / cards stuck on "--"
- **C1.2** Click Refresh → cards re-collect, "Last Run" updates / Refresh does nothing
- **C1.3** Uptime > 180 days → Uptime card amber + warn icon *(v1.0.53-beta threshold)* / shows green at 31 days now (intentional)
- **C1.4** System drive < 15 GB free → Storage card amber; < 5 GB free → red / stays green
- **C1.5** Click Export → `.txt` written to `Pulse_Results\` and opens / silent no-op
- **C1.6** Time & Locale section shows "Clock Drift" line with measured ms value *(v1.0.53-beta new)* / no Clock Drift row

### 2. Network Configuration

- **C2.1** Open cold → Adapter, IP Config, Firewall cards populated / blank cards
- **C2.2** Click Run Network Test → Internet, Port Tests, Domain Tests cards leave "--" and reach pass/fail; live log streams / cards stuck on "--"
- **C2.3** UDP 443 and UDP 2088 tests should now show INFO (gray), not FAIL *(v1.0.53-beta demoted)* / UDP 443/2088 showing FAIL when they shouldn't
- **C2.4** Step text uses "→" arrow not literal "?" *(v1.0.53-beta polish)* / "Testing TCP 443 ? pixellot.tv..."
- **C2.5** Pull internet, re-run → Internet=FAIL, port/domain FAIL with red banner; non-English Windows test: NTP source displays correctly with localized strings *(v1.0.53-beta locale fix)*
- **C2.6** Click Copy Summary → clipboard has formatted text incl. INFO rows in gray

### 3. Camera Connectivity

- **C3.1** Open cold → NIC card label shows e.g. "ADLINK GIE74P (Intel I210 x4)"; per-port detail boxes show live link state; remote MAC + IP per port populated / NIC card blank
- **C3.2** Click Run on full 4-port rig → SmartSpeed, Ping, ARP, CHU, PoE cards resolve; port LEDs reflect link tier (1/2.5/10 Gbps all green)
- **C3.3** Disconnect an OCR camera (link down, stale ARP) → port labelled "OCR Camera (link down)" with role preserved; ping FAIL does NOT count toward main-camera failures *(v1.0.53-beta D3 fix)* / stale OCR mislabeled "Main Camera (probable)" and flagged Critical
- **C3.4** Unplug a main port → port labelled correctly, ping failure correctly attributed
- **C3.5** Fail wording test: degraded port shows "Likely cable or termination — also verify the camera revision supports gigabit and the switch port is not locked to 100M" *(v1.0.53-beta D4 softening)* / "Physical layer issue. DEGRADED cable fault." (old wording)
- **C3.6** SmartSpeed events: a single old (>4h) ID 40 → Warn with "(historical)" tag, not Fail *(v1.0.53-beta D9 recency split)* / shows Fail on historical event only
- **C3.7** Click Cancel during a long run → runspace breaks out within ~250ms instead of waiting full RenegotiateWaitSec *(v1.0.53-beta R10)* / GUI freezes during cancel
- **C3.8** PoE budget: card with 2 PoE-on ports + 50 W total budget → Pass (D8 fix), not "LOW — Check Molex" / fires "Check Molex" inappropriately

### 4. Hardware & Peripherals

- **C4.1** Open cold → GPU, Monitor, Input cards populate
- **C4.2** Section header text reads "Hardware & Peripherals" without missing `&` characters *(v1.0.53-beta UseMnemonic fix)* / "Hardware  Peripherals" with stray spaces

### 5. Pixellot Services

- **C5.1** Open cold → 6 service cards each with distinct icon
- **C5.2** Click Run on a real VPU → cards show Running/Stopped + Auto/Manual
- **C5.3** Run on a **non-VPU machine** (dev laptop) → status shows "Pixellot not detected on this machine" (neutral, *not* Critical), and FullDiagnostic Services row shows Unknown *(v1.0.53-beta D6 fix)* / shows "4 required processes not running" Critical with "Restart the missing process(es)" recommendation
- **C5.4** Stop PixellotAgent on a real VPU → Critical and clear remediation

### 6. Disk & System Health

- **C6.1** Section header reads "Disk & System Health" *(v1.0.53-beta naming drift fix — sidebar/header/tile now match)* / "System & Disk Health" mismatch
- **C6.2** On a 4 TB recording drive at 99% used → Volume card shows Critical (under 20 GB absolute floor) *(v1.0.53-beta D20)* / shows ok until 99.6% full
- **C6.3** Disk events log unreadable (stop EventLog service) → DiskErrors card shows "Log unreadable" warn, NOT "Clean (48h)" green *(v1.0.53-beta D5 fix)* / silently shows Clean / ok
- **C6.4** Without admin / on stripped LTSC → SMART card shows "SMART data unavailable" warn, NOT "All N healthy" ok *(v1.0.53-beta R6)* / silently reports healthy
- **C6.5** Run on a system with huge `C:\Pixellot\Data\Log` (millions of files) → scan respects 30 s aggregate budget; later paths show "Skipped - scan budget exceeded" *(v1.0.53-beta R17)* / runs for minutes blocking the runspace

### 7. Event Viewer

- **C7.1** A single DistributedCOM 10016 → Warning (not Critical) *(v1.0.53-beta D14)* / shows Critical
- **C7.2** A Disk or Driver error → Critical *(v1.0.53-beta D14 weights hardware-relevant events as Critical)*
- **C7.3** Stop EventLog service, run → card shows "Log unreadable" warn, not "Clean" ok *(v1.0.53-beta D15)*

### 8. Reports / Settings / Help & About

- **C8.1** Settings: theme toggle. Click "Switch to Dark/Light Mode"; if UAC cancelled, friendly modal pops up and app stays open *(v1.0.53-beta R14)* / black screen on UAC cancel
- **C8.2** Help & About: section header reads "About & Help" without `&` swallow; subtitle says "How to use Pulse and answers to common questions" (v1.0.53-beta feedback removed)
- **C8.3** Help: "Home - running a full diagnostic" copy refers to **bottom action bar**, not "top-right of the header" *(v1.0.53-beta U-polish)*
- **C8.4** Reports panel lists past runs

### 9. Home / Full Diagnostic

- **C9.1** Home tile "System Information" navigates to System Information panel *(v1.0.53-beta U1 — was "System Overview" mislabel)* / wrong target
- **C9.2** Home tile "Disk & System Health" *(v1.0.53-beta naming alignment)*
- **C9.3** Run Full Diagnostic on a VPU where one runspace crashes (simulate by Stop-Service WMI mid-run): banner reads "N of 7 checks did not complete - cannot confirm VPU health" with yellow icon, **NOT** "All 7 checks passed - this VPU appears healthy" *(v1.0.53-beta D1 fix — the trust-killer)* / false green when something didn't actually run
- **C9.4** Toast meta text says "open Network Configuration" / "Pixellot Services" / "Disk & System Health" / "Hardware & Peripherals" / "Event Viewer" — never "open Hardware tab" / "open Disks tab" *(v1.0.53-beta U4)* / nonexistent tab names

---

## D. Negative and edge cases

| # | Scenario | Expected | Fail signal |
|---|---|---|---|
| D1 | Run `Pulse.bat` unelevated (deny UAC) | Friendly MessageBox: "Pulse needs to run as Administrator…" *(v1.0.53-beta R4)* | Silent close |
| D2 | Pixellot installed on `D:\Pixellot\` | Services panel pre-gate still detects it via registry; no false Critical |
| D3 | No internet at launch | Launcher prints "Could not reach update server" + offline mode |
| D4 | One camera unplugged mid-run | Port detail box flips to No Link; diagnostic completes |
| D5 | Stop `PixellotAgent` service before Run | Services panel Critical; FullDiag Services row Issues Found |
| D6 | C: at 92% used | Volume card amber (warn), not red |
| D7 | NTP skew ≥5 min (set clock forward 10 min) | System Information "Clock Drift" line shows >5000 ms = Fail *(v1.0.53-beta D12)* |
| D8 | `Winmgmt` (WMI) service stopped | SMART card shows "SMART data unavailable" warn; module load doesn't hang the UI |
| D9 | Windows Defender quarantines downloaded zip | `Pulse.bat` halts at validation step with clear error; existing install untouched *(v1.0.53-beta R18)* |
| D10 | Fresh boot, launch within 2 min | Services panel reflects real state; no hang |
| D11 | LogMeIn 1366×768 | Sidebar + content visible; Full Diagnostic rows + bottom buttons reachable via scroll |
| D12 | Launch Pulse while another instance is open | Either 2nd opens or blocked with message; both reports dirs writable |
| D13 | Empty / corrupt `settings.json` (zero bytes / garbage JSON) | Treated as defaults, no exception |
| D14 | **Atomic-swap test:** kill the install mid-download (e.g. unplug network) | Existing `%InstallDir%` is left intact; staged zip discarded; next launch still works *(v1.0.53-beta R18)* | install dir wiped + new content missing |
| D15 | Cancel during Camera Connectivity diagnostic | Stops within ~250 ms instead of waiting full RenegotiateWaitSec *(v1.0.53-beta R10)* |

---

## E. Release-blocking regressions

Run each on the minimal smoke rig; all must pass before tagging release.

| # | Source | Test | Expected |
|---|---|---|---|
| E1 | v1.0.40 | Full Diagnostic completes without "The term 'if' is not recognized" spam |
| E2 | v1.0.44 | Every panel's Summary panel populates after a run (no `$host` collision) |
| E3 | v1.0.44 | Click each sidebar entry twice quickly — no stack overflow |
| E4 | v1.0.45 | `&` in tile titles renders literally on home tiles AND section headers *(v1.0.53-beta extended to section headers)* |
| E5 | v1.0.46 | Tiles always in 4×2 grid, no holes/overlaps |
| E6 | v1.0.49 | Camera Connectivity dropdown shows fault flags |
| E7 | v1.0.50 | Camera Connectivity port detail boxes show remote device MAC + IP |
| E8 | v1.0.51 | With cameras.cfg, port labels show "Main Camera 1", "OCR / Scoreboard" |
| E9 | v1.0.52 | Camera Connectivity parses `rtsp:////169.254.16.50/h264` correctly |
| E10 | v1.0.53 | Repo is public — no `VPU_DEPLOY_TOKEN` references in launcher/scripts; install works anonymously |
| E11 | v1.0.53 | No feedback UI in Help/About; no Set-FeedbackToken.ps1 |
| E12 | v1.0.53-beta | Header bar / About panel / launcher banner / report headers all show `v1.0.53-beta` (suffix preserved) |

---

## F. Test result template

Paste into the ticket / Slack reply:

```
Pulse QA — v{version}
Date: YYYY-MM-DD       Tester: {name}
VPU: {model}  S/N {serial}   OS: {Win10 LTSC 1809 / 22H2 / Win11}
PowerShell: 5.1   NIC: {ADLINK card / Intel chip x N}   Display: {WxH}
Pixellot install: {C:\Pixellot or alt}   Cameras connected: {count + roles}

Smoke (B):           {N} / 8 passed
Per-panel (C):       {N} / ~40 passed   (failures: panel + case #)
Negative (D):        {N} / 15 passed    (failures: case #)
Regressions (E):     {N} / 12 passed    (any fail = blocker)

Notes:
{free-text — unexpected behavior, screenshots in ticket attachments,
exact versions of any service/driver mismatch, transcript file path}

Release recommendation: GO / NO-GO
```
