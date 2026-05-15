# CEO steering execution evidence — 2026-05-14

## Objective

Act as CEO across currently running projects, right-size teams/panes, start manager capacity where useful, and seed initial plans so project managers/validators can auto-steer toward the most urgent goals.

## Observed project states

From `csup steward ... --sample-secs=5` and dashboard state:

- `neural_grow`: originally 21 panes with many completed; later visible dashboard surface showed only active art panes due LUNARC direct SSH degradation. CEO decision: add META, recycle DONE panes through validator rather than expanding feature capacity.
- `babbloo`: 7 laptop workers active. CEO decision: add META, keep laptop workers, defer Mac workers until resource/prompt issues are fixed.
- `nnbar`: 32 panes observed initially, with blocked and done panes. CEO decision: do not add capacity; use existing META to resolve blockers and recycle completed panes.

## Actions taken

- Started neural_grow META station:
  - `csup station neural_grow --host=ng-meta-lunarc --sessions=1 --workers=0 --apply`
  - Result: `START ... session=ng-meta-lunarc-station-1 workers=0 panes=2` on job `3062045` node `cn069`.
- Started babbloo META station:
  - `csup station babbloo --host=lunarc-meta --sessions=1 --workers=0 --apply`
  - Result: `START ... session=babbloo-lunarc-meta-station-1 workers=0 panes=2` on job `3063426` node `cx04`.
- Left nnbar without new panes because steward showed existing over-capacity and blocker-first need.
- Created central portfolio plan: `docs/ceo-steering/2026-05-14-current-projects.md`.
- Created local project steering plans and meta queue tasks for neural_grow, babbloo, and nnbar.
- Mirrored Babbloo steering plan/queue to the laptop project copy.
- Fixed Babbloo stale `worker-f` queue issue locally by rerouting active worker-f goals into valid `bugs` and `test` queues.
- Created `codex-prompts-mac-ceo.txt` and pointed Babbloo Mac config to it so future local starts are right-sized and prompt-valid.

## Verification / guardrails

- `CODEX_SUPERVISOR_PROMPTS=codex-prompts-mac-ceo.txt /Users/billy/codex-supervisor.sh validate-prompts` passed.
- `csup govern --project=babbloo --host=mac-mini --dry-run` no longer fails on prompt mismatch; it now safely skips because local Mac capacity is reserved/insufficient.
- `csup steward` still identifies stale/done/blocked panes and recommends reassign/requeue actions.

## Current blocker

Direct LUNARC SSH degraded after the station starts. The persistent socket was stale/refusing sessions; after clearing it, `/Users/billy/lunarc-init.sh` failed at OTP authentication. Because of that, project-local steering docs could not be copied into the active LUNARC project directories after the starts, and direct remote status could not be re-verified. Dashboard/csup start output remains the evidence that the station starts were submitted/started.

## Next operator action when LUNARC auth works

1. Copy each local `docs/CEO_STEERING_PLAN_2026-05-14.md` and `codex-tasks/meta/ceo-steering.txt` into the active LUNARC project directories.
2. Confirm `ng-meta-lunarc-station-1` and `babbloo-lunarc-meta-station-1` are visible/healthy.
3. Ask each VALIDATOR to consume `ceo-steering.txt`, update acceptance-gap queues, and produce shrink/recycle recommendations.

## Continuation update — Babbloo accessible fallback

Because LUNARC OTP remained unavailable, Babbloo was given an accessible laptop META team as a fallback manager layer:

- Created `codex-prompts-laptop-meta.txt` with two manager lanes: `DEBUGGER` and `VALIDATOR`.
- Added `[hosts."laptop-meta"]` to the Babbloo supervisor config and to the local csup host inventory.
- Started `babbloo-laptop-meta` on the laptop with 2 panes.
- Verified with `csup status babbloo` that:
  - `babbloo-laptop` has 7 worker panes running.
  - `babbloo-laptop-meta` has 2 manager panes running (`DEBUGGER`, `VALIDATOR`).
- Captured pane tails showing the manager panes inspecting worker evidence, queue mismatch, and acceptance/steering docs.

The Babbloo part of the objective is therefore live and manager-steered despite LUNARC auth being down.

## Continuation update — LUNARC restored and remote plans deployed

LUNARC authentication recovered after a fresh OTP window:

- Socket created at `/Users/billy/.ssh/sockets/scyiu@cosmos.lunarc.lu.se-22` with 7-day TTL.
- Codex credentials synced.

Remote steering plan deployment was completed:

- Copied neural_grow CEO plan and `codex-tasks/meta/ceo-steering.txt` to `/projects/hep/fs10/shared/nnbar/billy/neural_grow/` and verified line counts (`22 + 1`).
- Copied nnbar CEO plan and `codex-tasks/meta/ceo-steering.txt` to `/projects/hep/fs10/shared/nnbar/billy/NNBAR_Detector_sim/` and verified line counts (`22 + 1`).
- Copied babbloo CEO plan and `codex-tasks/meta/ceo-steering.txt` to `/projects/hep/fs10/shared/nnbar/billy/babbloo-codex/` and verified line counts (`21 + 1`).

Manager/session verification:

- neural_grow: `ng-meta-lunarc` was started with 2 panes on job `3062045`; direct tmux check showed two live node panes.
- babbloo: `babbloo-laptop` has 7 worker panes and `babbloo-laptop-meta` has 2 manager panes (`DEBUGGER`, `VALIDATOR`) running on laptop; LUNARC Babbloo station has a holder job but no active named project sessions, so laptop META is the live manager layer.
- nnbar: existing `nnbar-meta-lunarc` has 2 manager panes (`DEBUGGER`, `VALIDATOR`) running; no extra panes were added because current worker capacity is already high and blocker-first recycling is the right CEO action.
