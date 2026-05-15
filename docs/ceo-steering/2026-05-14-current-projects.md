# CEO steering plan — running projects — 2026-05-14

Purpose: apply latest-model supervision as a CEO layer across the currently running projects, right-size teams, and hand control to project managers/validators so they steer from live needs instead of static roles.

## Portfolio allocation

| Project | Current observed state | CEO allocation | Immediate management goal |
|---|---:|---:|---|
| neural_grow | 21 panes observed: 6 active, 15 done | Keep active art/content work; add 2-pane META; recycle done panes only after validator artifact audit | Turn finished panes into acceptance-gap work, not idle capacity |
| babbloo | 7 laptop workers active; no active manager observed | Keep 7 workers; add 2-pane LUNARC META; defer Mac workers until stale worker-f queue/prompt mismatch is fixed | Put DEBUGGER/VALIDATOR above the laptop workers and steer from TEAM_PLAN |
| nnbar | 32 panes observed: 18 active, 7 waiting, 5 done, 2 blocked | Do not add panes; use existing META to requeue blockers and shrink/recycle completed panes | Resolve blocked lanes before expanding and stop completed DEBUG/worker capacity |

## Company operating rules for all managers

1. Run `csup steward <project> --sample-secs=5` before adding capacity.
2. Treat `DONE`, `DEAD`, `BLOCKED`, and stale/waiting panes as andon signals.
3. Reassign roles dynamically: old lane ownership ends when a pane finishes its bounded iteration.
4. Managers must update or create project-level steering docs with old role, new role, reason, queue file, acceptance row, and evidence path.
5. Workers may spontaneously identify needs only from `TEAM_PLAN.md`, acceptance checklists, blockers, failing tests, or missing evidence; no side quests.
6. Prefer blocker-first and validator-first work over more feature panes.
7. Use kaizen/kanban discipline: visible WIP, small batches, documented handoffs, continuous improvement.

## Actions taken by CEO session

- Started `neural_grow` META station: `ng-meta-lunarc-station-1` with 2 panes.
- Started `babbloo` META station: `babbloo-lunarc-meta-station-1` with 2 panes.
- Left `nnbar` capacity unchanged because it already has many active panes plus blocked lanes.
- Attempted local Babbloo Mac governance; it correctly failed because queued lane `worker-f` has no matching prompt in `codex-prompts.txt`. This is a manager cleanup item, not a reason to add more panes.

## Manager kickoff

Each project now has/should receive a project-local `docs/CEO_STEERING_PLAN_2026-05-14.md` and `codex-tasks/meta/ceo-steering.txt`. Managers should read these first, then steer from actual acceptance gaps.

## Update — accessible Babbloo manager layer

LUNARC authentication degraded after the initial station starts, so Babbloo received an accessible fallback manager team on the laptop:

- Session: `babbloo-laptop-meta`
- Panes: 2 (`DEBUGGER`, `VALIDATOR`)
- Workers being managed: existing `babbloo-laptop` 7-pane worker session
- Evidence: `csup status babbloo` reports both laptop worker and laptop meta sessions running.

This keeps Babbloo auto-steering even while LUNARC is unavailable.
