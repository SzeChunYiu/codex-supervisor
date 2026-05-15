# Team Plan / AI Factory Board

This file is owned jointly by the GM and VALIDATOR lanes. GM owns direction,
manager staffing, and escalation; VALIDATOR owns acceptance, leases, queues,
and worker handoffs. Treat this as the project's company board: outcome,
teams, accountable DRIs, role charters, leases, artifacts, queues, and blockers.

## Batch outcome

> Replace with one concrete sentence: "When this batch is accepted, ..."

## Acceptance checklist

| ID | Requirement / acceptance check | DRI / owner | Consulted | Status | Evidence |
| --- | --- | --- | --- | --- | --- |
| A1 | GM defines the outcome, team roster, and required artifacts before workers start. | GM | VALIDATOR, DEBUG, leads | open | this file |

Statuses: `open`, `in_progress`, `accepted`, `rejected`, `blocked`.

## Artifact ledger

| Artifact | Producer lane | Consumer / verifier | Status | Link or command |
| --- | --- | --- | --- | --- |
| `<file/PR/report/log>` | `<lane>` | VALIDATOR | open | `<path or command>` |

## Version / PR train

Copy `templates/BATCH_VERSION_PLAN.md` to
`docs/parallel-sessions/VERSION_BOARD.md` and keep it synchronized here.

| Field | Value |
| --- | --- |
| Base branch | `<main>` |
| Batch branch | `batch/<date>-<slug>` |
| Review-facing PR policy | one PR for the accepted batch |
| Separate PR exceptions | `<none or link to VERSION_BOARD.md row>` |

Workers may create atomic commits on leased worker branches, but they do not
open ordinary PRs unless VALIDATOR/RELEASE_LEAD records an exception in the
version board.

## Role roster

| Lane | Role type | Manager / escalation | Decision rights | Primary outputs | Status |
| --- | --- | --- | --- | --- | --- |
| GM | fixed-executive | human/operator | project direction, team roster, priority, resource trade-offs | executive decisions, manager priorities, escalations | active |
| VALIDATOR | fixed-management | GM | acceptance, queues, leases, worker next steps | accepted/rejected checklist rows, manager report, next prompts | active |
| DEBUG | fixed-quality | VALIDATOR | code-quality findings inside leased slice | small fix, test, or review blocker | queued |
| REVIEWER | fixed-review | MANAGER / VALIDATOR | simulated-user review and workspace-contract checks | queued defects, review evidence, pass/fail report | queued |
| WORKER-1 | dynamic-worker | VALIDATOR | one assigned generic task | patch/report/handoff with evidence | queued |

Role types: `fixed-executive`, `fixed-management`, `fixed-quality`,
`fixed-review`, `specified-lead`, `dynamic-worker`, `specialist-contractor`. Copy
`templates/ROLE_CHARTER.md` for lanes that need more detail.

## Staffing ledger

GM owns this table. Every add/reduce/move decision must cite demand, capacity,
manager readiness, and the command/evidence used.

| Time | Decision | Demand signal | Node/resource signal | Manager readiness | Command/evidence | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `<time>` | `<hold/add/reduce/move>` | `<queue/checklist>` | `<capacity/steward>` | `<manager>` | `<csup staff ...>` | open |

## Lane and lease table

| Lane | Host | Role | Source tree | Branch/worktree | Writable scope | Status |
| --- | --- | --- | --- | --- | --- | --- |
| GM | `<host>` | executive | canonical checkout | main | strategy docs, TEAM_PLAN, gm queue | active |
| DEBUG | `<host>` | debugger | `<canonical/worktree/mirror>` | `<branch/path>` | one reviewed slice + adjacent tests | queued |
| VALIDATOR | `<host>` | manager/validator | canonical checkout | main | coordination docs, queues | active |
| REVIEWER | `<host>` | reviewer | `<canonical/worktree/mirror>` | `<branch/path>` | reports, tests, screenshots, defect queues | queued |
| WORKER-1 | `<host>` | local-writer | registered worktree | `<branch/path>` | `<paths>` | queued |

## Communication and write-lock table

Managers own shared coordination file writes. Workers append to their own
journal and request shared updates through the meeting sheet unless a manager
grants a short lock here.

| Lock ID | File / scope | Owner lane | Purpose | Acquired UTC | Expires UTC | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `<lane>-<timestamp>` | `TEAM_PLAN.md#section` | `<lane>` | `<short edit>` | `<UTC>` | `<UTC>` | open |

Communication surfaces:

- `docs/parallel-sessions/meeting_sheet.md`: cross-lane questions, decisions,
  blockers, and handoffs.
- `docs/parallel-sessions/journals/<lane>.md`: append-only lane journal.
- `docs/parallel-sessions/journals/gm.md`: GM reflection journal for reusable
  management lessons, staffing decisions, and process improvements.
- `docs/worker-communication.md`: protocol for locks, journals, and meeting
  sheet rows.

Context budget:

- Keep this file under 200 lines for the active batch.
- Keep `meeting_sheet.md` under 120 lines.
- Keep each `journals/<lane>.md` under 120 lines.
- Keep `journals/gm.md` under 120 active lines and archive reusable lessons by
  date when they no longer need to be in every fresh prompt.
- Archive old rows under `docs/parallel-sessions/archive/` and leave short
  pointers instead of making every worker read long history.

## Queue policy

- `codex-tasks/gm.txt`: executive decisions, staffing changes, and escalations that
  only the GM lane or human/operator should resolve.
- `codex-tasks/blockers.txt`: common blockers that prevent accepting the batch
  outcome and can be attacked by any dynamic worker. This queue outranks normal
  open work.
- `codex-tasks/open.txt`: generic tasks that any dynamic worker can complete.
- `codex-tasks/<lane>.txt`: tasks that need a specific lane, host, branch, or
  writable lease.
- Every queued `/goal` should cite a markdown doc or checklist item and should
  close one acceptance gap.

## Decisions and blockers

| ID | Blocker / decision | Impact | Next action | Owner | Status |
| --- | --- | --- | --- | --- | --- |
| B1 | `<unknown fact>` | `<what cannot be accepted>` | `<smallest unblocker; queue in codex-tasks/blockers.txt if generic>` | `<lane>` | open |

## GM / manager audit log

Append one short entry per validation refresh:

```text
YYYY-MM-DD HH:MMZ gm: reviewed teams; decision=<staffing/priority/escalation>.
YYYY-MM-DD HH:MMZ validator: checked <artifact>; accepted/rejected/blocked because <evidence>.
```

## Worker handoff format

```text
Lane:
Host/path/branch:
Task/checklist item:
Changed artifacts:
Verification:
Accepted by worker? yes/no/blocked
Next suggested validator action:
```
