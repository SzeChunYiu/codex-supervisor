# CEO staffing hardening audit — 2026-05-15

## Restated objective

Harden the company staff roles so the CEO can add, reduce, hold, or move worker
capacity according to project needs and node resources, while preserving the
manager-owned team/acceptance chain.

## Prompt-to-artifact checklist

| Requirement | Evidence | Status |
| --- | --- | --- |
| CEO has explicit staffing authority | `docs/parallel-sessions/ceo-executive.md` now includes a Staffing authority section requiring measured demand, supply, node headroom, manager readiness, decision, and evidence. | PASS |
| CEO can add workers from project needs/resources | New `csup staff <project>` prints `STAFF-UP` when queued work exists and delegates to `factory-run`, which sizes sessions/workers by queue depth and station/governor capacity. | PASS |
| CEO can reduce workers safely | `csup staff` prints `STAFF-DOWN` when no queued work exists; default is recommendation only. `--apply --allow-stop` is required before it calls `csup stop`, so reduction is explicit and manager-gated. | PASS |
| Resource/node constraints are part of the decision | `docs/ceo-staffing.md` requires measured CPU/RAM/disk/load/headroom; `csup staff` delegates scale-up to existing `factory-run`/`station`/`govern` paths that enforce capacity and SLURM login-node safety. | PASS |
| Managers still own workers | `docs/ceo-staffing.md`, `docs/company-operating-model.md`, `docs/ai-factory.md`, and `TEAM_PLAN.md` keep CEO at direction/staffing level and managers as lease/acceptance/worker-communication owners. | PASS |
| Staffing decisions are recorded | `templates/TEAM_PLAN.md` now includes a CEO-owned Staffing ledger with demand, resource signal, manager readiness, command/evidence, and status columns. | PASS |
| Command is documented | New `docs/ceo-staffing.md`; README and AI factory docs reference `csup staff`; command appears in `bin/csup` usage. | PASS |
| Regression coverage exists | New `tests/test_csup_staff.sh` covers `STAFF-DOWN` no-work shrink recommendations and `STAFF-UP` delegation to factory-run with `workers + CEO/DEBUG/VALIDATOR` pane sizing. `tests/test_ai_factory_docs.sh` covers docs/template links. | PASS |

## Fresh verification evidence

- Syntax: `bash -n bin/csup codex-supervisor.sh csup-dashboard` passed.
- Targeted tests passed:
  - `tests/test_csup_staff.sh`
  - `tests/test_ai_factory_docs.sh`
  - `tests/test_csup_factory_run_slurm_resume.sh`
  - `tests/test_csup_station_existing_slot.sh`
  - `tests/test_csup_dynamic_workers.sh`
  - `tests/test_csup_governor.sh`
  - `tests/test_prompt_contract.sh`
  - `tests/test_planner_and_resilience.sh`
  - `tests/test_pane_auto_continue.sh`
- Full suite passed: `all 71 shell tests passed`.
- Real dry-run smoke: `csup staff neural_grow --host=ng-meta-lunarc --dry-run` produced `STAFF-UP ... work=8 blockers=7 ... action=factory-run`, then station dry-run sized `workers=5 panes=8` and skipped the already-running station session instead of duplicating it.
- Code-review graph refreshed and `detect_changes` ran; it reports medium risk (`0.40`) around shell functions that are covered by shell regression tests but not understood by graph test-gap inference.

## Remaining caveats

- `csup staff --apply --allow-stop` can stop a configured session. It is intentionally explicit and should only be used after manager/validator audit confirms no unchecked acceptance row depends on that session.
- Existing live CEO/manager sessions do not automatically invoke `csup staff`; this hardens their authority and provides the command/policy for their next staffing cycles.
- Deployment smoke: updated `csup staff` command deployed to laptop and LUNARC shared supervisor; `csup help` on both hosts includes `csup staff` (`laptop-staff-ok`, `lunarc-staff-ok`).

## Conclusion

The staff-role model is hardened: CEO has a measured staffing policy, a concrete
`csup staff` gate to add/reduce workers from demand and resources, and a
TEAM_PLAN staffing ledger that keeps manager ownership and evidence gates intact.
