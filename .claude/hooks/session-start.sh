#!/usr/bin/env bash
# Pulse — SessionStart hook.
# Anything this writes to stdout is injected into Claude's context at the
# start of every session (startup / resume / clear / compact). Keep it short:
# every line here is a per-session token cost.
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || true

echo "## Orient before acting (Pulse)"
echo "- Branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- Uncommitted in this checkout (commit only YOUR lane, by path — see CLAUDE.md Multi-Session Etiquette):"
git status --short 2>/dev/null | head -15

echo
echo "## Cardinal rules (do not relearn these every session)"
echo "- Worktree-first: never edit the main checkout — it's the read-only 8765 mirror of origin/dev. Do ALL work in your own worktree (git worktree add), even one-liners; UI work goes under .claude/worktrees/<name> on your own port. After a verified push, refresh 8765 only via ./sync-main.sh. See CLAUDE.md Multi-Session Etiquette."
echo "- Probe-first: confirm an existing lane already collects something before writing a new collector/script. The CGI probe (_cgi_probe_sync / _probe_camera_ip + _CGI_PROBE_CACHE) and _check_pixellot_compatibility already exist — reuse them."
echo "- tailwind-min.css is PREBUILT: it only contains classes present at build time. New utility classes will not exist at runtime — verify before relying on them, and don't edit the shared style.css blindly."
echo "- Diagnostics must not cry wolf: scope network probes to the active-default-route interface (the one with an IPv4 gateway / lowest route metric), never a name/index like 'Ethernet 16' and never first-across-all-interfaces. A critical that contradicts a passing check on the same panel must suppress itself."

echo
echo "## Handoff from the previous session"
if [ -f .claude/HANDOFF.md ]; then
  cat .claude/HANDOFF.md
else
  echo "(none) — if you are resuming work, ask the user which single task this session is for, then keep scope to that one task."
fi
