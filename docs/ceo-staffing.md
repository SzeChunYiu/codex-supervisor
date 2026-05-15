# CEO staffing and scaling policy

## Cold-start policy (read this first)

**One shared node at a time. All projects share it. Second node only when first is near full.**

### LUNARC cold start

1. Start only `AI-factory-csup-b` (Node B holder): `csup start <project> --host=ng-meta-lunarc`
2. All projects and all team sessions attach to `AI-factory-csup-b` — no project-specific holder jobs.
3. Only book `AI-factory-csup-a` (Node A) when `AI-factory-csup-b` has ≥ 32 active panes. Check with `csup steward`.
4. Maximum 2 nodes at any time. If both are full, hold — do not request a third.

**Never create a project-specific SLURM holder** (e.g. `civic-csup`, `mcaccel-sup`). All sessions use `AI-factory-csup-a` or `AI-factory-csup-b`.

### Laptop cold start

Same principle: babbloo, neural_grow (local), and any other local project share the same laptop sessions. Do not start a separate session per project if the existing session has headroom.

## How to launch a self-running project

A human only needs to provide:
1. A `docs/parallel-sessions/<lane>.md` file for each work domain (stub is enough).
2. A `codex-prompts-team-meta.txt` with a single CEO pane pointing to this doc.
3. A `.codex-supervisor.toml` with only the CEO host entry pointing to the shared node (`AI-factory-csup-b` for LUNARC).

Then start the CEO session: `csup start <project> --host=<meta-host>`

The CEO reads the lane files, groups them into teams, writes `codex-prompts-team-<TEAM>.txt`, appends host entries to `.codex-supervisor.toml`, starts each team session, and enters the normal staffing loop. **Humans do not design the team structure** — that is the CEO's first task.

---

The CEO lane may change staffing, but only through measured demand, measured
capacity, and manager-owned acceptance gaps. Scaling is an executive decision,
not a reflex to keep panes busy.

## Authority boundaries

CEO may:

- add dynamic workers when managers have ready, leased, acceptance-linked work;
- reduce or stop worker capacity when queues are empty, work is blocked outside
  the team's control, or panes are stale/done/dead;
- move capacity between teams when the target manager has clearer acceptance
  gaps and safer leases;
- request additional SLURM station capacity through `csup staff` / `csup
  factory-run` / `csup station`.

CEO must not:

- bypass the manager/validator acceptance chain;
- start workers without a queue item, manager, writable lease, and evidence
  target;
- exceed node CPU/RAM/disk/load budgets to satisfy ambition;
- kill a session unless the manager has confirmed no unchecked acceptance row
  depends on that session.

## Staffing loop

1. **Measure demand.** Count `codex-tasks/blockers.txt`, `codex-tasks/open.txt`,
   worker queues, and unchecked `TEAM_PLAN.md` acceptance rows.
2. **Measure supply.** Check running panes, stale/done/dead panes via `csup
   steward`, and host/node headroom.
3. **Choose posture.** Use one of:
   - `hold`: keep CEO/manager/quality only;
   - `add`: start more workers for queued work;
   - `reduce`: stop/recycle worker sessions with no linked work;
   - `move`: shrink one team and start another with higher priority demand.
4. **Delegate.** CEO records the staffing decision; managers write worker
   prompts and leases.
5. **Audit.** Validator accepts/rejects evidence; CEO reviews whether staffing
   helped or created waste.

## Command interface

### Open a team
Write a prompts file, add a host entry to `.codex-supervisor.toml` and
`~/.config/csup/hosts.toml`, then:
```bash
/home/billy/bin/csup start babbloo --host=<TEAM>
```

### Close a team
```bash
/home/billy/bin/csup stop babbloo --host=<TEAM>
```
Only safe after the team's manager confirms no unchecked acceptance row depends
on that session. Update TEAM_PLAN.md active roster to remove the closed team.

### Scale workers up (demand-driven)
```bash
csup staff babbloo --dry-run                      # preview
csup staff babbloo --apply                        # act
csup staff babbloo --host=<TEAM> --apply          # single team
```

### Scale workers down / recycle idle sessions
```bash
csup steward babbloo                              # identify stale/dead panes
csup staff babbloo --apply --allow-stop           # stop sessions with no queued work
```

### Staffing gate (scale decisions)
```bash
csup staff <project> --scenario=resume --dry-run
csup staff <project> --host=<host> --scenario=blockers --apply
```

`csup staff` is deliberately conservative:

- if queued work exists, it prints `STAFF-UP` and delegates to `factory-run`,
  which sizes sessions/workers from queue depth and node capacity;
- if no queued work exists, it prints `STAFF-DOWN` and recommends stopping or
  shrinking worker capacity;
- it does **not** stop sessions unless `--apply --allow-stop` is supplied;
- on SLURM hosts, it still uses `csup station`; it never runs workers on the
  login node.

Use `--allow-stop` only after a manager has updated `TEAM_PLAN.md` to show that
no unchecked acceptance row depends on the target session. The safe default is
recommendation, not killing.

## Decision table

| Condition | CEO decision | Command |
| --- | --- | --- |
| Shared blockers exist | Add blocker workers first | `csup staff babbloo --scenario=blockers --dry-run` |
| Open queue exceeds active worker capacity and node headroom exists | Add workers | `csup staff babbloo --scenario=resume --apply` |
| Open queue exists but node load/disk/RAM is full | Hold or move to another host | `csup staff babbloo --host=<host> --dry-run` |
| No queued work; panes are done/stale/dead | Reduce/recycle | `csup steward babbloo` then `csup staff babbloo --dry-run` |
| No queued work and manager has accepted/shrunk the batch | Stop session | `csup stop babbloo --host=<team>` |
| Project needs a new team (new domain or overflow) | Open a new team | bootstrap protocol above → `csup start babbloo --host=<new-team>` |
| Project is over-staffed in a domain | Close a team | manager confirms no open acceptance rows → `csup stop babbloo --host=<team>` |
| Work needs special lease/host | Create specified lead/team, not generic workers | update `TEAM_PLAN.md` active roster and `codex-tasks/<lane>.txt` |

## Team session bootstrap

When no structured sessions exist (or only flat worker panes with no MANAGER),
CEO bootstraps team structure before running any staffing commands.

### Bootstrap protocol

1. **Audit lanes.** List `docs/parallel-sessions/*.md` (each file = one lane).
   Exclude meta-files (AI_FACTORY, TEAM_PLAN, VERSION_BOARD, etc.). Group lanes
   into 2–3 domain teams (e.g. quality: bugs/sec/test; growth: data/perf/ux/qa-ui/delight).

2. **Write a prompts file** for each team at `codex-prompts-<TEAM>.txt`.
   Rules that must be followed:
   - **≤50 words per `/goal` line** (the supervisor rejects longer lines with an error).
   - PANE 0 must be the manager; lane name must contain `manager`
     (e.g. `MANAGER-quality`) so the dashboard renders it as a Manager pane.
   - Workers follow as PANE 1, 2, … using the same format as existing worker prompts.
   - Manager prompt template (trim to ≤50 words):
     ```
     /goal You are PANE 0, lane MANAGER-<TEAM>. Manage Team <TEAM>: <lane1> (pane 1), <lane2> (pane 2)... Read docs/parallel-sessions/MANAGER.md and TEAM_PLAN.md for your role. Review worker evidence, accept/reject, queue next tasks, report scaling proposals to CEO via codex-tasks/ceo.txt. Iterate until rate-limited.
     ```
   - Worker prompt template:
     ```
     /goal You are PANE N, lane <LANE>. Read docs/parallel-sessions.md, docs/parallel-sessions/AI_FACTORY.md, docs/parallel-sessions/TEAM_PLAN.md, and docs/parallel-sessions/<LANE>.md, then iterate per the protocol until rate-limited.
     ```

3. **Register the host** by appending to `.codex-supervisor.toml` in the project root:
   ```toml
   [hosts."<TEAM>"]
   ssh = "billy@100.75.122.10"
   project_dir = "/home/billy/Desktop/projects/babbloo"
   prompts = "codex-prompts-<TEAM>.txt"
   tasks_dir = "codex-tasks"
   session = "babbloo-<TEAM>"
   role = "team"
   ```
   Also append the same entry to `~/.config/csup/hosts.toml` on this machine:
   ```toml
   [hosts."<TEAM>"]
   ssh = "billy@100.75.122.10"
   reachable = "ssh -o ConnectTimeout=3 -o BatchMode=yes billy@100.75.122.10 true"
   hostname_match = "billy"
   supervisor = "/home/billy/codex-supervisor.sh"
   ```

4. **Start the session:**
   ```bash
   /home/billy/bin/csup start babbloo --host=<TEAM>
   ```

5. **Record in TEAM_PLAN.md** — add a row for each new team with manager, workers,
   acceptance items, and writable leases.

After bootstrap, re-run the normal staffing loop.

## Anti-waste rules

- One manager can supervise only a bounded number of active workers; if workers
  outpace validation, add/reassign a manager before adding more workers.
- A worker with no acceptance-linked task is inventory, not progress.
- A high-load node is a blocker, not a challenge to overcome by force.
- Shrinking idle teams is a success when it protects focus and cost.
