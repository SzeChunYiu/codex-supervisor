# GM staffing and scaling policy

The GM lane may change staffing, but only through measured demand, measured
capacity, and manager-owned acceptance gaps. Scaling is an executive decision,
not a reflex to keep panes busy.

## Authority boundaries

GM may:

- add dynamic workers when managers have ready, leased, acceptance-linked work;
- reduce or stop worker capacity when queues are empty, work is blocked outside
  the team's control, or panes are stale/done/dead;
- move capacity between teams when the target manager has clearer acceptance
  gaps and safer leases;
- request additional SLURM station capacity through `csup staff` / `csup
  factory-run` / `csup station`.

GM must not:

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
   - `hold`: keep GM/manager/quality only;
   - `add`: start more workers for queued work;
   - `reduce`: stop/recycle worker sessions with no linked work;
   - `move`: shrink one team and start another with higher priority demand.
4. **Delegate.** GM records the staffing decision; managers write worker
   prompts and leases.
5. **Audit.** Validator accepts/rejects evidence; GM reviews whether staffing
   helped or created waste.

## Command interface

Use the GM staffing gate before changing worker counts:

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

| Condition | GM decision | Command |
| --- | --- | --- |
| Shared blockers exist | Add blocker workers first | `csup staff <project> --scenario=blockers --dry-run` |
| Open queue exceeds active worker capacity and node headroom exists | Add workers | `csup staff <project> --scenario=resume --apply` |
| Open queue exists but node load/disk/RAM is full | Hold or move to another host | `csup staff <project> --host=<host> --dry-run` |
| No queued work; panes are done/stale/dead | Reduce/recycle | `csup steward <project>` then `csup staff <project> --dry-run` |
| No queued work and manager has accepted/shrunk the batch | Stop configured session | `csup staff <project> --host=<host> --apply --allow-stop` |
| Work needs special lease/host | Create specified lead/team, not generic workers | update `TEAM_PLAN.md` and `codex-tasks/<lane>.txt` |

## Anti-waste rules

- One manager can supervise only a bounded number of active workers; if workers
  outpace validation, add/reassign a manager before adding more workers.
- A worker with no acceptance-linked task is inventory, not progress.
- A high-load node is a blocker, not a challenge to overcome by force.
- Shrinking idle teams is a success when it protects focus and cost.
