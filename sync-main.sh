#!/usr/bin/env bash
# sync-main.sh — refresh the MAIN checkout (the 8765 mirror) to origin/dev, safely.
#
# Model: the main checkout is a READ-ONLY MIRROR of origin/dev. Nobody edits or
# commits there; all work happens in worktrees and is pushed to origin/dev. This
# script is the ONLY sanctioned way to advance the main tree and restart 8765.
#
# It fast-forwards ONLY and aborts on any uncommitted change or divergence, so it
# can never destroy work. If it aborts, STOP and reconcile by hand — never force.
#
# Run from anywhere inside the repo (any worktree).
set -uo pipefail

# The main worktree is always the first entry of `git worktree list`.
MAIN=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
[ -z "${MAIN:-}" ] && { echo "ABORT: not inside a git repo / no worktree found."; exit 1; }
echo "Main checkout: $MAIN"

# 1. Refuse if the main tree is dirty — it must stay a clean mirror.
if [ -n "$(git -C "$MAIN" status --porcelain)" ]; then
  echo "ABORT: main checkout has uncommitted changes — it must stay a clean mirror of origin/dev."
  echo "       Nobody should edit the main tree; do work in a worktree. Resolve the WIP, then retry."
  git -C "$MAIN" status --short
  exit 1
fi

# 2. Fetch, then fast-forward ONLY. ff-only refuses (instead of merging/resetting)
#    if local dev has diverged, so nothing is ever lost.
git -C "$MAIN" fetch origin dev || { echo "ABORT: fetch failed."; exit 1; }
if ! git -C "$MAIN" merge --ff-only origin/dev; then
  echo "ABORT: main 'dev' has diverged from origin/dev (local-only commits)."
  echo "       Fast-forward refused so nothing is destroyed. Reconcile by hand — do NOT force."
  echo "       (This is the 6907eea-style case: a commit made on the shared checkout that never"
  echo "        reached origin/dev. Decide whether to push it or drop it before mirroring.)"
  exit 1
fi
echo "Main fast-forwarded to $(git -C "$MAIN" rev-parse --short HEAD)."

# 3. Restart 8765 so it serves the updated files. 8765 is the Claude Preview MCP
#    server (python3 app/main.py from Pulse.Web/, uvicorn reload=off), so a restart
#    is REQUIRED for new code/static to show — and how you restart depends on who you are.
#    This script does NOT restart for you: it can't drive the MCP preview tool, and a raw
#    restart from here would orphan that tool's process registry. Advance is done; restart
#    with the right method below.
echo
echo "Mirror advanced. Restart 8765 to serve it:"
echo "  • Agent (has the preview tool):  preview_stop, then preview_start  (config: pulse-web)"
echo "  • Terminal (no MCP):  kill \$(lsof -ti tcp:8765) 2>/dev/null   # SIGTERM; frees 8766 too (same process)"
echo "                        ( cd \"$MAIN/Pulse.Web\" && PORT=8765 nohup python3 app/main.py >/tmp/pulse-8765.log 2>&1 & )"
