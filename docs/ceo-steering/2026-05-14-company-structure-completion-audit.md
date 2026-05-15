# Company structure completion audit — 2026-05-14

## Restated objective

Improve `codex-supervisor` so each project behaves like a company: the project
CEO is a real Codex session, managers own teams and report to CEO, workers
report to managers, every active team has at least one manager and one worker,
and the operating model defines efficient communication and execution rhythms
in the style of a high-trust kaizen/Japanese-company system.

## Prompt-to-artifact checklist

| Requirement | Evidence | Status |
| --- | --- | --- |
| CEO of each project is an actual Codex session | `codex-supervisor.sh` now defines `CODEX_SUPERVISOR_CEO=1` by default, persists `CEO_ENABLED`, generates a `CEO` `/goal`, and `load_prompts` appends CEO before DEBUG/VALIDATOR. `tests/test_planner_and_resilience.sh` expects generated `CEO`. | PASS |
| Supervisor right-sizing counts the CEO pane | `bin/csup` default fixed panes are now 3 for governor and station paths (`CEO + DEBUG + VALIDATOR`), and station/factory tests expect `workers + 3` panes. | PASS |
| CEO has an executive operating charter | New `docs/parallel-sessions/ceo-executive.md` defines purpose, decision rights, team contract, operating rhythm, communication protocol, kaizen behavior, and stop rule. | PASS |
| Managers own their teams and report to CEO | `docs/parallel-sessions.md`, `docs/company-operating-model.md`, `docs/ai-factory.md`, `docs/parallel-sessions/validator-planner.md`, `templates/TEAM_PLAN.md`, and `templates/ROLE_CHARTER.md` now separate CEO direction from manager acceptance and reporting. | PASS |
| Each team has at least one manager and worker | `docs/parallel-sessions/ceo-executive.md` and `docs/parallel-sessions.md` state the minimum team contract: one manager plus one worker or worker-equivalent executor, with rows in `TEAM_PLAN.md`. | PASS |
| Worker-manager communication is explicit | `docs/parallel-sessions/ceo-executive.md` defines CEO -> manager, manager -> CEO, manager -> worker, and worker -> manager channels; dynamic worker docs tell workers to escalate to the manager. | PASS |
| Efficient/effective operation is designed | `docs/company-operating-model.md` and `docs/ai-factory.md` now combine CEO direction, manager-owned need ledgers, blocker-first queues, evidence acceptance, role recycling, and kaizen/andon behavior. | PASS |
| Templates encode the structure | `templates/TEAM_PLAN.md` includes CEO, VALIDATOR manager, DEBUG, WORKER rows plus `codex-tasks/ceo.txt`; `templates/ROLE_CHARTER.md` includes `fixed-executive` and manager/escalation reporting. | PASS |
| Regression coverage exists | `tests/test_ai_factory_docs.sh`, `tests/test_planner_and_resilience.sh`, `tests/test_prompt_contract.sh`, station/governor tests, and full shell suite cover docs and fixed-pane count changes. | PASS |

## Fresh verification evidence

- `bash -n codex-supervisor.sh bin/csup csup-dashboard` passed.
- `CODEX_SUPERVISOR_TEST_SOURCE=1 CODEX_SUPERVISOR_PROMPTS=codex-prompts.example.txt source ./codex-supervisor.sh; load_prompts` produced lanes: `BUGS`, `PERF`, `CEO`, `DEBUG`, `VALIDATOR`.
- Full shell suite passed: `all 70 shell tests passed`.
- `code-review-graph detect_changes` reported medium code risk (`0.40`) with changed prompt/runtime functions; shell tests cover the generated CEO path even though the graph cannot infer shell test coverage for those functions.

## Remaining caveats

- This audit verifies repo structure, docs, prompt generation, and launch sizing.
  It does not start live project CEO panes; project operators should use
  `csup factory-run` or project configs to roll the new default into running
  projects during the next controlled recycle.
- Existing running two-pane META sessions will remain as-is until restarted;
  the new CEO default applies to fresh launches or restarts.

## Conclusion

The company-structure design is implemented and verified at the supervisor repo
level: projects now default to a real CEO Codex session plus manager/quality
lanes, teams have explicit manager-worker contracts, and the communication/
operations model is documented and covered by regression tests.
