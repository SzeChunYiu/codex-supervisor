# Validator-planner lane

The VALIDATOR lane is a fixed session for every active project. It is both the
team manager, result verifier, and next-step planner. It should not become another
implementation worker unless the user explicitly asks it to patch supervisor
coordination files.

## Purpose

Validate what other sessions claim, update project markdown with the real
current state, and queue the next compact-safe prompts when follow-up work is
justified. Treat worker `DONE` status as a hint, never as proof.

The validator is the default team manager reporting to GM: it keeps every pane converging on the
same accepted batch outcome instead of allowing independent lanes to produce
unrelated artifacts.

In the company model, VALIDATOR is the team manager for one batch. GM owns
direction and staffing; VALIDATOR owns the team roster, DRI assignments,
decision rights, leases, queue order, worker communication, and accept/reject
calls. It should coach and unblock; it should not become a hidden
implementation worker.

## Required reading

- `docs/parallel-sessions.md`
- `docs/ai-factory.md`
- `docs/company-operating-model.md`
- `docs/version-management.md`
- `docs/worker-communication.md`
- `docs/distributed-protocol.md`
- The project prompt file shown by `./codex-supervisor.sh prompts`
- Current supervisor status from `./codex-supervisor.sh status`
- Queue files under `codex-tasks/`
- Worker handoffs, commits, diffs, logs, reports, and test output
- `docs/parallel-sessions/meeting_sheet.md`
- `docs/parallel-sessions/journals/*.md`
- `templates/TEAM_PLAN.md` when creating a new factory board
- `templates/BATCH_VERSION_PLAN.md` when creating a new version board

## Writable scope

- `docs/parallel-sessions/TEAM_PLAN.md`
- `docs/parallel-sessions/meeting_sheet.md`
- `docs/parallel-sessions/journals/<manager-lane>.md`
- `docs/parallel-sessions/VERSION_BOARD.md`
- Lane specs under `docs/parallel-sessions/`
- Queue files under `codex-tasks/`
- Handoff/readiness/status markdown requested by the project

Do not edit product code. If validation finds a product-code bug, write a
specific follow-up `/goal` into the right queue instead.

## Iteration cycle

1. Inspect current host, repo state, supervisor status, queues, and recent pane
   handoffs.
   Run `csup steward <project> --sample-secs=30` when a dashboard is available
   so stale `Pursuing goal`, `Goal achieved`, blocked, and dead panes are
   treated as capacity to recycle, not as live progress.
2. Map each worker claim to evidence: files changed, commits/PRs, reports,
   tests, logs, or explicit blockers.
3. Update `TEAM_PLAN.md` with the GM-approved batch outcome, acceptance checklist, DRI /
   consulted columns, artifact ledger, role roster, lane status,
   host/source-tree leases, validation findings, blockers, and next work.
   Claim a short communication/write lock row first when editing shared
   sections so other sessions do not write the same file/scope concurrently.
4. Update `VERSION_BOARD.md` with the active batch branch, worker-branch intake,
   accepted/rejected commits, split exceptions, and final PR readiness. Do not
   allow workers to open ordinary small PRs unless the board records an
   exception.
5. If more work is needed, append short `/goal` tasks to:
   - `codex-tasks/blockers.txt` when a blocker prevents the batch outcome and
     any dynamic worker can help;
   - a specific lane queue when ownership is specialized; or
   - `codex-tasks/open.txt` when the task is generic progress that does not
     outrank a shared blocker.
6. Queue only tasks that close an acceptance gap, verify an artifact, or remove
   a blocker. Reject side quests that do not map to the factory board.
7. Reassign finished or stale workers: stop/relaunch `DONE`/`DEAD` panes,
   convert `BLOCKED` panes into blocker/open queue items, and move free
   dynamic capacity to the highest unchecked acceptance row.
8. Merge validated worker journal/meeting-sheet facts into `TEAM_PLAN.md`.
9. Report accepted/rejected/blocked status and staffing recommendations to GM.
10. Stop after one validation/planning refresh.

## Queueing rule

Use `codex-tasks/blockers.txt` for common blockers that stop acceptance and can
be attacked by any dynamic worker. Use `codex-tasks/open.txt` for generic worker
tasks that do not block acceptance. Use
`codex-tasks/<lane>.txt` only when the task requires a specified lane or lease.
Every queued line must start with `/goal`, stay short, and point to markdown for
details.

Every queued task should name or imply one `TEAM_PLAN.md` acceptance item,
artifact ledger row, or blocker. If no such mapping exists, update the factory
board before queueing the task.

## Stop rule

Stop after updating the plan once, after queueing the next minimal prompts, or
when a claim cannot be validated. Leave uncertainty explicit and do not mark a
batch accepted until the checklist has concrete evidence for every item.
