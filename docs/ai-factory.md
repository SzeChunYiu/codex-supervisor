# AI factory operating model

`codex-supervisor` is not just a pane launcher. Treat it as a small AI factory
and company: one visible outcome, a shared production board, explicit pane
roles, a real GM Codex session, manager-owned teams, bounded workers, and
one validator/manager chain that accepts or rejects finished work.

> **Read first:** [`productivity-contract.md`](./productivity-contract.md). Every
> project under codex-supervisor MUST follow it. Without it, this factory
> reliably produces audit/planning churn instead of shipped product. The
> contract pins each layer (worker, manager, CEO, git hook) to one measurable
> rule: every iteration commits a source-code change against the project's
> `GOAL.md`, or it doesn't count.

## Factory invariants

1. **One batch outcome.** Every running project declares the current outcome in
   `docs/parallel-sessions/TEAM_PLAN.md` before workers start.
2. **Prompt-to-artifact flow.** Work enters through queue files, but acceptance
   happens against artifacts: commits, PRs, reports, generated files, logs,
   tests, or explicit blocker notes.
3. **GM owns direction; managers own convergence.** The GM lane sets
   project direction, priorities, staffing, and escalations. VALIDATOR or a
   named manager updates the plan, assigns leases, verifies evidence, reports
   to GM, and queues the next smallest task.
4. **Every pane has a role charter.** Executive, management, specified, dynamic, and specialist
   panes each declare decision rights, writable leases, outputs, manager /
   escalation lane, and stop rule. Use `docs/company-operating-model.md` and
   `templates/ROLE_CHARTER.md`.
5. **Every active team has a reviewer.** Team starts reserve a REVIEWER lane
   alongside the MANAGER. The reviewer runs simulated-user or functional checks,
   files defects as queueable `/goal` tickets, and verifies the workspace
   contract in `docs/parallel-sessions/reviewer.md` before trusting artifacts.
6. **One PR per accepted batch.** Workers may use temporary branches and atomic
   commits, but review-facing PRs are grouped through the batch PR train in
   `docs/version-management.md` and `docs/parallel-sessions/VERSION_BOARD.md`.
7. **Workers do not invent parallel products.** Workers may propose follow-up
   tasks, but they should not pursue side quests or create unscheduled artifacts
   unless the factory board or queue points there.
8. **No green proxy status.** `DONE`, a quiet pane, or passing local tests are
   useful signals only after the validator maps them to the batch checklist.
9. **Queues shrink toward acceptance.** New tasks should close an acceptance
   gap, verify an artifact, or remove a blocker. If a queue item cannot be tied
   to the outcome, leave it for the validator instead of doing it.
10. **Blockers are stop-the-line work.** If a common blocker prevents the batch
   from being accepted, the validator queues it in `codex-tasks/blockers.txt`
   and workers prioritize it before ordinary open work.
11. **GM staffing is measured.** Run `csup staff <project>` before adding or
   reducing workers. It uses queue demand and host/node capacity; it recommends
   shrinkage when no queued work remains and only stops sessions with explicit
   `--allow-stop`.
12. **GM starts before teams.** For project create/resume, the operator runs
   `csup gm-start <project>` first. That starts the GM/manager layer with no
   dynamic workers; GM reads plans, work done so far, manager reports, queues,
   and resource signals before teams are opened, closed, reduced, redeployed, or
   expanded with `csup staff`.
13. **Management audits are first-class.** Run `csup factory-audit <project>` to
   classify each configured host as `GREEN`, `YELLOW`, or `RED` before launching
   more work. `RED` means missing factory docs or unresolved shared blockers.

## Required factory board

Each project should keep `docs/parallel-sessions/TEAM_PLAN.md` with these
sections. Copy `templates/TEAM_PLAN.md` when bootstrapping a project.

- **Batch outcome:** one sentence that says what will be true when the batch is
  accepted.
- **Acceptance checklist:** concrete checks that prove the outcome, with owner,
  status, and evidence path/command. Every row has exactly one DRI.
- **Artifact ledger:** the files, branches, PRs, reports, logs, and datasets
  workers are expected to produce or verify.
- **Version board:** the active `batch/<date>-<slug>` branch, worker branch
  intake table, PR grouping decision, split exceptions, and final PR evidence.
- **Role roster and lane/lease table:** fixed GM and management roles, specified
  functional leads, dynamic workers, specialist contractors, host, role, source
  tree, branch/worktree, writable scope, decision rights, manager, and status.
- **Queue policy:** which queue files exist and why each task belongs there.
- **Blockers/decisions:** unresolved facts that stop acceptance, plus the next
  action needed to resolve each one.

## Factory loop

1. GM writes or approves the batch outcome, team roster, and priorities.
2. Managers translate GM direction into acceptance rows, leases, and worker
   tickets. Every active team has at least one manager and one worker.
3. Validator creates or refreshes `VERSION_BOARD.md` for one batch PR train.
4. Managers allocate leases, role charters, and compact `/goal` tickets.
5. Dynamic/specialized workers complete exactly one ticket and leave evidence.
6. Managers audit evidence against the checklist, mark accepted/rejected, report
   to GM, and queue only the next smallest acceptance gap.
7. Accepted worker commits are integrated into the batch branch; workers do not
   open normal PRs unless the version board records an exception.
8. Shared blockers go to `codex-tasks/blockers.txt` before any new lane-local
   progress tasks are queued.
9. The batch ends only when every checklist item is accepted or explicitly
   blocked with evidence.

## Worker communication loop

Use `docs/worker-communication.md` for cross-lane communication and shared-file
write safety:

1. GM and managers read `TEAM_PLAN.md`, `meeting_sheet.md`, lane journals, queue
   files, and reports before changing direction or staffing.
2. Workers read `TEAM_PLAN.md`, `meeting_sheet.md`, and relevant
   `docs/parallel-sessions/journals/<lane>.md` files before starting.
3. Workers append only to their own journal and leased source scope by default.
4. Managers own shared plan, meeting, version, and queue edits. Before editing a
   shared coordination file, they record a lock row in `TEAM_PLAN.md`.
5. If two panes need the same file/scope, one waits or escalates in
   `meeting_sheet.md`; no hidden concurrent writes.

## Management audit

Use the system manager gate before starts, restarts, and daily reviews:

```bash
csup factory-audit <project>
csup factory-audit --project=<project>
csup gm-start <project> --host=<host> --dry-run
csup staff <project> --scenario=resume --dry-run
csup staff <project> --scenario=resume --apply
csup factory-run <project> --scenario=resume --dry-run
csup factory-run <project> --scenario=resume --apply
```

The audit checks factory docs, `docs/blocker-schema.md`,
`docs/parallel-sessions/VERSION_BOARD.md`, prompt counts, shared blocker queue
existence/depth, open queue depth, and lane queue depth. Treat results as:

- `RED`: missing factory docs, missing shared blocker queue, or shared blockers
  exist. Resolve blockers before lane-local expansion.
- `YELLOW`: no shared blockers, but acceptance-gap work remains queued.
- `GREEN`: no shared blockers and no queued work; validator should confirm the
  batch is accepted or queue the next acceptance gap.

Use `docs/blocker-schema.md` for blocker queue lines so code, data, approval,
infra, empirical, and external blockers are not flattened into one status.

## One-command factory resume

AI/operator sessions should prefer `csup factory-run` over ad-hoc `start`,
manual `station`, or manually chosen LUNARC nodes. It is intentionally small and
fail-closed:

- `--dry-run` is the default. It prints the scenario, queued work count, blocker
  count, session count, worker count, and pane count before doing anything.
- If no `/goal` work is queued for the host, it prints
  `HOLD ... reason=no_queued_work` and does not touch SLURM.
- For local hosts, it delegates to `csup govern`, which uses local CPU/RAM/disk
  headroom and opens only the queued lanes that fit.
- For SLURM hosts, it delegates to `csup station`, which packs into existing
  holder allocations before submitting a new slot and never falls back to the
  login node.
- Each project may use at most two computer nodes by default. Maximize panes
  inside those nodes only while `slurm_max_panes`, measured pane usage, and
  load headroom allow it; do not add a third node to compensate for oversized
  lane plans.
- Scenarios are conservative: `resume` starts the smallest useful slice,
  `balanced` can start a second slice, `full` can drain larger queues while
  still respecting slot capacity, and `blockers` runs only shared blocker work.

Examples:

```bash
csup factory-run nnbar --host=recon-lunarc --scenario=resume --dry-run
csup factory-run nnbar --host=recon-lunarc --scenario=resume --apply
csup factory-run neural_grow --host=ng-content-lunarc --max-workers=4 --apply
csup factory-run neural_grow --scenario=blockers --dry-run
```

Use `--sessions`, `--workers`, `--max-workers`, or `--max-panes` only to make a
run smaller or more explicit. These flags do not bypass station capacity, queue,
or login-node safety checks.

## Worker fallback when a queue is empty

Do not create unrelated work to keep a pane busy. If your queue is empty:

1. Read `TEAM_PLAN.md` and identify the smallest unchecked acceptance item in
   your writable scope.
2. If none exists, write a short handoff/proposed queue item for VALIDATOR.
3. If the batch is accepted or all remaining gaps are outside your lease, stop.

This keeps workers productive without letting them drift away from the shared
outcome.

## Self-steering and role recycling

Factory panes are capacity, not permanent jobs. A pane that has completed,
blocked outside its lease, or sat on stale "Pursuing goal" text is inventory
waiting in the system. Recycle it instead of letting it consume attention.

Use this management loop:

1. `GM` owns the **direction ledger**: objective, team roster, priority order,
   and escalations. `VALIDATOR` owns a live **need ledger** in `TEAM_PLAN.md`: unchecked
   acceptance gaps, shared blockers, evidence gaps, and release risks.
2. Run `csup steward <project> --sample-secs=30` during monitoring. It samples
   live pane tails and classifies panes as `ACTIVE`, `DONE`, `BLOCKED`,
   `WAITING_*`, `STALE_WORKING`, or `DEAD`.
3. Reassign in this order: shared blockers, failed acceptance evidence,
   release/validation gates, then normal open work. Do not start side work
   simply because a pane is free.
4. `DONE` and `DEAD` panes should be stopped or relaunched with a fresh compact
   `/goal` from the need ledger. `BLOCKED` panes should create a blocker/open
   queue item with evidence, then stop. `STALE_WORKING` panes require operator
   or validator inspection before more resources are added.
5. If the need ledger is empty, shrink the org. Idle workers are waste; a small
   accepted batch is better than a large busy-looking one.

Workers may "spontaneously" identify project needs only through the factory
board: they read the batch outcome, find the smallest unchecked acceptance
item in their lease, and propose or take that item. They must not invent new
product direction outside the GM/validator-owned board.
