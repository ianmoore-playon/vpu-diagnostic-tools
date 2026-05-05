# Pulse WPF — UX Review

*Authored by the `pulse-ux-reviewer` persona, against the v0.1 pilot
(Camera Connectivity panel only). Captured here as a reference document
for the WPF migration plan.*

## 1. Top 5 highest-impact UX issues (Camera Connectivity)

**1. The page never answers "what is wrong, where, what next" at a glance.**
`CameraConnectivityView.xaml` rows 0–3 show a status pill that reads "Ready" / "All Clear" / "Issues Found" with no aggregation of *which port* is the problem. A Tier-1 agent staring at this on LogMeIn has to scan four 296×178 cards to find a yellow dot. There is no top-of-page **Findings summary** — e.g. "1 Warning: Port 2 negotiated 100 Mbps to a Main camera (expected 1 Gbps). Recommended: reseat the cable on Port 2 or replace it." That is the single biggest miss versus the design principle. **Fix in `CameraConnectivityView.xaml` between rows 0 and 1**: add a Findings card that lists every Warning/Critical with its recommended action, generated from the same logic in `CameraConnectivityViewModel.RefreshLiveAsync`.

**2. Five empty placeholder cards are actively misleading.**
Lines 108–144 of `CameraConnectivityView.xaml` render SmartSpeed/Ping/ARP/CHU/PoE Budget cards with hard-coded em-dashes. To a support agent these look broken or "didn't run". Either hide them until `RunDiagnosticAsync` actually populates them, or label them "Not yet measured — Run Test to evaluate" with a faint icon. Right now they steal vertical real estate (about 110 px) that should belong to findings.

**3. "Run Test" silently does nothing.**
`CameraConnectivityViewModel.RunDiagnosticAsync` sets the status to "All Clear" no matter what the cards say, and adds a log line saying the engine is deferred. A field tech who clicks Run Test on a real fault will see "All Clear" pinned to the header — that is dangerous in a diagnostic tool. Until the engine is ported, the button should read **"Refresh Live State"** and the StatusLabel should reflect the **worst port state** (`Degraded` → "Issues Found", `No Link` on a port that has a configured role → "Critical").

**4. The header status pill is decoupled from port reality.**
`StatusLabel` only changes inside `RunDiagnosticAsync`. Live monitoring (which runs every 3 s) never updates it. So a cable falls out at minute 4 → the cards turn red, the pill stays "All Clear". Move status aggregation into `RefreshLiveAsync` (compute worst-of all ports each tick).

**5. Live Log dominates the page but carries almost no value in the pilot.**
Row 4 of the grid is `Height="*" MinHeight="280"` and the log gets 2× the column width of Guidance. In the pilot the log has at most 3 entries ever ("Pilot diagnostic", "Note", "Refresh complete"). That is ~280 px of dead pixels at the visual center of the screen on a 1366×768 monitor. Demote Live Log to a collapsible expander or tab behind the Findings panel, and promote Next Steps Guidance + a per-port action list to the prime real estate.

## 2. Theme & visual system

**Palette — keep the bones, tighten contrast and add semantic depth.** Current `Colors.xaml` has only 14 swatches and no elevation system. Recommended additions:

```xml
<!-- Surfaces — three elevations, not one -->
<Color x:Key="AppBg">#0B111E</Color>             <!-- was 0A101E, slightly warmer -->
<Color x:Key="SurfaceBg">#131C2D</Color>          <!-- new: subordinate panel -->
<Color x:Key="CardBg">#1A2538</Color>             <!-- was 162032, +1 step lighter -->
<Color x:Key="CardBgRaised">#22304A</Color>       <!-- new: hover/selected -->
<Color x:Key="BorderCol">#2E3D55</Color>          <!-- subtle bump for ratio -->
<Color x:Key="BorderColStrong">#475A78</Color>    <!-- new: focus rings, dividers -->

<!-- Text — fix the muted text contrast -->
<Color x:Key="Foreground">#E6ECF5</Color>         <!-- was DCE4F0, +1 lum -->
<Color x:Key="MutedForeground">#8FA0BD</Color>    <!-- was 6E809B — fails 4.5:1 on CardBg -->
<Color x:Key="SubtleForeground">#637592</Color>   <!-- new: meta lines only -->

<!-- Status — softer reds to avoid alarm fatigue, brighter green for badges -->
<Color x:Key="Green">#34D399</Color>
<Color x:Key="Yellow">#F59E0B</Color>
<Color x:Key="Red">#F87171</Color>
<Color x:Key="Critical">#DC2626</Color>           <!-- new: reserved for "stop the line" -->
<Color x:Key="Info">#60A5FA</Color>               <!-- new: distinct from Accent -->
```

The current `MutedForeground #6E809B` on `CardBg #162032` is roughly 3.4:1 — fails WCAG AA for body text. Bumping to `#8FA0BD` lifts it to ~4.6:1.

**Typography hierarchy — collapse to a 6-step scale, no floating sizes:**

| Token | Size | Weight | Use |
|---|---|---|---|
| `DisplayLg` | 28 | Semibold | Findings headline number ("2 issues") |
| `PageTitle` | 22 | Semibold | Panel title (already exists) |
| `SectionTitle` | 14 | Semibold | Card titles (already exists) |
| `BodyDefault` | 13 | Regular | Default running text |
| `BodyStrong` | 13 | Semibold | Port names, statuses |
| `MetaSm` | 11 | Regular | Labels, timestamps (already `MutedLabel`) |
| `Mono11` | 11 | Regular | IP/MAC values (already `MonoValue`) |

Drop the inline `FontSize="20"`/`"15"` etc. in `CameraConnectivityView.xaml` lines 113, 51 — replace with named styles.

**Spacing — pick 4/8/12/16/24/32 and enforce.** Currently the file mixes `2, 4, 6, 8, 12, 14, 16, 20, 22, 24, 32`. Most offending: the 5-card row uses `Margin="0,0,6,0"` / `"6,0,6,0"` which is half a step out of the rhythm. Standardize on multiples of 4 with a `<Thickness x:Key="GapSm">4</Thickness>` … `GapXl=32` token set in `Styles.xaml`.

**Card elevation — three levels.** Right now every Card uses one drop shadow. Define three:
- `CardFlat` (no shadow, just border) — for grouping inside a card (port detail rows)
- `CardElev1` (current) — content surfaces
- `CardElev2` (BlurRadius=20, Opacity=0.32) — Findings banner, modals

**Light theme.** Don't fight it — design the palette as semantic tokens (`SurfaceBg`, `BorderCol`, `Foreground`, `Critical`, …) and ship a parallel `Colors.Light.xaml` later. The `<DynamicResource>` story is already wired in `MainWindow.xaml`. Switch via `Application.Current.Resources.MergedDictionaries[0] = new ResourceDictionary { Source = … }` from a Settings toggle. Color values for light: `AppBg #F4F6FA`, `CardBg #FFFFFF`, `Foreground #0F1624`, `MutedForeground #4B5A75`, status colors stay identical (their hues already work both ways).

## 3. Information architecture

Does the panel answer "what is wrong, where, what next"? **Partially — for "where" only.** The port cards tell you state per port, but neither "what is wrong" (no aggregation) nor "what next" (Guidance is generic prose, not actionable per finding).

Proposed layout, top to bottom:

1. **Header** (title + status pill) — keep, but make pill *aggregate* live, not just post-test.
2. **Findings banner** (NEW) — only renders when there is at least one Warning/Critical. Each finding is a horizontal row: severity icon, plain-English statement, primary action button. Example: `[!] Port 2 — Main Camera negotiated 100 Mbps. Expected 1 Gbps. [Reseat & retest] [Open adapter settings]`. Clicking a finding scrolls/highlights the relevant port card.
3. **Toolbar** (Test Scope + Detected NIC) — keep.
4. **Port cards** — keep, but add a one-line "what this means" footer per card when status is Degraded/No Link (e.g. "Recommended: try a known-good Cat6 cable").
5. **Probe results row** (the 5 cards) — only show after a test runs; dim/hide otherwise.
6. **Two-column tail**: left = **Recommended Actions** (was Guidance, now actionable buttons), right = **Live Log** (collapsed by default, expander).
7. **Action bar** — keep, rename "Run Test" → "Run Full Diagnostic" so it's distinct from "Refresh".

The 5-card grouping (SmartSpeed / Ping / ARP / CHU / PoE Budget) is sensible technically but reads as five disconnected probes. Better: group as **"Network" (SmartSpeed, ARP, Ping)** and **"Power & Camera" (PoE Budget, CHU detection)**. That maps to how a tech actually triages — link layer first, then device.

Live Log: **less real estate, not more.** Tier-1 doesn't read raw logs; Tier-3 wants the full transcript on demand. Make it an expander at the bottom that pops out to fill the row when opened. Add a "Copy log" icon button in its header (not just at the bottom action bar).

Next Steps Guidance: **more prominent, but only when contextual.** A static block of prose ("Live port-status monitoring is active…") is page noise. Replace with a stack of action buttons that change based on state: when all ports linked at 1 G → "Run Full Diagnostic" only; when one is degraded → "Reseat cable & re-check Port N", "Force 1 Gbps via Adapter Settings", "Open Fault Isolator".

## 4. Wording

In `CameraConnectivityView.xaml` and `CameraConnectivityViewModel.cs`:

- **"All Clear"** (line ~187 of VM) — fine, but pair with a count: "All Clear (4 ports linked at 1 Gbps)". Bare "All Clear" reads as a guess.
- **"Issues Found"** is the kind of vague label your principles call out. Use **"1 Warning"** / **"2 Critical"** with severity-specific colour.
- **"Linked"** (`StatusText`, VM line ~140) — ambiguous: linked at what speed? Use **"1 Gbps"** as the status text directly. The dot already encodes pass/fail; the text should encode *information*.
- **"Linked (OCR)"** — Tier-1 doesn't know OCR means optical-character-recognition scoreboard camera. Use **"100 Mbps — OCR (expected)"**.
- **"Degraded"** — better than most, but tell them what it should be. Use **"100 Mbps (expected 1 Gbps)"**.
- **"No Link"** — fine, but distinguish "No cable" (`No device`) from "Cable, no negotiation". A `No device` port should say **"Empty"** not "No Link".
- **"No device"** (VM line ~225) — ambiguous. Use **"No cable"** when the port is down with no MAC.
- **"Main Camera (probable)"** (VM line ~242) — the parenthetical undermines confidence. Use **"Main Camera"** + an info icon tooltip "Inferred from speed; not yet matched to cameras.cfg".
- **"Detecting…"** for `DetectedNic` — fine, but a permanent **"4 camera-NIC ports detected (Intel I350-T4)"** reads as plumbing detail. Move it under the page subtitle as a meta line, not a top-right toolbar element.
- **"Test Scope"** combo — fine label, but **"All Ports"** as default item should be **"All 4 ports"** (specific count beats generic).
- **"Open Fault Isolator →"** — currently triggers a "not implemented" toast. Either disable the button with a tooltip "Coming in next release", or remove it. A button that does nothing on click is the worst option.
- **"Run Test"** — too generic. **"Run Full Diagnostic"** in the pilot, or even better, **"Refresh Live State"** until the engine is ported.
- **"Pilot diagnostic"** / **"Refresh complete. See the WinForms Pulse for the full diagnostic."** (VM lines 184, 191) — never expose internal terms like "WinForms Pulse" or "pilot" to a support agent. Phrase as **"Live state refreshed. Full diagnostic engine arrives in v1.1."**
- **"Errors:"** card field — what kind? Adapter receive errors? Use **"NIC errors:"** with tooltip "Receive + transmit errors since last reset".
- **"L2 neighbour table"**, **"ICMP reachability"**, **"RTSP port 554"**, **"ADLINK SmartPoE"** (status-card subtitles, lines 113–143) — pure jargon. Replace with: "Switch sees the camera", "Camera responds to ping", "Camera streams video", "Switch power budget".

## 5. Motion & feedback

Pilot has zero animation. The high-value moves (not fancy, but functional):

- **Live-update flash on port cards.** When a port's `StatusColor` or `Speed` changes during a `RefreshLiveAsync` tick, briefly fade the card's border from `AccentBrush` back to default over 600 ms. Tells the agent "I just saw new data" and mitigates the "did anything change?" problem on a 3 s polling loop.
  ```xml
  <Style.Triggers>
    <DataTrigger Binding="{Binding JustUpdated}" Value="True">
      <DataTrigger.EnterActions>
        <BeginStoryboard><Storyboard>
          <ColorAnimation Storyboard.TargetProperty="BorderBrush.Color"
                          To="#3B82F6" Duration="0:0:0.15" AutoReverse="True"/>
        </Storyboard></BeginStoryboard>
      </DataTrigger.EnterActions>
    </DataTrigger>
  </Style.Triggers>
  ```
- **Status-pill colour transition.** Currently snaps from gray → yellow → green. Add a 200 ms `ColorAnimation` on `StatusBg` and `StatusColor` so the Running → Done shift reads as progress, not a flicker.
- **Findings banner slide-in.** When a Warning appears live (cable pulled), animate the banner in via `TranslateTransform.Y` from -20 to 0 and `Opacity` 0 → 1 over 250 ms. Skip on initial render.
- **Sidebar nav active-bar.** The 3 px accent border on the active item should slide between items, not jump — cheap to do with a `RenderTransform` storyboard tied to `IsChecked`.
- **Run Test button — indeterminate progress.** Replace its content with a `MaterialDesign:CircularProgressBar` (already in the toolkit) when `RunTestCommand.IsExecuting`. Right now the button just disables.
- **ListBox item insertion.** New `LogEntries` items should fade in (50 ms) — eliminates the "did the log update?" question. Use `ItemsControl.ItemContainerStyle` + a Loaded trigger.

Avoid: bouncy easing, ripple effects on cards (Material has them on buttons already — leave it there), parallax, anything > 300 ms. This is a diagnostic tool — motion should be calm.

## 6. Accessibility & contrast

**Contrast audit on current `Colors.xaml`:**

| Pair | Ratio | WCAG AA |
|---|---|---|
| Foreground `#DCE4F0` on CardBg `#162032` | 12.6:1 | ✅ |
| MutedForeground `#6E809B` on CardBg | **3.4:1** | ❌ AA body |
| MutedForeground on AppBg `#0A101E` | 4.1:1 | ❌ AA body |
| Yellow `#EAB308` on CardBg | 8.7:1 | ✅ |
| Red `#EF4444` on CardBg | 4.6:1 | ✅ AA body, fails AAA |
| Green `#22C55E` on OkBg `#0F3A1C` | 4.9:1 | ✅ AA body |
| Green `#22C55E` on CardBg | 6.2:1 | ✅ |
| Accent `#3B82F6` on CardBg | 3.9:1 | ❌ AA body, ✅ AA Large |

Fixes: bump `MutedForeground` to `#8FA0BD` (raises ratios above 4.5). Avoid using `AccentBrush` for body text — restrict to large headings, icons, button fills.

**Keyboard nav:** every interactive control in `CameraConnectivityView.xaml` is built on standard WPF primitives (Button, ComboBox, ListBox, ToggleButton) so Tab order works by default. But:
- The sidebar `ToggleButton`s have `IsEnabled="False"` for non-Camera tabs. Disabled controls are skipped by Tab, which is correct — but they're also the only nav. Once those are wired up, ensure `KeyboardNavigation.TabNavigation="Cycle"` on the sidebar and `KeyboardNavigation.DirectionalNavigation="Cycle"` so arrow keys move between nav items.
- Port cards are `Border` elements — not focusable. If clicking a port card is meant to do anything (and per your mockup, opening a per-port detail box, it should), wrap them in a `Button` with a card-style ControlTemplate, otherwise keyboard users can't reach them.
- The status pill is a `Border` with no AutomationProperties. Add `AutomationProperties.Name="Overall status: {Binding StatusLabel}"`.
- Add `AutomationProperties.HelpText` to each port card with the same content the mouse user would tooltip — currently a screen reader hears "Port 1, Linked, 1 Gbps, 192.168.0.10, 00-D0-89-…" which is fine if labeled, but right now there are no `AutomationProperties` anywhere in the file.

**Focus indicator:** WPF default focus rect is invisible on a dark background. Define a `FocusVisualStyle` once in `Styles.xaml` using `BorderColStrong` 2 px and apply globally.

**ListBox virtualization on Live Log:** already fine because of `ScrollViewer.CanContentScroll` defaults, but with 200-item cap, no perf concern. A screen reader will still announce every line as it streams in — add `AutomationProperties.LiveSetting="Polite"` so they aren't interrupted.

## 7. Path to mockup polish — ranked panel ROI

The "near-photographic NIC render with cables drawn to detail boxes" mockup is the right north star but only buys polish on **one** panel. Without bitmap assets, you can still hit ~80% of the same emotional impact with vector + gradient work in pure XAML — drawn `Path` geometry for the NIC bezel, RJ45 jack rectangles, animated `LineGeometry` from each jack to the port card. ~3 days of focused dev for a designer-engineer pair.

**Polish ROI ranking (highest → lowest):**

1. **Network** — single largest "wow" return; sets the tone for the whole app and is the panel where techs spend the most time. Bespoke design fully justified. ~3 days for the NIC visualization.
2. **Camera Connectivity** — same audience, similar mental model; reuse the NIC visualization with camera icons on the camera end of each cable. Bespoke design. ~2 days once Network is done.
3. **Home / System Overview** — first impression. Big gauges for CPU/GPU/Disk + hero status banner. Bespoke design pays off. ~2 days.
4. **Hardware & Peripherals** — has photogenic content (USB devices, capture cards). Card grid with device-type icons; not bespoke per device, but a strong icon system. ~1.5 days.
5. **Disk & System Health** — gauges + sparklines. Material baseline is fine if you add 2–3 custom gauge controls. ~1 day.
6. **Pixellot Services** — list view of services. Material baseline good enough; just a great status table. ~0.5 day.
7. **Event Viewer** — dense data table. Stay Material. Filters + severity chips. ~0.5 day.
8. **System Information** — read-only key-value list. Material baseline, no need for hero design. ~0.25 day.
9. **Reports** — utilitarian, agent uses it briefly. Material baseline. ~0.25 day.
10. **Settings** — Material baseline absolutely. Don't waste polish budget here.

Total bespoke-polish budget: ~3 days × 4 panels (1–4) = ~12 dev-days for the visually load-bearing screens. The other six can ship at Material baseline in another 2–3 days.

## 8. Quick wins vs larger investments

**Quick wins (≤ 2 hours each):**
- Bump `MutedForeground` to `#8FA0BD` in `Colors.xaml` (one line, fixes WCAG fail across whole app).
- Replace `StatusText="Linked"` with the actual speed value in `CameraConnectivityViewModel` (~5 lines).
- Compute `StatusLabel` inside `RefreshLiveAsync`, not just inside `RunDiagnosticAsync` (~10 lines).
- Hide the 5 placeholder status cards until a test has run, or label them "Not measured" instead of "—".
- Rename "Run Test" → "Run Full Diagnostic" + add tooltip explaining the pilot scope.
- Disable / remove "Open Fault Isolator →" until it does something.
- Replace "L2 neighbour table" / "ICMP reachability" / etc. subtitles with plain language.
- Add `AutomationProperties.Name` to the status pill, port cards, and sidebar nav buttons.
- Define a `FocusVisualStyle` in `Styles.xaml` and apply via `<Style TargetType="{x:Type Control}">` so focus is visible.
- Add a "Copy log" icon button to the Live Log header.

**Medium investments (1–3 days each):**
- **Findings banner**: per-finding row with severity, plain-English statement, action buttons. Drives the entire decision-engine experience.
- **Port-card live-flash** + status-pill colour transition Storyboards.
- **Spacing/typography tokens** pass: extract every inline `Margin`, `FontSize`, `FontWeight` into `Styles.xaml` resources, replace site-by-site.
- **Three-tier surface system** (`SurfaceBg`, `CardBg`, `CardBgRaised`) and elevation Card styles.
- **Light theme** palette + a real switcher in Settings.
- **Network panel polish**: vector NIC render + animated cables (the mockup target, in pure XAML).

**Larger initiatives (1+ week):**
- **Port the diagnostic engine** out of PowerShell into C# services so `Run Full Diagnostic` is real. Without this, no amount of UX polish saves the panel. Single biggest blocker.
- **Phased migration of all 10 panels** with a shared component library (StatusPill, FindingsBanner, KeyValueRow, GaugeCard, DataTableSeverity).
- **Per-panel bespoke polish** for Home, Network, Camera Connectivity, Hardware (per the polish ROI ranking) — ~12 dev-days total.
- **Settings panel + theme switcher + persistence** so light theme and per-tech preferences (e.g. "always show raw log") survive restarts.
- **Telemetry of agent flow** (which findings get acted on, which buttons get clicked, which panels open most): instruments whether the decision-engine is actually working in the field. Without this, the next round of UX decisions is guesswork.

The sequencing I'd recommend: ship the Quick Wins next sprint, do the Findings banner + status aggregation as the first medium move (it changes the panel from data-viewer to decision-engine in one stroke), then commit to the engine port before any further polish — polish on top of a stub Run Test button is wasted spend.
