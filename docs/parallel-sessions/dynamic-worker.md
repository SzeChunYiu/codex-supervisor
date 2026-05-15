# Dynamic worker lane

Dynamic workers are the flexible worker pool. A project may run N of them in
addition to the three fixed lanes: GM, DEBUG, and VALIDATOR. Dynamic workers take open
tasks that do not require a specialized lane.

## Purpose

Complete one queued open task safely, using the project protocol and the lease
ledger. If the task names a specialized lane, host, branch, or writable scope
that this worker does not own, stop and hand it back to the validator-planner.

Dynamic workers are factory workers, not independent product owners. Their
output should close one `TEAM_PLAN.md` acceptance gap, verify one artifact, or
remove one blocker.

In the company model, a dynamic worker is flexible capacity, not a permanent
department. It receives one DRI-routed task, works within a lease, produces
evidence, and escalates back to its manager (usually VALIDATOR), which reports to GM when ownership or priority is unclear.

## Required reading

- `docs/parallel-sessions.md`
- `docs/ai-factory.md`
- `docs/company-operating-model.md`
- `docs/version-management.md`
- `docs/worker-communication.md`
- `docs/distributed-protocol.md` for multi-host projects
- `docs/parallel-sessions/TEAM_PLAN.md`
- `docs/parallel-sessions/meeting_sheet.md`
- Relevant `docs/parallel-sessions/journals/*.md`
- `docs/parallel-sessions/VERSION_BOARD.md`
- The markdown file referenced by the queued `/goal`

## Queue source

Dynamic workers primarily consume:

- `codex-tasks/blockers.txt` (first priority: shared blockers that stop the
  batch outcome)
- `codex-tasks/blocker.txt` (alias for the same priority)
- `codex-tasks/open.txt`
- `codex-tasks/worker.txt`
- `codex-tasks/workers.txt`
- `codex-tasks/dynamic.txt`

They may also consume a worker-specific queue such as
`codex-tasks/worker-1.txt`, but shared blocker queues outrank worker-specific
tasks. After blockers clear, worker-specific queues are honored before ordinary
shared open queues. Dynamic workers should not consume specialized lane queues
unless their prompt or `TEAM_PLAN.md` explicitly grants that lease.

## Iteration cycle

1. Re-read the required protocol docs and the queued task.
2. Run the worker preflight: host, `pwd`, branch, remote, worktree list, and
   writable lease.
   Also read `meeting_sheet.md` and your lane journal to catch dependency
   questions before editing.
3. Confirm the task is generic or explicitly assigned to this worker.
4. Confirm which `TEAM_PLAN.md` checklist item, artifact, or blocker this task
   advances. If none, stop and propose a validator queue item instead of
   inventing unrelated work.
5. Complete one compact-safe patch or artifact.
6. Commit only on the leased worker branch/worktree. Do not open a normal PR
   unless `VERSION_BOARD.md` explicitly records a split/hotfix exception.
7. Run the task's targeted verification.
8. Append one entry to `docs/parallel-sessions/journals/<lane>.md`. Do not edit
   another lane's journal or shared plan files unless your manager granted a
   lock in `TEAM_PLAN.md`.
9. Stop with a handoff: host/path/branch, checklist item, changed files,
   verification, blocker, and next task suggestion.

## Stop rule

Stop after one open task, when the task needs a specified lane, or when the
lease/source-tree state is ambiguous. If your queue is empty, inspect
`TEAM_PLAN.md`; if no unchecked acceptance item fits your lease, leave a
validator handoff and stop rather than producing side work.

## Empty-queue need discovery

Dynamic workers are allowed to identify needs, but only inside the
validator-owned factory board:

1. Read the current batch outcome and acceptance checklist in `TEAM_PLAN.md`.
2. Pick the smallest unchecked row that is inside your writable lease.
3. If a queue item already exists for it, take exactly that item.
4. If no queue item exists, write a proposed `/goal` line and evidence note for
   VALIDATOR instead of silently starting new work.
5. If your last task is done, expect to be recycled into the current highest
   priority role; do not assume your old lane remains the best use of capacity.
