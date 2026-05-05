# Pulse.WPF Style Guide

This is the design-token reference for the WPF migration. New panels MUST
use the tokens listed here — no inline `FontSize`, no magic colour hex, no
ad-hoc `Margin` values. The tokens live in:

- `Pulse.WPF/Themes/Colors.xaml` — dark palette (default)
- `Pulse.WPF/Themes/Colors.Light.xaml` — light palette (companion file, not yet wired)
- `Pulse.WPF/Themes/Styles.xaml` — typography, spacing, card elevations, focus visual

Reference: see `Pulse.WPF/UX_REVIEW.md` for the rationale behind every token.

---

## 1. Colours

### Surfaces (three elevations)

| Token            | Dark      | Light     | Use                                          |
|------------------|-----------|-----------|----------------------------------------------|
| `AppBg`          | `#0B111E` | `#F4F6FA` | Window / page background                     |
| `SurfaceBg`      | `#131C2D` | `#ECEFF5` | Subordinate panels (sidebars, sub-sections)  |
| `CardBg`         | `#1A2538` | `#FFFFFF` | Default content surface                      |
| `CardBgRaised`   | `#22304A` | `#F8FAFC` | Hover / selected / Findings banner           |

### Borders

| Token              | Dark      | Light     | Use                              |
|--------------------|-----------|-----------|----------------------------------|
| `BorderCol`        | `#2E3D55` | `#D8DEE9` | Default card / control borders   |
| `BorderColStrong`  | `#475A78` | `#A7B3C7` | Focus ring, dividers, key edges  |

### Text (three levels)

| Token              | Dark      | Light     | Use                          |
|--------------------|-----------|-----------|------------------------------|
| `Foreground`       | `#E6ECF5` | `#0F1624` | Default body text            |
| `MutedForeground`  | `#8FA0BD` | `#4B5A75` | Labels, secondary text       |
| `SubtleForeground` | `#637592` | `#6B7894` | Meta lines, timestamps       |

`MutedForeground` was bumped from the prior `#6E809B` to fix a WCAG AA failure.

### Status palette

| Token      | Hex       | Use                                              |
|------------|-----------|--------------------------------------------------|
| `Green`    | `#34D399` | Pass / OK                                        |
| `Yellow`   | `#F59E0B` | Warning                                          |
| `Red`      | `#F87171` | Fail                                             |
| `Critical` | `#DC2626` | "Stop the line" — production-impacting           |
| `Info`     | `#60A5FA` | Informational, distinct from `Accent`            |
| `Accent`   | `#3B82F6` | UI accents only (icons, button fills, NOT body)  |

### Pill backgrounds

`OkBg`, `WarnBg`, `ErrBg`, `CriticalBg`, `InfoBg` — paired with the matching
foreground colour above.

---

## 2. Typography (7-step scale)

Use `Style="{StaticResource <name>}"` on every TextBlock. Don't set `FontSize`
or `FontWeight` inline.

| Token         | Size | Weight    | Use                                          |
|---------------|------|-----------|----------------------------------------------|
| `DisplayLg`   | 28   | Semibold  | Findings headline number ("2 issues")        |
| `PageTitle`   | 22   | Semibold  | Panel title                                  |
| `SectionTitle`| 14   | Semibold  | Card titles                                  |
| `BodyDefault` | 13   | Regular   | Default running text                         |
| `BodyStrong`  | 13   | Semibold  | Port names, statuses                         |
| `MetaSm`      | 11   | Regular   | Labels, timestamps (alias `MutedLabel`)      |
| `Mono11`      | 11   | Regular   | IP/MAC values (alias `MonoValue`)            |

---

## 3. Spacing

Multiples of 4 only. Use the named `Thickness` tokens or matching `Double`s.

| Token   | Value | Use                                          |
|---------|-------|----------------------------------------------|
| `GapXs` | 4     | Inline gaps                                  |
| `GapSm` | 8     | Tight stacks                                 |
| `GapMd` | 12    | Default gap inside a card                    |
| `GapLg` | 16    | Card padding, section gap                    |
| `GapXl` | 24    | Page margins, between hero sections          |
| `GapXxl`| 32    | Outer page margin                            |

For each there is also a `<name>Value` `sys:Double` for properties like `Width`.

---

## 4. Card elevations (three levels)

```xml
<Border Style="{StaticResource CardElev1}"> ... </Border>
```

| Token       | Shadow                          | Use                                    |
|-------------|---------------------------------|----------------------------------------|
| `CardFlat`  | none                            | Grouping inside another card           |
| `CardElev1` | BlurRadius=12, Opacity=0.18     | Default content surfaces (== `Card`)   |
| `CardElev2` | BlurRadius=20, Opacity=0.32     | Findings banner, modals                |

`Card` is preserved as a backwards-compat alias for `CardElev1`.

---

## 5. Shared components (`Pulse.WPF/Controls/`)

| Component         | XAML usage                                                       |
|-------------------|------------------------------------------------------------------|
| `FindingsBanner`  | `<controls:FindingsBanner Findings="{Binding Findings}" />`      |
| `StatusPill`      | `<controls:StatusPill Label="All Clear" Severity="ok" />`        |
| `KeyValueRow`     | `<controls:KeyValueRow Label="IP:" Value="{Binding Ip}" IsMono="True" />` |
| `SeverityChip`    | `<controls:SeverityChip Severity="warn" Text="WARN" />`          |
| `SectionHeader`   | `<controls:SectionHeader Title="..." Subtitle="..." StatusLabel="..." StatusSeverity="..." />` |

`Severity` accepts: `ok` / `warn` / `fail` / `critical` / `info` / `running` / `neutral`.

`FindingsBanner` auto-collapses when its bound collection is empty and slide-in
animates from `-20px → 0` with opacity `0 → 1` over 250 ms when a finding
appears.

---

## 6. Focus visual

`Themes/Styles.xaml` defines `PulseFocusVisual` and applies it via
`<Style TargetType="{x:Type Control}">` so every interactive control gets a
2 px `BorderColStrong` outline when focused. Don't override `FocusVisualStyle`
unless you have a panel-specific reason.

---

## 7. Theme switching (deferred)

`App.xaml`'s merged dictionary list has `Themes/Colors.xaml` at index 4. To
swap to light at runtime:

```csharp
Application.Current.Resources.MergedDictionaries[4] =
    new ResourceDictionary { Source = new Uri("Themes/Colors.Light.xaml", UriKind.Relative) };
```

The Settings toggle is not wired up yet.

---

## 8. Accessibility checklist for new panels

- Set `AutomationProperties.Name` on every interactive control (button, combo,
  pill, port card).
- Set `AutomationProperties.HelpText` on cards / rows that have details a
  mouse user would tooltip.
- Make custom card surfaces `Button` (with `PortCardButton` style) if they're
  clickable — otherwise keyboard users can't reach them.
- Use named text styles (`MetaSm` / `BodyDefault` / etc.) — never inline
  `FontSize="11"` because contrast was tuned at the token level.
- Use `LiveSetting="Polite"` on streaming ListBoxes (Live Log).
