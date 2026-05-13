# Team Plan / AI Factory Board

This file is owned by the VALIDATOR lane. Workers read it before editing and
write handoffs that the validator can reconcile here.

## Batch outcome

> Replace with one concrete sentence: "When this batch is accepted, ..."

## Acceptance checklist

| ID | Requirement / acceptance check | Owner | Status | Evidence |
| --- | --- | --- | --- | --- |
| A1 | Define the outcome and required artifacts before workers start. | VALIDATOR | open | this file |

Statuses: `open`, `in_progress`, `accepted`, `rejected`, `blocked`.

## Artifact ledger

| Artifact | Producer lane | Consumer / verifier | Status | Link or command |
| --- | --- | --- | --- | --- |
| `<file/PR/report/log>` | `<lane>` | VALIDATOR | open | `<path or command>` |

## Lane and lease table

| Lane | Host | Role | Source tree | Branch/worktree | Writable scope | Status |
| --- | --- | --- | --- | --- | --- | --- |
| DEBUG | `<host>` | debugger | `<canonical/worktree/mirror>` | `<branch/path>` | one reviewed slice + adjacent tests | queued |
| VALIDATOR | `<host>` | validator | canonical checkout | main | coordination docs, queues | active |
| WORKER-1 | `<host>` | local-writer | registered worktree | `<branch/path>` | `<paths>` | queued |

## Queue policy

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

## Validator audit log

Append one short entry per validation refresh:

```text
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
