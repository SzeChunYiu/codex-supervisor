# Manager-first TUI pane audit — 2026-05-15

## Objective restatement

In each project/team TUI pane view, the manager pane must be visible first for
that team, followed by the worker panes. The pane cards must explicitly show
whether each pane is a manager, worker, CEO, or planner so operators do not have
to infer roles from lane names.

## Prompt-to-artifact checklist

| Requirement | Evidence inspected | Status |
| --- | --- | --- |
| Manager pane appears first in each team/TUI pane group | `csup-dashboard` now builds `orderedPanes = sortTeamPaneItems(...)` for each instance grid and renders that instead of raw tmux order. `teamPaneRoleRank()` ranks `manager` before `planner`, `ceo`, and `worker`. | PASS |
| Workers follow the manager panes | `sortTeamPaneItems()` puts `worker` last and preserves pane index/original order inside the role group. The TUI grid has class/title `team-tui-pane-order` / `Manager panes are shown first, then planner/CEO, then workers.` | PASS |
| Each pane explicitly says manager vs worker | Pane headers now include `pane-role-badge role-<role>` with visible text from `companyRoleLabel(role)`: `Manager`, `Worker`, `CEO`, or `Planner`. | PASS |
| Role tags explain responsibilities | Badge titles include `Manager pane: accepts work and routes workers`, `Worker pane: executes one bounded task`, `CEO pane: real Codex executive session`, and `Planner pane: maintains plan and queue`. | PASS |
| Office/team view stays consistent with TUI order | `officeTeamFloor()` also renders `sortTeamPaneItems(team.people)`, so the pixel office team order and the raw TUI pane card order follow the same manager-first role sort. | PASS |
| Smooth-rendering contract is not broken | Removed lane from `selectedProjectStructure` after `test_dashboard_smooth_rendering.sh` caught it as volatile; reran the full shell suite successfully. | PASS |
| Tests cover the UI contract | `tests/test_dashboard_company_office.sh` now checks for `team-tui-pane-order`, `teamPaneRoleRank`, `sortTeamPaneItems`, `pane-role-badge`, `role-manager`, `role-worker`, and manager/worker responsibility titles. | PASS |
| Running dashboard serves the new assets | Restarted local `csup-dashboard`; `curl http://127.0.0.1:7777` contains `pane-role-badge`, `team-tui-pane-order`, and the manager/worker title strings. | PASS |
| Remote dashboards can pick it up | Deployed `csup-dashboard` and dashboard test to laptop and LUNARC shared supervisor tree; laptop and LUNARC `python3 -m py_compile csup-dashboard && bash tests/test_dashboard_company_office.sh` passed. Laptop `csup-dashboard` was restarted. | PASS |

## Verification evidence

- `python3 -m py_compile csup-dashboard` passed.
- `bash -n codex-supervisor.sh bin/csup` passed.
- Full shell suite: all 71 `tests/test_*.sh` scripts passed.
- Local served dashboard HTML contains:
  - `.pane-role-badge`
  - `team-tui-pane-order`
  - `Manager pane: accepts work and routes workers`
  - `Worker pane: executes one bounded task`
- code-review-graph was incrementally rebuilt and `detect_changes` reported
  risk score `0.40`.

## Caveats

- The Browser/Playwright MCP instance was locked by an existing Chrome profile
  during this pass, so browser automation could not attach. I verified via the
  served dashboard HTML and the dashboard shell tests instead.
- If lane names change without a structural pane change, the existing smooth
  dashboard update path updates role badges in place but does not reshuffle the
  already-mounted grid until the next structural rerender. This preserves the
  smooth-rendering contract that prevents volatile lane tails from forcing full
  DOM rebuilds.

## Conclusion

The dashboard TUI pane view now orders each team/instance with manager panes
first and workers after them, and every pane header explicitly labels the role
as Manager, Worker, CEO, or Planner.
