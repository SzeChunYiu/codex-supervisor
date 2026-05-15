# Company-style pane operating model

`codex-supervisor` should run projects like a small company, not like a pile of
parallel shells. Each project gets a real GM Codex session, and each pane
needs a role, decision rights, outputs, and a manager that accepts its work.

## Patterns adopted from real companies

- **Amazon two-pizza / single-threaded focus:** keep teams small and give each
  batch one focused owner. For supervisor runs, one batch has one accountable
  VALIDATOR and no more panes than the work and resources justify.
- **GitLab / Apple DRI practice:** every acceptance item has one directly
  responsible lane. Other panes may help, but one row in `TEAM_PLAN.md` owns the
  decision and evidence.
- **Google Project Oxygen management habits:** manager panes coach, unblock,
  communicate, and hold quality bars. They do not micromanage implementation or
  become another generic worker.
- **Toyota / Japanese kaizen, kanban, and andon:** make work visible, limit
  work-in-progress, stop the line on shared blockers, and continuously improve
  the process after every batch. For AI panes, a blocked or finished worker is
  an andon signal, not a reason to pretend the org is busy.
- **Spotify-inspired squads / chapters / guilds:** use the useful part only:
  delivery lanes own outcomes, specialist lanes own standards, and optional
  guild-style docs share practices across projects. Do not copy titles without
  explicit responsibilities.

References:

- <https://aws.amazon.com/executive-insights/content/amazon-two-pizza-team/>
- <https://handbook.gitlab.com/handbook/people-group/directly-responsible-individuals/>
- <https://rework.withgoogle.com/en/guides/understanding-team-effectiveness>
- <https://global.toyota/en/company/vision-and-philosophy/production-system/>
- <https://docs.adaptdev.info/lib/AGXT8SZ5>

## Role tiers

| Tier | Pane / actor | Fixed? | Main job | May edit product code? |
| --- | --- | --- | --- | --- |
| Executive sponsor | Human / operator | Outside pane | Define ultimate strategic objective, budget, risk tolerance, and final approval. | Yes, but normally delegates. |
| Project GM | `GM` | Fixed | Act like the project executive: set direction, own priorities, staff teams, resolve escalations, and hold managers accountable. | No, except strategy docs/queues. |
| Team manager | `VALIDATOR` or named lead | Fixed or specified | Own a team, leases, worker next steps, acceptance, blockers, and reports to GM. | No, except coordination docs/queues. |
| Quality / principal engineer | `DEBUG` | Fixed | Review risky slices, simplify, test, and de-risk acceptance. | Yes, only in a small leased slice. |
| Functional lead | `TECH_LEAD`, `RESEARCH_LEAD`, `OPS_LEAD`, `DATA_LEAD`, `RELEASE_LEAD`, `SECURITY_REVIEWER`, etc. | Specified when needed | Own a discipline standard or complex workstream. | Only in its chartered scope. |
| Individual contributor pool | `WORKER-N` dynamic workers | Dynamic count | Pull one generic task from blockers/open queues and produce evidence. | Yes, only for the leased task. |
| Specialist contractor | Remote / LUNARC executor, read-only verifier | Dynamic or specified | Run tests, backfills, searches, audits, or platform-specific checks. | Usually no; source is read-only unless leased. |

## Role charter contract

Every active pane must be traceable to a role charter in either
`TEAM_PLAN.md`, `docs/parallel-sessions/<lane>.md`, or
`templates/ROLE_CHARTER.md` copied into the project.

Minimum fields:

1. **Role type:** `fixed-executive`, `fixed-management`, `fixed-quality`, `specified-lead`,
   `dynamic-worker`, or `specialist-contractor`.
2. **Decision rights:** what this pane may decide without asking.
3. **Writable lease:** host, source tree, branch/worktree, and paths.
4. **Inputs:** queue file, checklist row, artifacts, logs, or external data.
5. **Outputs:** commit, PR, report, audit result, blocker note, or queue item.
6. **Manager / escalation:** managers report to `GM`; workers report to
   `VALIDATOR` or a named manager. For technical standards it may be a named
   lead plus `VALIDATOR`.
7. **Version path:** worker branch, batch branch, and whether this role may open
   a PR. Default is no worker PR; VALIDATOR/RELEASE_LEAD owns the batch PR.
8. **Stop rule:** one bounded iteration, blocked with evidence, or accepted.

## Management rhythm

1. **Plan like a company:** `GM` writes or approves the project objective,
   team roster, priority order, and resource trade-offs; `VALIDATOR` turns that
   into RACI/DRI rows, leases, queues, and acceptance checks before scaling
   workers.
2. **Staff the smallest org:** start fixed management/quality first, then add
   only the functional leads or dynamic workers justified by queue depth.
3. **Run work through queues:** blockers stop the line; open tasks are normal
   work; lane queues are for specialized roles only.
4. **Staff by evidence:** GM uses `docs/gm-staffing.md` and `csup staff` to add, reduce, hold, or move workers from queue demand and node resources.
5. **Accept by evidence:** each DRI maps outputs to checklist evidence. Passing
   tests or a `DONE` pane is not accepted unless the checklist row is covered.
6. **Publish through the batch train:** accepted worker branches feed
   `batch/<date>-<slug>` and one review-facing PR unless `VERSION_BOARD.md`
   records a hotfix, risk-isolation, independent-release, or review-size split.
7. **Re-org cheaply:** if work changes, update charters and queues before
   restarting panes. Do not let stale roles keep running just to stay busy.
8. **Recycle capacity:** run `csup steward <project>` during live monitoring.
   Stop, relaunch, or reassign `DONE`, `DEAD`, `BLOCKED`, and stale panes to the
   highest acceptance gap in the need ledger.

## Dynamic role reassignment

Roles are temporary contracts. When a worker finishes one bounded iteration,
the validator should decide whether the next best use is:

1. **Same lane, new need:** relaunch with a fresh `/goal` only if that lane owns
   the highest unchecked acceptance gap.
2. **Different role:** reassign the pane to blocker removal, validation,
   release evidence, or another DRI row when that is now more urgent.
3. **Stop/shrink:** release the pane when the batch has no safe queued work or
   the next need requires human approval, data, or another host.

The reassignment decision must be traceable in `TEAM_PLAN.md`: old role, new
role, reason, queue file, acceptance row, and evidence path. This is the AI
factory version of kanban WIP control plus andon escalation.

## Suggested staffing by batch shape

| Batch shape | Recommended panes |
| --- | --- |
| Small bugfix | `GM`, `VALIDATOR`, `DEBUG`, 1-2 dynamic workers |
| Feature implementation | `GM`, `VALIDATOR`, `DEBUG`, optional `TECH_LEAD`, 1-4 dynamic workers |
| Research / evidence program | `GM`, `VALIDATOR`, `RESEARCH_LEAD`, `DATA_LEAD` or remote executor, 1-4 dynamic workers |
| Release / live ops | `GM`, `VALIDATOR`, `OPS_LEAD`, `RELEASE_LEAD`, `DEBUG`, 1-3 dynamic workers |
| Large multi-host run | One `GM` per project, one manager per team, named functional leads, dynamic workers sized by queues; split across hosts only after resource checks |

## Anti-patterns

- Treating the GM as a dashboard-only label instead of a real Codex session.
- Opening many generic workers without a manager-owned acceptance checklist.
- Giving every pane the same vague role, then hoping conflicts self-resolve.
- Letting `VALIDATOR` implement product code instead of accepting/rejecting work.
- Copying "squads/tribes/guilds" vocabulary without DRI rows, leases, and
  evidence gates.
- Treating dynamic workers as permanent owners; they are capacity, not
  accountability.
