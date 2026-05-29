# Parallel sessions: one git worktree per lane

We run ~8 Claude Code sessions against this repo at once (Dashboard, System,
Network, Camera Connectivity, ScoreConnect, Audio, API, Setup). When they all
share **one working tree on `dev`**, they clobber each other: two sessions
writing `app.js` seconds apart overwrite on disk, and one session's
`git commit` captures another's staged files. CLAUDE.md's staging etiquette
reduces the damage but **cannot prevent a shared-disk race** — the fix is to
stop sharing the disk.

**Each session gets its own git worktree + branch.** Worktrees share one
`.git` object store (cheap) but have fully independent working trees, so there
is no cross-session clobbering. Integration moves to merge-time — explicit and
reviewable instead of silent.

## Setup (per lane)

From the main checkout (`/Users/ian.moore/Code/vpu-diagnostic-tools`):

```bash
./worktree.sh new <lane>     # lanes: dashboard system network cameras
                             #        scoreconnect audio api setup
```

This creates `../vpu-worktrees/<lane>` on a branch `lane/<lane>` off the
latest `origin/dev`, and prints the lane's dev-server command. Point that
session's Claude Code at the printed directory and do **all** its work there.

## Per-lane dev-server ports

Each lane has a fixed port so two servers never collide on 8765:

| Lane | Port | | Lane | Port |
|------|------|-|------|------|
| dashboard | 8770 | | scoreconnect | 8774 |
| system | 8771 | | audio | 8775 |
| network | 8772 | | api | 8776 |
| cameras | 8773 | | setup | 8777 |

```bash
cd ../vpu-worktrees/<lane>/Pulse.Web
PORT=87xx /Users/ian.moore/Code/vpu-diagnostic-tools/Pulse.Web/.venv/bin/python app/main.py
# ./worktree.sh run <lane> prints this line for you
```

The main repo's `.venv` is reused as the interpreter (it only supplies
fastapi/uvicorn); the code that runs is always the worktree's own.

## Merge flow

1. Work + commit on `lane/<lane>` — small, coherent commits.
2. `git pull --rebase origin dev` before pushing.
3. Push the lane branch; open a PR into `dev` (or fast-forward merge for tiny
   changes). **Never commit directly to `dev` from a shared tree.**
4. After merge, other lanes pick it up with `git pull --rebase origin dev`
   inside their worktree.

CLAUDE.md's etiquette (`git add` only your files, review
`git diff --cached --stat`, commit small) still applies — now it governs the
merge to `dev`, where it actually works, instead of a shared live tree, where
it can't.

## Cleanup

```bash
./worktree.sh rm <lane>      # removes the worktree dir; keeps the branch
git branch -d lane/<lane>    # delete the branch once merged
```

## Notes

- `.claude/worktrees/` is the agent runner's auto-managed worktree dir — leave
  it alone. Manual lane worktrees live in the sibling `../vpu-worktrees/`.
- The durable companion fix is to split the three monolith files
  (`app.js` 6.3k lines, `main.py` 3.2k, `style.css` 3.3k) into per-lane
  modules so lanes own disjoint files. That makes worktree merges
  conflict-free. Do it as a coordinated stop-the-world refactor, not live.
