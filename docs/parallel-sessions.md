# Compact-safe parallel session protocol

This is the shared protocol that every lane prompt should reference. Keep this
file short enough for each agent to re-read at the start of every iteration.
Put lane-specific details in `docs/parallel-sessions/<lane>.md`.

## Prompt rule

The prompt file is only a router. Each prompt must start with `/goal`, use 50
words or fewer, and point to this file plus a lane markdown file. Do not put
long instructions, file lists, or implementation plans directly in the prompt.

## Planner lane

Every batch should have one planner/leader pane. `codex-supervisor` adds a
generated `PLANNER` lane by default when the prompt file does not already define
one. The planner does not own implementation code; it reviews recent pane
activity, keeps `docs/parallel-sessions/TEAM_PLAN.md` current, records blockers,
and queues the next smallest tasks for worker lanes.

## Iteration rule

Each lane performs one bounded iteration:

1. Re-read this shared protocol and the lane spec.
2. Inspect current repo state before editing.
3. Pick the smallest useful task from the lane spec or queue.
4. Make focused changes only inside the lane's writable scope.
5. Run the lane's required verification.
6. Commit or write a clear handoff note if the lane spec requires it.
7. End the goal when the iteration is complete, blocked, or near the timebox.

## Compact-avoidance rule

Do not continue an open-ended chat. Finish one small iteration and let the
supervisor respawn a fresh Codex process for the next task. Default supervisor
settings enforce this by respawning on goal completion and forcibly restarting
iterations that exceed the timebox.

Lane specs should include a stricter human-readable stop rule, for example:
"Stop after one PR-sized patch, after 30 minutes, or when blocked by missing
information."

## Handoff rule

When stopping, leave enough evidence for the next fresh Codex session:

- files changed,
- verification commands and results,
- blockers,
- next suggested task.

Prefer repo files, commits, issue comments, or a short handoff note over chat
history. Chat history may disappear when the next iteration starts fresh.
