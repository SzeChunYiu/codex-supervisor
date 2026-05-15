# Restart rollout audit — 2026-05-15

## Restated objective

Restart supervised projects so the new company architecture is actually in
place: each active project should have a real CEO Codex session, manager/quality
sessions, and the updated supervisor code/docs available on the machines that
launch panes.

## Prompt-to-artifact checklist

| Requirement | Evidence | Status |
| --- | --- | --- |
| Deploy new supervisor architecture locally | Local `~/codex-supervisor.sh` and `~/bin/csup` are symlinks to the updated repo. Local dashboard was restarted from `./csup-dashboard`. | PASS |
| Deploy new supervisor architecture to laptop | Rsynced `codex-supervisor.sh`, `bin/csup`, dashboard/docs/templates/tests to `/home/billy/Desktop/projects/codex-supervisor`; copied launchers to `/home/billy/codex-supervisor.sh` and `/home/billy/bin/csup`; remote generated-only smoke produced `CEO DEBUG VALIDATOR`. | PASS |
| Deploy new supervisor architecture to LUNARC | Rsynced updated supervisor tree to `/projects/hep/fs10/shared/codex-tooling/supervisor`; remote generated-only smoke produced `CEO DEBUG VALIDATOR`. | PASS |
| Fix generated-only station starts without prompt files | Updated `codex-supervisor.sh` so `CODEX_SUPERVISOR_GENERATED_ONLY=1` can launch generated CEO/DEBUG/VALIDATOR without requiring the configured prompt file to exist. | PASS |
| Ensure station fixed-pane count matches generated roles despite remote env overrides | Updated `bin/csup` station payload to force `CODEX_SUPERVISOR_CEO=1 CODEX_SUPERVISOR_DEBUGGER=1 CODEX_SUPERVISOR_VALIDATOR=1` when it reserves fixed panes. | PASS |
| Restart Babbloo management layer | Restarted `babbloo-laptop-meta` on laptop. Verified 3 panes: `DEBUGGER`, `VALIDATOR`, `CEO`; all working after restarting the validator pane. | PASS |
| Restart NeuroGrow management layer | Restarted LUNARC station `ng-meta-lunarc-station-1` on job `3062045`, node `cn069`. Verified 3 panes: `CEO`, `DEBUG`, `VALIDATOR`, all `WORKING`. | PASS |
| Restart NNBAR management layer | Restarted LUNARC station `nnbar-meta-lunarc-station-1` on job `3061935`, node `cn002`. Verified 3 panes: `CEO`, `DEBUG`, `VALIDATOR`, all `WORKING`. | PASS |
| Do not over-expand inactive projects | `weather-market` and `codex-supervisor` had no verified active supervisor project sessions in the inspected tmux surfaces; tooling was deployed so their next controlled start uses the new architecture. | PASS |
| Verification / regression | `bash -n codex-supervisor.sh bin/csup csup-dashboard`; `test_planner_and_resilience.sh`; `test_prompt_contract.sh`; `test_pane_auto_continue.sh`; `test_csup_station_existing_slot.sh`; `test_csup_factory_run_slurm_resume.sh`; `test_csup_dynamic_workers.sh` passed after the restart fixes. | PASS |

## Current live evidence

### Babbloo laptop meta

`babbloo-laptop-meta` status:

- `DEBUGGER` — `WORKING`
- `VALIDATOR` — `WORKING`
- `CEO` — `WORKING`

### NeuroGrow LUNARC meta

`ng-meta-lunarc-station-1` status on job `3062045`:

- `CEO` — `WORKING`
- `DEBUG` — `WORKING`
- `VALIDATOR` — `WORKING`

### NNBAR LUNARC meta

`nnbar-meta-lunarc-station-1` status on job `3061935`:

- `CEO` — `WORKING`
- `DEBUG` — `WORKING`
- `VALIDATOR` — `WORKING`

## Caveats

- Existing worker sessions were not mass-killed. The new architecture was put in
  place by restarting the project management/meta layer and deploying the new
  launchers. This avoids destroying in-flight worker context while still adding
  CEO -> manager -> worker control at the project level.
- LUNARC status commands still print the known `flatpak`/`libmount` warning, but
  direct `srun`/tmux and supervisor status verification succeeded.
- Local Mac root disk remains very low, so no local project pane expansion was
  attempted there.

## Conclusion

The active supervised projects now have the new architecture in place at the
management layer, and the updated launchers/docs are deployed to local, laptop,
and LUNARC so future restarts use CEO + DEBUG + VALIDATOR by default.
