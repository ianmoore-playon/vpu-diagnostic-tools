# HANDOFF

(empty) — the session baton. At a task boundary, Claude overwrites this with a 3–5 line
summary: what changed, what's left, files that matter, what was ruled out.
The SessionStart hook reads it into the next session. See CLAUDE.md → Session Hygiene.
