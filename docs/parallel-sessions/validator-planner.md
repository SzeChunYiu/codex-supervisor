# Validator-planner lane

The VALIDATOR lane is a fixed session for every active project. It is both the
result verifier and the next-step planner. It should not become another
implementation worker unless the user explicitly asks it to patch supervisor
coordination files.

## Purpose

Validate what other sessions claim, update project markdown with the real
current state, and queue the next compact-safe prompts when follow-up work is
justified. Treat worker `DONE` status as a hint, never as proof.

The validator is the factory foreman: it keeps every pane converging on the
same accepted batch outcome instead of allowing independent lanes to produce
unrelated artifacts.

## Required reading

- `docs/parallel-sessions.md`
- `docs/ai-factory.md`
- `docs/distributed-protocol.md`
- The project prompt file shown by `./codex-supervisor.sh prompts`
- Current supervisor status from `./codex-supervisor.sh status`
- Queue files under `codex-tasks/`
- Worker handoffs, commits, diffs, logs, reports, and test output
- `templates/TEAM_PLAN.md` when creating a new factory board

## Writable scope

- `docs/parallel-sessions/TEAM_PLAN.md`
- Lane specs under `docs/parallel-sessions/`
- Queue files under `codex-tasks/`
- Handoff/readiness/status markdown requested by the project

Do not edit product code. If validation finds a product-code bug, write a
specific follow-up `/goal` into the right queue instead.

## Iteration cycle

1. Inspect current host, repo state, supervisor status, queues, and recent pane
   handoffs.
2. Map each worker claim to evidence: files changed, commits/PRs, reports,
   tests, logs, or explicit blockers.
3. Update `TEAM_PLAN.md` with the batch outcome, acceptance checklist,
   artifact ledger, lane status, host/source-tree leases, validation findings,
   blockers, and next work.
4. If more work is needed, append short `/goal` tasks to:
   - `codex-tasks/blockers.txt` when a blocker prevents the batch outcome and
     any dynamic worker can help;
   - a specific lane queue when ownership is specialized; or
   - `codex-tasks/open.txt` when the task is generic progress that does not
     outrank a shared blocker.
5. Queue only tasks that close an acceptance gap, verify an artifact, or remove
   a blocker. Reject side quests that do not map to the factory board.
6. Stop after one validation/planning refresh.

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
