# Handoff — Audio Diagnostics Tab

**Epic:** PULSEDEV-31 (Audio diagnostics panel)
**Branch:** `dev`
**Status:** **Feature-complete but GATED OFF for the beta build.** The tab is
fully implemented and was demo-verified, but it is hidden behind a "Coming
Soon" placeholder because it was **never confirmed working on real VPU
hardware** — see the Critical Open Question below.

---

## TL;DR for the next session

1. The Audio tab works end-to-end in demo mode. All four JIRA tickets are
   substantially implemented (gaps noted below).
2. It is **gated**: `pageRenderers.audio` points at `renderAudioComingSoon`,
   not `renderAudio`. Nothing was deleted — flip one line to re-enable.
3. **The single most important task: confirm `Get-AudioDevices.ps1` actually
   works on a real VPU** (Win 10 IoT LTSC + its specific .NET build). The tab
   was gated precisely because we never got a clean hardware run. CoreAudio
   COM interop is the risk.

---

## How to re-enable the tab

One line in `app/static/app.js` (~line 793, the `pageRenderers` map):

```js
audio: renderAudioComingSoon,   // ← change back to:  audio: renderAudio,
```

That's it. The nav entry (app.js:48), PAGE_API entry (app.js:85), the full
`renderAudio()` implementation, all helpers, CSS, API endpoints, and PS
scripts are all still present and wired. `renderAudioComingSoon()`
(app.js:5598) can be deleted once the tab is permanently re-enabled, or kept
as a pattern for gating other tabs.

---

## 🚨 Critical Open Question (start here)

**Does CoreAudio enumeration work on the VPU, or does it fall back to WMI / fail?**

On the VPU during beta prep, the tab hung on "Loading Audio…" forever. Two
root causes were found and **both are fixed at the infrastructure level**:

- **Frontend fetch-loop** (fixed, commit `953f028`): `fetchSection()` didn't
  cache error responses, so a failing `/api/audio` re-fired every ~140ms.
  Now errors are cached and the renderer shows `errorBox`. *This bug masked
  the real one.*
- **Script silently returned no output** (fixed, commits `953f028` +
  `0d1499b`): `Get-AudioDevices.ps1` could die inside `Add-Type` before
  emitting JSON. It now **always** emits JSON, and `run_ps` now surfaces
  stderr + exit code on empty output.

**What was never answered:** with those fixes in place, does the script
return real CoreAudio device data, or does it report `wmiFallback: true`
(degraded — no volume/mute/peak), or still error? The script now carries a
`diagnostics` block (`interopLoaded`, `coreAudioFailed`, `wmiFallbackUsed`,
`interopError`, `coreAudioError`, `psVersion`) — **first step: pull
`/api/audio` on a VPU and read that block.** It will tell you exactly which
phase works.

If CoreAudio interop doesn't load on the VPU's .NET build, the fallback
options are: (a) ship the WMI-only fallback (device list, no live meters),
(b) vendor a tiny compiled helper exe, or (c) NAudio via a bundled DLL.

---

## File map (verified line numbers, `dev` @ `0d1499b`)

### Frontend — `app/static/app.js`
| What | Location | Notes |
|------|----------|-------|
| Nav entry | line 48 | `{ id: "audio", label: "Audio", icon: "mic" }` — still visible |
| PAGE_API | line 85 | `audio: "/api/audio"` |
| Renderer wiring | line 793 | **`audio: renderAudioComingSoon`** ← the gate |
| `renderAudioComingSoon()` | line 5598 | The placeholder (delete on re-enable) |
| Constants | lines 5610–5612 | `AUDIO_SIGNAL_THRESHOLD=1`, `AUDIO_PEAK_HOT=80`, `AUDIO_REFRESH_MS=2000` |
| **`renderAudio()`** | lines 5617–5856 | Full impl — summary cards, findings, device rows, volume sliders, 2s live-refresh. Intact. |
| Helpers | 5734–5856 | `_audioUpdateMeter`, `_audioPeakClass`, `_audioFindings`, `_audioSlug`, `_audioSummaryCard`, `_audioFormFactorBadge`, `_audioFormFactorLabel`, `_audioDeviceRow` |

### Styles — `app/static/style.css`
- ~42 `.audio-*` classes (summary cards, device rows, peak meters, sliders,
  findings, vendor chips). Plus `.coming-soon` (shared placeholder style).

### Backend — `app/main.py`
| Endpoint | Location | Notes |
|----------|----------|-------|
| `GET /api/audio` | line 2571 | Runs `Get-AudioDevices.ps1`. **Not in preload** — lazy-fetched on tab visit (CoreAudio enum can be slow). |
| `POST /api/audio/volume` | lines 2576–2592 | Validates `deviceId` (non-empty str) + `volume` (int 0–100) before calling `Set-AudioVolume.ps1` |

### PowerShell — `scripts/`
| Script | Size | Notes |
|--------|------|-------|
| `Get-AudioDevices.ps1` | ~10 KB | CoreAudio enum → device list w/ volume, mute, peak, formFactor. WMI fallback. **Always emits JSON** via `_EmitJsonAndExit` + `diagnostics` block. |
| `Set-AudioVolume.ps1` | ~3.3 KB | Sets master volume scalar via `IAudioEndpointVolume`. Searches ALL device states; returns verified post-set volume. |
| `_AudioInterop.ps1` | ~6.8 KB | Shared CoreAudio COM type definitions (dot-sourced by both scripts). Interface extended through `GetMute` (vtable idx 13). |

### Demo data — `app/demo_data.py`
- `Get-AudioDevices.ps1` → line 683 (5 devices: 2 active inputs incl. a muted
  mic, 1 disabled, 1 active output, 1 unplugged). `Set-AudioVolume.ps1` →
  line 741. Demo peaks are tuned clear of the 1% threshold so "Signal
  Detected" doesn't flicker.

---

## JIRA ticket status (what's done vs. what's left)

### PULSEDEV-38 — Line-in capture check
**Mostly done.** Enumerates capture devices ✓, samples peak ✓, "Line-in
active but silent" warning finding ✓ (`_audioFindings`), live update ✓ (2s).

### PULSEDEV-39 — Gain + volume adjustment
**Partial.** Master volume read + set ✓, mute state read ✓ (`GetMute`),
slider commit-on-release ✓. **Gap:** microphone *boost/gain* specifically is
NOT implemented — only the master volume scalar. Boost needs a different
CoreAudio property (`IAudioEndpointVolume` doesn't expose it; it's on the
capture device's hardware property store).

### PULSEDEV-40 — Mixer level / activity meter
**Partial.** Per-device peak meter ✓, page-level "is anything making sound"
roll-up ✓. **Gap:** ticket asks for ~10 Hz; current impl polls at **2 s**
(`AUDIO_REFRESH_MS`). True 10 Hz needs a WebSocket push or a streaming helper,
not on-demand `run_ps` (each PS spawn is ~100–200 ms minimum). Decide whether
2 s "is signal present" is enough, or if real-time bars are required.

### PULSEDEV-41 — Identify physical port
**Partial.** `EndpointFormFactor` ✓ (Line-In / Mic / Speakers / HDMI badges
via `_audioFormFactorBadge`). **Gap:** `KSCONNECTPHYSICAL_LOCATION` via
`IDeviceTopology` for front/rear jack distinction ("Microphone (rear)") is
NOT implemented — would need additional COM interop in `_AudioInterop.ps1`.

---

## Commit history (audio-tagged)
- `33f4a6a` — initial feat: audio tab
- `8f6c226` — polish: 13 review findings (mute via GetMute, COM cleanup, error handling, in-flight guard, findings panel, slug hashing)
- `953f028` — fix: script always emits JSON + frontend fetch-loop fix
- `aa5ded8` — style: coming-soon placeholder (the gate) + ship orphaned styles
- `0d1499b` — harden(run_ps): stderr surfacing + diagnostics (helps debug the audio VPU failure)

---

## Suggested order for the new session
1. **Run `Get-AudioDevices.ps1` on a real VPU**, read the `diagnostics`
   block. This single step decides everything below.
2. If CoreAudio works → flip the gate, do a clean hardware pass of every
   device row + the volume slider write path.
3. If it falls to WMI → decide: ship degraded (list only) or invest in a
   compiled/NAudio helper.
4. Close the PULSEDEV-39/40/41 gaps as scoped above (mic boost, 10 Hz
   metering, physical-jack ID) — each is independent and optional for v1.

## Patterns to know (shared across all Pulse sessions)
- ES2019 only (VPU Chrome lacks `.flat()` — use `String()`/split).
- `asyncio.Semaphore(4)` caps concurrent PS in `powershell.py`.
- Multi-session repo: stage only files you touched, check
  `git diff --cached --stat` before every commit (see root `CLAUDE.md`).
- Tests: `cd Pulse.Web && .venv/bin/python -m unittest discover -s tests`.
