# Batch Version / PR Train Board

This file is owned by VALIDATOR or RELEASE_LEAD. Copy it into a project as
`docs/parallel-sessions/VERSION_BOARD.md`.

## Current train

- Batch outcome:
- Base branch:
- Integration branch: `batch/<date>-<slug>`
- Planned PR title:
- Release owner: `VALIDATOR` or `RELEASE_LEAD`
- Split decision: `single_batch_pr` unless an exception below applies

## PR grouping policy

Default: worker branches and small commits are integrated into the batch branch;
only the batch branch opens a normal review-facing PR.

Allowed exceptions:

- `hotfix`: urgent production/security/revert path.
- `independent_release`: must ship separately from the current batch.
- `risk_isolation`: migration, live-ops, security, or rollback-sensitive change.
- `review_size`: current train is too large to review safely.

Document every exception in the table below before opening a separate PR.

## Worker branch intake

| Worker branch / commit | Lane | Checklist ID | Intake status | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| `work/<batch>/<lane>-<task>` | `<lane>` | `<A#>` | open | `<test/report/log>` | `<why included or rejected>` |

Statuses: `open`, `accepted`, `rejected`, `needs_followup`, `deferred`.

## Integration ledger

| Commit / artifact | Source lane | Integrated into batch? | Verification | Reviewer note |
| --- | --- | --- | --- | --- |
| `<sha or file>` | `<lane>` | no | `<command>` | `<risk / context>` |

## Separate PR exceptions

| PR / branch | Reason | Owner | Approval / evidence |
| --- | --- | --- | --- |
| `<link or branch>` | `<hotfix|independent_release|risk_isolation|review_size>` | `<lane>` | `<who approved and why>` |

## Final batch PR checklist

- [ ] `TEAM_PLAN.md` acceptance rows are accepted or explicitly blocked.
- [ ] All accepted worker commits are on `batch/<date>-<slug>`.
- [ ] Rejected/deferred worker commits are documented above.
- [ ] Conflicts are resolved by the release owner, not silently by workers.
- [ ] Targeted tests passed.
- [ ] Batch-level verification passed or blocker is documented.
- [ ] PR body links this board, artifacts, verification, and split exceptions.
- [ ] Temporary worker branches are deleted or intentionally retained.
