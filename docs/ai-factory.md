# AI factory operating model

`codex-supervisor` is not just a pane launcher. Treat it as a small AI factory:
one visible outcome, a shared production board, many bounded workers, and one
validator that accepts or rejects finished work.

## Factory invariants

1. **One batch outcome.** Every running project declares the current outcome in
   `docs/parallel-sessions/TEAM_PLAN.md` before workers start.
2. **Prompt-to-artifact flow.** Work enters through queue files, but acceptance
   happens against artifacts: commits, PRs, reports, generated files, logs,
   tests, or explicit blocker notes.
3. **Validator owns convergence.** The VALIDATOR lane updates the plan,
   assigns leases, verifies evidence, and queues the next smallest task. It is
   the only lane allowed to redefine the batch outcome.
4. **Workers do not invent parallel products.** Workers may propose follow-up
   tasks, but they should not pursue side quests or create unscheduled artifacts
   unless the factory board or queue points there.
5. **No green proxy status.** `DONE`, a quiet pane, or passing local tests are
   useful signals only after the validator maps them to the batch checklist.
6. **Queues shrink toward acceptance.** New tasks should close an acceptance
   gap, verify an artifact, or remove a blocker. If a queue item cannot be tied
   to the outcome, leave it for the validator instead of doing it.
7. **Blockers are stop-the-line work.** If a common blocker prevents the batch
   from being accepted, the validator queues it in `codex-tasks/blockers.txt`
   and workers prioritize it before ordinary open work.
8. **Management audits are first-class.** Run `csup factory-audit <project>` to
   classify each configured host as `GREEN`, `YELLOW`, or `RED` before launching
   more work. `RED` means missing factory docs or unresolved shared blockers.

## Required factory board

Each project should keep `docs/parallel-sessions/TEAM_PLAN.md` with these
sections. Copy `templates/TEAM_PLAN.md` when bootstrapping a project.

- **Batch outcome:** one sentence that says what will be true when the batch is
  accepted.
- **Acceptance checklist:** concrete checks that prove the outcome, with owner,
  status, and evidence path/command.
- **Artifact ledger:** the files, branches, PRs, reports, logs, and datasets
  workers are expected to produce or verify.
- **Lane/lease table:** host, role, source tree, branch/worktree, writable
  scope, and current status for every active lane.
- **Queue policy:** which queue files exist and why each task belongs there.
- **Blockers/decisions:** unresolved facts that stop acceptance, plus the next
  action needed to resolve each one.

## Factory loop

1. Operator or validator writes the batch outcome and acceptance checklist.
2. Validator allocates leases and queues compact `/goal` tickets.
3. Dynamic/specialized workers complete exactly one ticket and leave evidence.
4. Validator audits evidence against the checklist, marks accepted/rejected, and
   queues only the next smallest acceptance gap.
5. Shared blockers go to `codex-tasks/blockers.txt` before any new lane-local
   progress tasks are queued.
6. The batch ends only when every checklist item is accepted or explicitly
   blocked with evidence.

## Management audit

Use the system manager gate before starts, restarts, and daily reviews:

```bash
csup factory-audit <project>
csup factory-audit --project=<project>
```

The audit checks factory docs, `docs/blocker-schema.md`, prompt counts, shared
blocker queue depth, open queue depth, and lane queue depth. Treat results as:

- `RED`: missing factory docs or shared blockers exist. Resolve blockers before
  lane-local expansion.
- `YELLOW`: no shared blockers, but acceptance-gap work remains queued.
- `GREEN`: no shared blockers and no queued work; validator should confirm the
  batch is accepted or queue the next acceptance gap.

Use `docs/blocker-schema.md` for blocker queue lines so code, data, approval,
infra, empirical, and external blockers are not flattened into one status.

## Worker fallback when a queue is empty

Do not create unrelated work to keep a pane busy. If your queue is empty:

1. Read `TEAM_PLAN.md` and identify the smallest unchecked acceptance item in
   your writable scope.
2. If none exists, write a short handoff/proposed queue item for VALIDATOR.
3. If the batch is accepted or all remaining gaps are outside your lease, stop.

This keeps workers productive without letting them drift away from the shared
outcome.
