---
name: promote-pulse
description: Promote Pulse.Web through the dev → beta → main release pipeline — version bumps, tagging, changelog promotion, and the CI release flow on playon/pulse. Use when cutting a beta, shipping to production, starting a new dev cycle, or when asked to "promote", "cut a release", "tag beta", "ship to main", or "bump dev".
---

# Promote Pulse.Web

The release runbook for Pulse.Web. Code flows `dev` → `beta` → `main`. Each branch
has CI builds; tags create releases on `playon/pulse` (the single source +
distribution repo). **Version source of truth: `Pulse.Web/VERSION`.**

Pulse.WPF is deprecated — it is not part of any release. Ignore it.

## Channels & tags

| Channel | Version format | Tag example | Release type | Audience |
|---------|----------------|--------------------------------|--------------|------------------|
| Dev | `X.Y.Z-dev` | `web-dev-v0.4.0-dev-abc1234` | pre-release | Internal testing |
| Beta | `X.Y.Z` | `web-beta-v0.3.0` | pre-release | Field validation |
| Main | `X.Y.Z` | `web-v0.3.0` | full release | Production VPUs |

Dev stays roughly two versions ahead of main; beta stays one ahead. Example at a
point in time — Main `0.1.0` (stable), Beta `0.3.0` (rolling to testers),
Dev `0.4.0-dev` (bleeding edge, auto-tagged with commit SHA).

## Promotion workflow

1. **Dev → Beta:** merge `dev` into `beta`. Set the version source to a clean
   semver (e.g. `0.2.0`). Push the beta tag (`web-beta-v0.2.0`).
2. **Beta → Main:** merge `beta` into `main`. Push the production tag — **the same
   version that was validated in beta** (`web-v0.2.0`).
3. **Bump dev:** after promoting, set the version source on `dev` to the next
   version with a `-dev` suffix (e.g. `0.3.0-dev`). Subsequent dev pushes
   auto-tag with the commit SHA.

## Rules — do not violate

- **Version bumps are manual.** Decide minor vs. major when starting a new dev cycle.
- **Dev auto-tags on push** via `.github/workflows/web-auto-tag.yml`. Beta and main
  tags are pushed **manually**.
- **Only promote to main what was validated in beta.** The beta tag version and the
  main tag version must match for a given release.
- **Never rewrite pushed history** on `dev`/`beta`/`main` — no amend, rebase, or
  force-push (see CLAUDE.md multi-session rules).

## Changelog (these notes are shown to testers on update)

`Pulse.Web/CHANGELOG.md` is the source for the in-app **Check for Update** "what's new" notes.

- When you ship a user-facing change, add a one-line bullet under `## [Unreleased]`
  (Added / Changed / Fixed), **written for a field tech, not a developer**.
- At a beta/main promotion, **rename `[Unreleased]` to the version** — that section
  becomes the release notes the mirror release publishes.
- Dev builds surface the current `[Unreleased]` list automatically; no per-push curation.
- The release workflow reads the top changelog section. **Do not hand-edit release bodies.**

## CI

- `.github/workflows/web-build.yml` — zips `Pulse.Web/`, triggers on web tags.
- `.github/workflows/web-auto-tag.yml` — auto-tags `dev` pushes.
- Both publish releases directly to `playon/pulse` using the workflow's built-in
  `GITHUB_TOKEN` — no separate PAT or mirror step.

## Checklist before pushing a beta or main tag

- [ ] Correct branch merged (`dev`→`beta` or `beta`→`main`).
- [ ] `Pulse.Web/VERSION` set to the clean semver (no `-dev` on beta/main).
- [ ] `CHANGELOG.md` `[Unreleased]` renamed to this version.
- [ ] For main: this exact version was validated in beta.
- [ ] Tag name matches the channel format above.
