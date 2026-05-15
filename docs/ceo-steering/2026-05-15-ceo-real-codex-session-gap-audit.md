# CEO real Codex session gap audit — 2026-05-15

## Objective restatement

The CEO must not be a virtual dashboard label. For each supervised project, CEO
must be a real Codex/tmux pane that actively reviews the latest manager reports,
communicates project direction to managers, and queues executive decisions that
guide the project.

## Prompt-to-artifact checklist

| Requirement | Evidence inspected | Status |
| --- | --- | --- |
| CEO is generated as a real Codex session/pane | `CODEX_SUPERVISOR_GENERATED_ONLY=1` proof generated `lane=CEO`, `lane=DEBUG`, `lane=VALIDATOR`; the first prompt is a `/goal` for `PANE 0, lane CEO`. | PASS |
| CEO prompt actively reviews manager reports | `codex-supervisor.sh::ensure_ceo_prompt` now emits `review manager reports`. `tests/test_planner_and_resilience.sh` asserts this exact behavior. | PASS |
| CEO communicates project direction to managers | Generated CEO prompt now emits `communicate direction`; `docs/parallel-sessions/ceo-executive.md` says CEO communicates project direction back to managers; tests assert both. | PASS |
| Dashboard must not fabricate a virtual CEO | Removed fallback insertion of synthetic `people.ceo`. Removed `renderVirtualCeoPane`; replaced it with `renderCeoSessionSummaryPane`, which lists real CEO panes or shows `CEO Codex session missing`. Grep found zero remaining `ceo-virtual-pane`, `Virtual CEO pane`, `Virtual CEO layer`, or `This is not a tmux worker pane` markers. | PASS |
| Dashboard surfaces CEO as real session evidence | `renderCeoSessionSummaryPane` uses `projectCeoPanes(project)` to list real host/session/pane/lane/state. If none exists, it tells the operator to restart with generated fixed roles. | PASS |
| Docs encode the corrected role contract | `docs/parallel-sessions/ceo-executive.md` now says the CEO lane is a real Codex session that actively reviews manager reports and communicates direction. The dashboard audit doc was corrected from virtual CEO language to real/missing CEO behavior. | PASS |
| Tests cover the gap | `tests/test_planner_and_resilience.sh`, `tests/test_dashboard_company_office.sh`, and `tests/test_ai_factory_docs.sh` were updated to fail if the CEO prompt/docs/dashboard regress to passive or virtual behavior. | PASS |
| Remote launchers pick up the fix | Targeted rsync deployed the changed supervisor/dashboard/docs/tests to the laptop and LUNARC shared supervisor tree. Remote generated-only verification on both hosts produced `CEO`, `DEBUG`, `VALIDATOR` and a CEO prompt with `review manager reports, communicate direction`. | PASS |
| Running dashboards pick up the fix | Restarted local and laptop `csup-dashboard` tmux sessions after deploying the dashboard change. | PASS |

## Verification evidence

- Syntax: `bash -n codex-supervisor.sh bin/csup csup-dashboard` passed.
- Targeted tests: `test_planner_and_resilience.sh`,
  `test_dashboard_company_office.sh`, and `test_ai_factory_docs.sh` passed.
- Full shell suite: all 71 `tests/test_*.sh` scripts passed.
- Generated CEO proof saved in `/tmp/ceo-generated-proof.txt`:
  `CEO`, `DEBUG`, `VALIDATOR`, with CEO prompt `review manager reports,
  communicate direction, and queue executive decisions`.
- Laptop proof: remote generated-only load produced `CEO`, `DEBUG`,
  `VALIDATOR`, with the corrected CEO prompt under
  `/home/billy/Desktop/projects/codex-supervisor`.
- LUNARC proof: shared supervisor generated-only load produced `CEO`, `DEBUG`,
  `VALIDATOR`, with the corrected CEO prompt under
  `/projects/hep/fs10/shared/codex-tooling/supervisor`.
- code-review-graph was incrementally rebuilt and `detect_changes` reported low
  risk score `0.40`; noted shell-function test-gap inference remains, but the
  explicit shell suite covers the CEO prompt/dashboard/doc contract.

## Remaining caveats

- Existing already-running CEO panes keep their current in-pane prompt until
  restarted or resent. New/restarted sessions now receive the corrected CEO
  prompt.
- Dashboard summary is not a second CEO pane; it is a status card that points to
  real CEO panes or warns that a CEO pane is missing.
- LUNARC verification still prints the known `flatpak`/`libmount` warning, but
  generated prompt verification succeeded.

## Conclusion

The gap is closed in code, dashboard behavior, docs, tests, local deployment,
laptop deployment, and LUNARC shared deployment: CEO is treated as a real Codex
session, not a virtual label, and its generated duty is to review manager
reports, communicate direction, and queue executive decisions.
