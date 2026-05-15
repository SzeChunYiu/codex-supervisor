# Worker communication and write-safety protocol

Workers communicate through project files, not hidden side channels. The goal is
shared context without concurrent writes or source conflicts.

## Required communication surfaces

Every active project should have these files:

- `docs/parallel-sessions/TEAM_PLAN.md` — manager-owned source of truth for
  outcome, teams, leases, checklist rows, artifact ledger, staffing, and queue
  policy.
- `docs/parallel-sessions/meeting_sheet.md` — manager-owned meeting board for
  cross-worker questions, decisions, handoffs, and dependency notes.
- `docs/parallel-sessions/journals/<lane>.md` — one append-only journal per
  lane. Each worker writes only its own journal unless a manager grants a
  temporary lock.
- `docs/parallel-sessions/journals/gm.md` — the General Manager's short
  reflection journal for reusable process lessons, staffing decisions, and
  system improvements that can benefit other projects.

## Context-size limits

Communication files must stay small enough for fresh panes to read without
wasting context:

- `TEAM_PLAN.md`: target under 200 lines. Keep only the current batch board;
  move old accepted rows to `docs/parallel-sessions/archive/`.
- `meeting_sheet.md`: target under 120 lines. Keep only open/recent rows; move
  resolved rows to `docs/parallel-sessions/archive/meeting_sheet-<date>.md`.
- `journals/<lane>.md`: target under 120 lines per lane. Keep the latest
  entries needed for handoff; move older entries to
  `docs/parallel-sessions/archive/journals/<lane>-<date>.md`.
- Queue files: keep one compact `/goal` per line and move narrative detail into
  the smallest relevant markdown section.

If a communication file exceeds its limit, the manager should summarize,
archive, and leave a short pointer before asking workers to read it.

## Write ownership

| Surface | Writer | Readers | Conflict rule |
| --- | --- | --- | --- |
| `TEAM_PLAN.md` | GM, VALIDATOR, named managers | everyone | Managers serialize edits; workers propose changes in journals/meeting sheet. |
| `meeting_sheet.md` | GM, VALIDATOR, named managers; workers only in their assigned row | everyone | Add rows by lane; do not edit another lane's row. |
| `journals/<lane>.md` | that lane only | everyone | Append-only; never rewrite another lane journal. |
| source files | one leased worker/lead | everyone else read-only | One writable lease per branch/worktree/path from `TEAM_PLAN.md`. |

## Lock before shared writes

Before editing any shared coordination file (`TEAM_PLAN.md`, `meeting_sheet.md`,
queue files, or version boards), a manager must create or claim a row in the
TEAM_PLAN communication/lock table:

```text
lock_id=<lane>-<timestamp> file=<path> owner=<lane> scope=<section> expires=<UTC>
```

Rules:

1. Never edit a shared file if an unexpired row for the same file/scope belongs
   to another lane.
2. Keep locks small: one section or queue file, one short edit, then release.
3. Workers do not take shared-file locks by default; they append to their own
   journal and ask a manager to merge the decision.
4. If a stale lock blocks progress, escalate in `meeting_sheet.md`; GM or
   VALIDATOR may release it after checking pane status.
5. Source-code writes still require the normal branch/worktree/path lease.

## Meeting sheet row format

Use one row per cross-lane interaction:

```markdown
| Time | From | To | Topic | Request / decision | Linked checklist | Status |
```

Workers use it for dependency questions and handoffs. Managers use it to answer,
route, accept/reject, or escalate to GM.

## Journal entry format

Each worker appends:

```markdown
## <UTC time> — <lane> — <task/checklist id>
- Read: <files/reports>
- Did: <artifact/commit/report>
- Need from others: <meeting_sheet row or none>
- Lock/lease used: <TEAM_PLAN row>
- Verification: <command/result>
- Next suggestion: <manager queue item or none>
```

## Operating rhythm

1. GM reads `TEAM_PLAN.md`, `meeting_sheet.md`, journals, queues, and reports
   before changing team structure or staffing.
2. GM writes short reflection entries in `journals/gm.md` after management
   cycles and archives old lessons before the journal grows long.
3. Managers merge worker journal facts into `TEAM_PLAN.md` after validation.
4. Managers archive or summarize oversized communication files before assigning
   new workers, so prompt inputs stay compact.
5. Workers read `TEAM_PLAN.md`, `meeting_sheet.md`, and relevant journals before
   starting a task.
6. Workers write only their own journal and leased source scope; managers handle
   shared plan/queue writes unless explicitly delegated.
