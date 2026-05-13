# Factory blocker schema

Use this schema for every shared blocker queue line or blocker ledger row. The
goal is to stop workers from treating every obstacle as generic "blocked" work.

## Queue line shape

```text
/goal [BID=<id>] [type=code|data|approval|infra|empirical|external] [blocks=<acceptance-id>] [owner=<lane-or-validator>] <short unblocker>. Read docs/parallel-sessions.md and docs/parallel-sessions/AI_FACTORY.md first.
```

## Required fields

- `BID`: stable blocker id, for example `BID=B-004`.
- `type=code|data|approval|infra|empirical|external`: blocker class.
- `blocks`: the `TEAM_PLAN.md` acceptance item or artifact row stopped by this
  blocker.
- `owner`: lane expected to make the next attempt or `VALIDATOR` when routing is
  unclear.

## Type semantics

| Type | Meaning | Valid next action |
| --- | --- | --- |
| `code` | Source/test defect blocks acceptance. | Small patch + targeted verification. |
| `data` | Missing/stale dataset or provenance. | Materialize reachable data or mark data wall. |
| `approval` | Human/maintainer decision required. | Prepare evidence and stop; do not bypass. |
| `infra` | Runtime, CI, cluster, disk, auth, or service issue. | Repair infra or route to operator. |
| `empirical` | Needs live fill, PnL, post-canary, or measured outcome evidence. | Collect evidence; do not claim code completion clears it. |
| `external` | Third-party quota/API/scheduler/market condition. | Monitor or document; do not patch around it blindly. |

## Acceptance rule

A blocker is closed only when `TEAM_PLAN.md` records the evidence path/command
that resolved it, or when it is explicitly downgraded to `external` or
`approval` with the next human decision.
