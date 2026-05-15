# Restart and NeuroGrow scale-up audit — 2026-05-15

## Objective

Restart supervised projects so they pick up the new CEO/DEBUG/VALIDATOR
company architecture, then scale `neural_grow` so it can work on more queued
work without over-expanding inactive projects.

## Results checklist

| Requirement | Fresh evidence | Status |
| --- | --- | --- |
| Confirm LUNARC access before remote operations | `ssh -O check lunarc ... || /Users/billy/lunarc-init.sh` reported the existing persistent socket was active after the auto-login check. | PASS |
| Keep local Mac from taking new project panes | `df -h /` showed the local root filesystem at roughly 95% full with under 1 GiB free during the rollout, so no local project panes were started. | PASS |
| Restart Babbloo management layer | `babbloo-laptop-meta` was restarted on the laptop and verified as a 3-pane management session with `DEBUGGER`, `VALIDATOR`, and `CEO`. | PASS |
| Remove stale Babbloo worker session instead of over-expanding | `csup staff babbloo --host=laptop --scenario=resume --apply --allow-stop` returned `STAFF-DOWN ... reason=no_queued_work work=0 blockers=0 prompts=8 action=stop_configured_session`; it stopped `babbloo-laptop` and left `babbloo-laptop-meta` running. | PASS |
| Restart NeuroGrow management layer | `ng-meta-lunarc-station-1` was restarted on LUNARC job `3062045` and verified with 3 panes. | PASS |
| Restart NNBAR management layer | `nnbar-meta-lunarc-station-1` was restarted on LUNARC job `3061935` and verified with 3 panes. | PASS |
| Avoid starting inactive weather-market sessions | LUNARC jobs `3063426`, `3061935`, `3061936`, and `3062045`, laptop tmux, and local tmux were checked for `weather`/`market` sessions; none were found. | PASS |
| Scale NeuroGrow on real queued work | `csup staff neural_grow --host=ng-unity-lunarc --scenario=resume` still reports `STAFF-UP ... work=54 blockers=0 ... workers=5 panes=8`; applied scale-up started five 8-pane station sessions. | PASS |

## Live session inventory after scale-up

### Laptop

- `babbloo-laptop-meta` is running.
- `babbloo-laptop` was stopped because the staff gate found no queued work.
- `csup-dashboard` remains running on the laptop.

### LUNARC NeuroGrow

Verified station sessions:

- `ng-meta-lunarc-station-1` — 3 panes on job `3062045`.
- `ng-unity-lunarc-station-1` — 8 panes on job `3061936`.
- `ng-content-lunarc-station-1` — 8 panes on job `3061936`.
- `ng-research-lunarc-station-1` — 8 panes on job `3061936`.
- `ng-polish-lunarc-station-1` — 8 panes on job `3062045`.
- `ng-qa-lunarc-station-1` — 8 panes on job `3062045`.

The scale-up added five task stations with 5 dynamic workers each, for 25 new
dynamic NeuroGrow workers plus fixed CEO/DEBUG/VALIDATOR panes per station.
Including the meta station, NeuroGrow now has 43 verified panes across the
inspected LUNARC stations.

### LUNARC NNBAR

- `nnbar-meta-lunarc-station-1` — 3 panes on job `3061935`.

### Weather-market / codex-supervisor project sessions

No active `weather`/`market` project tmux sessions were found on the inspected
local, laptop, or LUNARC tmux surfaces. The local `csup-dashboard` is running,
but no separate `codex-supervisor` project worker session was found.

## Verification commands and artifacts

- `/tmp/csup-weather-check.txt` — checked weather-market project session absence
  across known LUNARC jobs, laptop, and local tmux.
- `/tmp/csup-lunarc-sessions.txt` — recorded LUNARC NeuroGrow/NNBAR station pane
  counts and pane titles.
- `/tmp/csup-babbloo-status.txt` and `/tmp/csup-babbloo-prompt.txt` — recorded
  Babbloo status/prompt state before staff-down.
- `./bin/csup staff babbloo --host=laptop --scenario=resume --apply --allow-stop`
  — stopped stale Babbloo worker session due no queued work.
- `./bin/csup staff neural_grow --host=ng-unity-lunarc --scenario=resume` —
  fresh post-scale dry-run still shows real queued work and a right-sized
  5-worker/8-pane station shape.

## Caveats

- Some project management panes quickly report `DONE`; that is not treated as
  proof of project completion. The audit only claims session restart/pane
  architecture and live station capacity.
- LUNARC commands continue to emit the known `flatpak`/`libmount` warning in
  some `csup status` paths, but direct `srun`/tmux checks succeeded.
- The local Mac remains too low on disk for safe local pane expansion.

## Conclusion

The active management layers were refreshed, stale no-work Babbloo worker panes
were stopped, inactive weather-market/codex-supervisor project sessions were not
expanded, and `neural_grow` was scaled to five additional 8-pane task stations
for the current queued work.
