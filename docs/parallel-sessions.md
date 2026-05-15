# Compact-safe parallel session protocol

This is the shared protocol that every lane prompt should reference. Keep this
file short enough for each agent to re-read at the start of every iteration.
Put lane-specific details in `docs/parallel-sessions/<lane>.md`.

For any project that can run panes on multiple hosts, this file must also
import the distributed constitution in `docs/distributed-protocol.md`: one
project identity, no anonymous source copies, one writable lease per scope, and
fail-closed behavior when host/path/branch ownership is unclear.

For every active project, also use the AI factory model in
`docs/ai-factory.md`: one batch outcome, one GM/validator-owned factory board,
and queue items that converge on accepted artifacts rather than unrelated lane
outputs.

For company-style runs, also apply `docs/company-operating-model.md`: each pane
has a role type, decision rights, manager / escalation lane, DRI checklist rows,
and a writable lease. GM is a real Codex session; managers own teams; dynamic
workers are capacity, not accountability.

For version control, apply `docs/version-management.md`: workers may produce
atomic commits on leased worker branches, but ordinary review-facing PRs are
opened from the batch branch after VALIDATOR/RELEASE_LEAD accepts the work into
`docs/parallel-sessions/VERSION_BOARD.md`.

For worker-to-worker communication, apply `docs/worker-communication.md`.
Workers coordinate through `TEAM_PLAN.md`, `meeting_sheet.md`, and lane journals
under `docs/parallel-sessions/journals/`. Shared files require a short
manager-owned lock row before edits, so two sessions do not write the same plan,
queue, meeting sheet section, or source scope at the same time.

## Operator -> GM -> teams launch flow

The human-facing AI session is the operator. It chooses the project/host,
checks resources, and either books a LUNARC station node or uses an available
laptop/local host. It must start the General Manager layer before scaling
worker teams:

```bash
csup gm-start <project> --host=<host> --dry-run
csup gm-start <project> --host=<host> --apply
```

`gm-start` launches the fixed General Manager layer first (`GM`, `DEBUG`, and
`VALIDATOR`, with zero dynamic workers). The GM is a normal Codex pane. It reads
project plans, markdown, queues, reports, and work done so far; then it decides
which teams should exist, which managers own them, whether to add/reduce/move
workers, and what direction managers should communicate to their teams. After
that review, GM or the operator uses measured staffing commands:

```bash
csup staff <project> --host=<host> --scenario=resume --dry-run
csup staff <project> --host=<host> --scenario=resume --apply
csup steward <project>
```

This keeps the chain of command explicit: operator allocates resources; GM sets
direction and staffing posture; managers translate GM direction into leases,
acceptance rows, and worker `/goal` tickets; workers execute one bounded task.

## Prompt rule

The prompt file is only a router. Each prompt must start with `/goal`, use 50
words or fewer, and point to this file plus a lane markdown file. Do not put
long instructions, file lists, or implementation plans directly in the prompt.

## Fixed project lanes

Every active project should have three fixed panes:

- `GM`: acts as the project executive Codex session. It owns direction, team
  structure, priorities, resource decisions, and escalations.
- `DEBUG`: debugs and optimizes one code slice at a time.
- `VALIDATOR`: acts as the default team manager. It validates results from
  workers, keeps `docs/parallel-sessions/TEAM_PLAN.md` current, records blockers,
  reports status to GM, and queues the next smallest prompts for dynamic or
  specified worker lanes.

`codex-supervisor` generates these lanes by default when the prompt file does
not already define equivalent `gm`/`general-manager`/legacy `ceo`, `debug`/`optimizer`, and
`validator`/`planner`/`leader` lanes.

For distributed projects, the validator also owns the live host/lane lease ledger:
which host is active, which source tree is canonical/worktree/mirror, which
branch/worktree each lane owns, and which paths are read-only for everyone else.

The GM and validator own the factory board at
`docs/parallel-sessions/TEAM_PLAN.md`. Before worker lanes start, that board
should declare the batch outcome, acceptance checklist, artifact ledger,
role roster, lane/lease table, queue policy, and blockers. Workers treat the
board as the source of truth for what "done" means.

The meeting sheet and journals are the source of truth for worker communication:
workers append to `docs/parallel-sessions/journals/<lane>.md`, ask cross-lane
questions in `docs/parallel-sessions/meeting_sheet.md`, and let managers merge
validated facts into `TEAM_PLAN.md`.

The validator or RELEASE_LEAD owns the version board at
`docs/parallel-sessions/VERSION_BOARD.md`. Before workers open or request any
PR, the board should declare whether the work belongs in the current
`batch/<date>-<slug>` PR train or has a documented split/hotfix exception.

## Company role model

Every pane is one of:

- `fixed-executive`: `GM`; accountable for direction, teams, priorities,
  resources, and escalations.
- `fixed-management`: `VALIDATOR` or named managers; accountable for team
  ownership, leases, queues, worker next steps, and acceptance.
- `fixed-quality`: `DEBUG`; accountable for focused risk reduction and code
  quality inside a leased slice.
- `specified-lead`: a named functional lead such as `TECH_LEAD`,
  `RESEARCH_LEAD`, `OPS_LEAD`, `DATA_LEAD`, `RELEASE_LEAD`, or
  `SECURITY_REVIEWER`.
- `dynamic-worker`: generic capacity that pulls one blockers/open task and
  returns evidence.
- `specialist-contractor`: remote executor or read-only verifier for tests,
  backfills, audits, or platform-specific checks.

Every team must have at least one manager and at least one worker or
worker-equivalent executor. Managers report to GM; workers report to their
manager. Use specified leads sparingly. If a task can be expressed as one generic queue
item with a clear lease, assign it to a dynamic worker instead of creating a
new permanent lane.

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
5. Move source changes through Git branches, patches, and the batch PR train.
   Worker branches do not become normal PRs unless `VERSION_BOARD.md` records an
   exception. Use rsync only for artifacts/logs or a declared one-way mirror.
6. If two panes appear to own the same branch, worktree, or writable path, both
   panes stop and hand off evidence to the validator.

## Iteration rule

Each lane performs one bounded iteration:

1. Re-read this shared protocol and the lane spec.
2. Inspect current host, `pwd`, branch, worktree list, and repo state before
   editing.
3. Confirm the lane owns the branch/worktree and writable scope listed in the
   lane spec or `TEAM_PLAN.md`.
4. Confirm the lane's role type, decision rights, and manager/escalation path.
5. Pick the smallest useful task from the lane spec or queue.
6. Confirm the task maps to a `TEAM_PLAN.md` acceptance item or blocker.
7. Make focused changes only inside the lane's writable scope.
8. Run the lane's required verification.
9. Commit or write a clear handoff note if the lane spec requires it.
10. End the goal when the iteration is complete, blocked, or near the timebox.

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
