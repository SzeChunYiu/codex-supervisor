# General Manager launch-flow audit — 2026-05-15

## Objective restatement

The human-facing AI session is the operator: it opens/resumes a project by
choosing resources (for example a LUNARC station node or the laptop), then first
starts a General Manager Codex session. The General Manager is a real Codex pane
like the other panes. GM reads project plans, markdown, queues, reports, and
work done so far, then decides which teams to open, close, redeploy, shrink, or
expand based on available resources. GM communicates direction to team managers;
managers translate that direction into team plans, leases, queues, and worker
prompts.

## Prompt-to-artifact checklist

| Requirement | Evidence inspected | Status |
| --- | --- | --- |
| Rename CEO to General Manager / GM | Generated fixed lane is now `GM`, dashboard summary is `gm-session-summary-pane`, docs use `General Manager`, and current config docs expose `CODEX_SUPERVISOR_GM` / `CODEX_SUPERVISOR_GM_DOC`. Legacy `CEO` env/lane aliases remain only for backward compatibility. | PASS |
| GM is a real Codex pane, not a label | `codex-supervisor.sh::ensure_gm_prompt` generates a real `/goal` prompt for `PANE 0, lane GM`; dashboard `projectGmPanes()` lists actual tmux/Codex panes and warns if missing. | PASS |
| Operator starts GM first when creating/resuming a project | Added `csup gm-start <project> [--host=<host>]`: dry-run prints `GM-BOOT ... action=start_general_manager_first panes=3`; apply starts the fixed GM/DEBUG/VALIDATOR layer with zero dynamic workers. | PASS |
| Operator can book/use LUNARC or laptop resources | `gm-start` delegates SLURM hosts to `csup station --workers=0`, and uses generated-only fixed panes for local/remote non-SLURM hosts. Existing `csup staff`/`csup station` continue to size workers by queue demand and node capacity. | PASS |
| GM reads project plans, markdown, and work done so far | Generated GM prompt reads `docs/parallel-sessions/general-manager.md`; that doc requires `parallel-sessions.md`, `company-operating-model.md`, `ai-factory.md`, `gm-staffing.md`, project `TEAM_PLAN.md`, `codex-tasks/gm.txt`, and blockers. The prompt explicitly says `review plans, work so far, manager reports, resources`. | PASS |
| GM actively manages teams and staffing | `docs/parallel-sessions.md` now defines the operator -> GM -> teams flow. `docs/gm-staffing.md` gives GM authority to add, reduce, move, hold, or stop worker capacity through measured demand/resources. `csup staff` prints `STAFF-UP`/`STAFF-DOWN` and `GM-NOTE`. | PASS |
| GM communicates with managers and steers development direction | Generated GM prompt says `communicate direction and steer staffing`; `general-manager.md` says GM communicates project direction back to managers and defines GM -> manager / Manager -> GM protocol. | PASS |
| Managers still manage workers | `TEAM_PLAN.md` template has GM as fixed executive, VALIDATOR as fixed manager reporting to GM, and workers reporting to VALIDATOR/manager; manager-first TUI pane ordering and role badges remain in `csup-dashboard`. | PASS |
| Dashboard reflects GM terminology and real pane status | Served local dashboard HTML contains `gm-session-summary-pane`, `Real GM Codex session`, `GM duty: review manager reports`, `team-tui-pane-order`, and `pane-role-badge`. | PASS |
| Tests cover the launch/GM/staffing behavior | `tests/test_planner_and_resilience.sh` asserts generated `GM` prompt content; `tests/test_csup_staff.sh` asserts `gm-start` dry-run and `GM-NOTE`; `tests/test_ai_factory_docs.sh` checks GM docs; `tests/test_dashboard_company_office.sh` checks GM dashboard markers. | PASS |
| Laptop/LUNARC launchers pick up the flow | Deployed changed supervisor/dashboard/docs/tests to laptop and LUNARC shared supervisor tree. Remote verification on both hosts generated `GM`, `DEBUG`, `VALIDATOR` and the corrected GM prompt. Targeted remote tests passed. | PASS |

## Verification evidence

- Generated prompt proof (`/tmp/gm-generated-proof.txt`): `GM`, `DEBUG`,
  `VALIDATOR`; first prompt is `/goal You are PANE 0, lane GM... review plans,
  work so far, manager reports, resources; then communicate direction and steer
  staffing.`
- Real dry-run: `./bin/csup gm-start neural_grow --host=ng-meta-lunarc --dry-run`
  printed `GM-BOOT ... action=start_general_manager_first panes=3` followed by
  `GM-NEXT ... run csup staff to open/reduce/redeploy teams`.
- Syntax/build: `bash -n codex-supervisor.sh bin/csup` and
  `python3 -m py_compile csup-dashboard` passed.
- Full shell suite: all 71 `tests/test_*.sh` scripts passed.
- Dashboard served HTML contains GM and role-badge markers.
- Remote laptop and LUNARC targeted tests passed after deployment.
- code-review-graph incremental rebuild succeeded; `detect_changes` reported
  risk score `0.40`. It still flags shell-function test gaps, but the explicit
  shell tests cover the changed GM prompt, `gm-start`, docs, and dashboard
  markers.

## Compatibility notes

- Legacy `CODEX_SUPERVISOR_CEO`, `CODEX_SUPERVISOR_CEO_DOC`, `ceo-start`, and
  `ceo-staff` still work as aliases so older project configs do not break.
- Existing already-running panes keep their current prompt until restarted or
  resent; newly started/restarted projects now use GM terminology and behavior.
- Historical audit docs under `docs/ceo-steering/` remain as history, but the
  current launch/docs/tests use GM.

## Conclusion

The system now follows the requested chain: operator allocates a host/node and
runs `csup gm-start`; a real GM Codex pane starts first and reviews plans,
manager reports, work so far, queues, and resources; GM then uses/requests
`csup staff` and manager queues to open, close, reduce, redeploy, or expand
teams while communicating direction to managers.
