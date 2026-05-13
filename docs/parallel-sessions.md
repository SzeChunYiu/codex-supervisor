# Compact-safe parallel session protocol

This is the shared protocol that every lane prompt should reference. Keep this
file short enough for each agent to re-read at the start of every iteration.
Put lane-specific details in `docs/parallel-sessions/<lane>.md`.

For any project that can run panes on multiple hosts, this file must also
import the distributed constitution in `docs/distributed-protocol.md`: one
project identity, no anonymous source copies, one writable lease per scope, and
fail-closed behavior when host/path/branch ownership is unclear.

For every active project, also use the AI factory model in
`docs/ai-factory.md`: one batch outcome, one validator-owned factory board,
and queue items that converge on accepted artifacts rather than unrelated lane
outputs.

## Prompt rule

The prompt file is only a router. Each prompt must start with `/goal`, use 50
words or fewer, and point to this file plus a lane markdown file. Do not put
long instructions, file lists, or implementation plans directly in the prompt.

## Fixed project lanes

Every active project should have two fixed panes:

- `DEBUG`: debugs and optimizes one code slice at a time.
- `VALIDATOR`: validates results from other sessions, keeps
  `docs/parallel-sessions/TEAM_PLAN.md` current, records blockers, and queues
  the next smallest prompts for dynamic or specified worker lanes.

`codex-supervisor` generates these lanes by default when the prompt file does
not already define equivalent `debug`/`optimizer` and `validator`/`planner`/
`leader` lanes.

For distributed projects, the validator also owns the live host/lane lease ledger:
which host is active, which source tree is canonical/worktree/mirror, which
branch/worktree each lane owns, and which paths are read-only for everyone else.

The validator owns the factory board at
`docs/parallel-sessions/TEAM_PLAN.md`. Before worker lanes start, that board
should declare the batch outcome, acceptance checklist, artifact ledger,
lane/lease table, queue policy, and blockers. Workers treat the board as the
source of truth for what "done" means.

## Dynamic workers

The rest of the panes are N dynamic workers, configured with
`CODEX_SUPERVISOR_DYNAMIC_WORKERS=N` or selected by `csup govern`. Dynamic
workers take generic open tasks from `codex-tasks/open.txt` and related open
queues. Use `codex-tasks/<lane>.txt` only when a task requires a specified lane,
host, branch, or writable lease.

Dynamic workers should close one checklist gap from `TEAM_PLAN.md`. If their
queue is empty, they may propose the next queue item to VALIDATOR; they should
not create side artifacts that are not tied to the current batch outcome.

## Distributed safety minimum

Before starting or resuming any worker lane:

1. Prefer one host. Add a second host only for measured resource need or native
   execution requirements.
2. Use exactly one canonical project identity from `.codex-supervisor.toml`.
3. Register every source tree as canonical checkout, Git worktree, or execution
   mirror. Do not create ad-hoc repo copies.
4. Record one writable lease per lane in `docs/parallel-sessions/TEAM_PLAN.md`
   or the lane spec: host, branch/worktree, and paths.
5. Move source changes through Git branches, PRs, or patches. Use rsync only for
   artifacts/logs or a declared one-way mirror.
6. If two panes appear to own the same branch, worktree, or writable path, both
   panes stop and hand off evidence to the validator.

## Iteration rule

Each lane performs one bounded iteration:

1. Re-read this shared protocol and the lane spec.
2. Inspect current host, `pwd`, branch, worktree list, and repo state before
   editing.
3. Confirm the lane owns the branch/worktree and writable scope listed in the
   lane spec or `TEAM_PLAN.md`.
4. Pick the smallest useful task from the lane spec or queue.
5. Confirm the task maps to a `TEAM_PLAN.md` acceptance item or blocker.
6. Make focused changes only inside the lane's writable scope.
7. Run the lane's required verification.
8. Commit or write a clear handoff note if the lane spec requires it.
9. End the goal when the iteration is complete, blocked, or near the timebox.

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
- host, path, branch/worktree, and lane lease used,
- checklist item or blocker addressed,
- verification commands and results,
- blockers,
- next suggested task.

Prefer repo files, commits, issue comments, or a short handoff note over chat
history. Chat history may disappear when the next iteration starts fresh.
