# Worker communication and restart audit — 2026-05-15

## Objective restatement

Deepen how workers communicate with each other through shared project surfaces
while preventing conflicting simultaneous writes. The system should use
`TEAM_PLAN.md`, lane journals, and `meeting_sheet.md` for coordination; shared
files must have explicit ownership/locks; and current running project management
layers should be restarted so they pick up the new protocol.

## Prompt-to-artifact checklist

| Requirement | Evidence inspected | Status |
| --- | --- | --- |
| Workers communicate through `TEAM_PLAN.md` | `docs/worker-communication.md`, `docs/parallel-sessions.md`, `docs/ai-factory.md`, and `templates/TEAM_PLAN.md` define `TEAM_PLAN.md` as the manager-owned source of truth for outcome, teams, leases, checklist rows, artifact ledger, staffing, and queue policy. | PASS |
| Workers communicate through journals | Added `docs/parallel-sessions/journals/<lane>.md` protocol and `templates/JOURNAL_ENTRY.md`; dynamic workers are required to append their own lane journal before handoff. | PASS |
| Workers communicate through `meeting_sheet.md` | Added `templates/MEETING_SHEET.md`; `docs/worker-communication.md` defines meeting rows for cross-lane questions, decisions, handoffs, and dependency notes. | PASS |
| Avoid concurrent writes to shared files | `docs/worker-communication.md` defines lock rows for `TEAM_PLAN.md`, `meeting_sheet.md`, queue files, and version boards. `templates/TEAM_PLAN.md` now has a `Communication and write-lock table`. Rules forbid editing a shared file/scope when another unexpired lock owns it. | PASS |
| Workers do not overwrite each other's journals | `docs/worker-communication.md` says each lane owns only `journals/<lane>.md`, append-only; other lanes read and respond through the meeting sheet or manager-owned plan updates. | PASS |
| GM learns and reflects for system improvement | `general-manager.md` now has `Continuous monitoring and reflection`; the generated GM prompt includes `journal lessons`; `worker-communication.md` and `TEAM_PLAN.md` define `journals/gm.md` as the GM reflection journal for reusable management lessons, staffing decisions, and process improvements that can benefit other projects. | PASS |
| Markdown communication stays context-light | `docs/worker-communication.md` now defines context-size limits: `TEAM_PLAN.md` under 200 lines, `meeting_sheet.md` under 120 lines, and each `journals/<lane>.md` under 120 active lines, with archive paths for old rows. Templates repeat these limits. | PASS |
| Source writes remain lease-protected | `docs/worker-communication.md` keeps source files under the existing one writable branch/worktree/path lease from `TEAM_PLAN.md`; shared communication locks do not replace source leases. | PASS |
| Managers merge shared context safely | `validator-planner.md` now reads `worker-communication.md`, `meeting_sheet.md`, and journals; it must claim a short lock before shared section edits and merge validated worker facts into `TEAM_PLAN.md`. | PASS |
| Workers read shared context before acting | `dynamic-worker.md` now requires `worker-communication.md`, `meeting_sheet.md`, journals, and the plan before work; it instructs workers to read the meeting sheet/journal during preflight. | PASS |
| Tests cover the protocol | `tests/test_ai_factory_docs.sh` checks `docs/worker-communication.md`, `meeting_sheet.md`, `journals/<lane>.md`, lock-before-write language, `templates/MEETING_SHEET.md`, `templates/JOURNAL_ENTRY.md`, and the TEAM_PLAN communication/write-lock table. | PASS |
| Current systems pick up features | Deployed the updated supervisor/docs/templates/tests to laptop and LUNARC shared supervisor tree; restarted local and laptop dashboards; restarted `babbloo-laptop-meta`, `ng-meta-lunarc-station-1`, and `nnbar-meta-lunarc-station-1`. | PASS |

## Restart evidence

- `babbloo-laptop-meta`: restarted on laptop with generated fixed panes. Status
  shows 3 panes: `GM`, `DEBUG`, `VALIDATOR`; final check showed GM and
  VALIDATOR working.
- `ng-meta-lunarc-station-1`: restarted on LUNARC job `3062045`, node `cn069`,
  3 panes running; final verification showed panes `GM`, `DEBUG`, and
  `VALIDATOR`/active node title.
- `nnbar-meta-lunarc-station-1`: restarted on LUNARC job `3061935`, node
  `cn002`, 3 panes running.
- Existing large worker stations were not mass-killed; their prompt docs are
  deployed, and the restarted GM/manager layer can recycle/redeploy workers via
  `csup staff` / `csup steward` without destroying in-flight worker context.

## Verification evidence

- `python3 -m py_compile csup-dashboard` passed.
- `bash -n codex-supervisor.sh bin/csup` passed.
- Full shell suite: all 71 `tests/test_*.sh` scripts passed.
- Context-budget and GM-reflection remote verification passed on laptop and
  LUNARC after deploying the final docs/template/prompt changes.
- Laptop targeted verification passed: `test_ai_factory_docs.sh` and
  `test_csup_staff.sh`.
- LUNARC targeted verification passed: `test_ai_factory_docs.sh` and
  `test_csup_staff.sh`.
- code-review-graph was incrementally rebuilt and `detect_changes` reported
  risk score `0.40`; shell-function inferred test gaps remain, but explicit
  tests cover the new communication docs/templates and existing changed code.

## Caveats

- The protocol is enforced through prompts/docs/templates and manager/GM gates;
  it does not implement an OS-level file lock around every markdown edit.
- Existing worker panes already running before the restart may finish their
  current prompt before reading the new communication docs. The management
  layers were restarted so they can steer/recycle/redeploy workers onto the new
  protocol.
- LUNARC still emits the known `flatpak`/`libmount` warning on some status paths.
  One `stop` also printed a `$HOME` disk quota warning while writing local stop
  markers, but the tmux session stopped and restarted successfully through the
  shared project/supervisor paths.
- Stopping Babbloo meta created the normal disabled marker; it was removed before
  the final restart, and the session is running again.

## Conclusion

Worker communication is now explicit and conflict-aware: TEAM_PLAN remains the
manager-owned source of truth, meeting_sheet records cross-lane interactions,
per-lane journals capture worker context, and shared coordination writes require
short lock rows to avoid simultaneous edits. The communication files also have
line budgets and archive rules so fresh panes do not waste context on long
markdown history. GM now has an explicit reflection journal loop so useful
management lessons can improve future projects. Current project management
layers were restarted so the running projects can pick up and enforce the new
protocol.
