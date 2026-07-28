#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Pulse multi-session worktree helper
#
# One isolated git worktree per development lane, so the parallel
# Claude Code sessions (Dashboard, System, Network, …) never share a
# working tree — which is the only thing that actually stops them from
# clobbering each other's uncommitted edits. CLAUDE.md etiquette governs
# the MERGE back to dev; this governs the editing.
#
# Usage:
#   ./worktree.sh new  <lane>    create/attach a worktree + branch for a lane
#   ./worktree.sh list           show all worktrees
#   ./worktree.sh run  <lane>    print the dev-server command (with its port)
#   ./worktree.sh rm   <lane>    remove a lane's worktree (the branch is kept)
#
# Lanes (match the Claude Code session names):
#   dashboard  system  network  cameras  scoreconnect  audio  api  setup
# ─────────────────────────────────────────────────────────────
set -euo pipefail

MAIN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"
WT_ROOT="$(dirname "$MAIN_REPO")/vpu-worktrees"
# Reuse the main repo's venv interpreter — it only supplies fastapi/uvicorn;
# the app CODE that runs is always the worktree's own (resolved via __file__).
VENV_PY="$MAIN_REPO/Pulse.Web/.venv/bin/python"
BASE_BRANCH="dev"

# Lane → fixed dev-server port, so a lane always reuses the same port.
lane_port() {
  case "$1" in
    dashboard)    echo 8770 ;;
    system)       echo 8771 ;;
    network)      echo 8772 ;;
    cameras)      echo 8773 ;;
    scoreconnect) echo 8774 ;;
    audio)        echo 8775 ;;
    api)          echo 8776 ;;
    setup)        echo 8777 ;;
    *)            echo "" ;;
  esac
}

die() { echo "error: $*" >&2; exit 1; }

cmd_new() {
  local lane="${1:-}" ; [ -n "$lane" ] || die "usage: worktree.sh new <lane>"
  local port branch dir
  port="$(lane_port "$lane")" ; [ -n "$port" ] || die "unknown lane '$lane'"
  branch="lane/$lane"
  dir="$WT_ROOT/$lane"

  if [ -d "$dir" ]; then
    echo "worktree already exists: $dir"
  else
    echo "fetching origin/$BASE_BRANCH …"
    git -C "$MAIN_REPO" fetch origin "$BASE_BRANCH"
    mkdir -p "$WT_ROOT"
    if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$MAIN_REPO" worktree add "$dir" "$branch"
    else
      git -C "$MAIN_REPO" worktree add -b "$branch" "$dir" "origin/$BASE_BRANCH"
    fi
  fi

  echo
  echo "  lane:     $lane"
  echo "  branch:   $branch"
  echo "  worktree: $dir"
  echo "  port:     $port"
  echo
  echo "  work here:  cd '$dir'"
  echo "  run server: cd '$dir/Pulse.Web' && PORT=$port '$VENV_PY' app/main.py"
  echo "  merge flow: commit to '$branch' → push → PR into '$BASE_BRANCH'"
}

cmd_run() {
  local lane="${1:-}" ; [ -n "$lane" ] || die "usage: worktree.sh run <lane>"
  local port dir
  port="$(lane_port "$lane")" ; [ -n "$port" ] || die "unknown lane '$lane'"
  dir="$WT_ROOT/$lane"
  [ -d "$dir" ] || die "no worktree for '$lane' — run: worktree.sh new $lane"
  echo "cd '$dir/Pulse.Web' && PORT=$port '$VENV_PY' app/main.py"
}

cmd_list() { git -C "$MAIN_REPO" worktree list; }

cmd_rm() {
  local lane="${1:-}" ; [ -n "$lane" ] || die "usage: worktree.sh rm <lane>"
  local dir="$WT_ROOT/$lane"
  [ -d "$dir" ] || die "no worktree for '$lane'"
  git -C "$MAIN_REPO" worktree remove "$dir"
  echo "removed worktree '$dir' (branch lane/$lane kept — delete with: git branch -d lane/$lane)"
}

case "${1:-}" in
  new)  shift; cmd_new  "$@" ;;
  run)  shift; cmd_run  "$@" ;;
  list) shift; cmd_list "$@" ;;
  rm)   shift; cmd_rm   "$@" ;;
  *) echo "usage: worktree.sh {new|run|list|rm} <lane>"; echo "lanes: dashboard system network cameras scoreconnect audio api setup"; exit 1 ;;
esac
