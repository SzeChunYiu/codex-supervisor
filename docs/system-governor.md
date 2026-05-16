# Cross-project supervisor system

`csup` is the system-level governor for multiple `codex-supervisor` projects.
Each project contributes work by keeping queue files in `codex-tasks/` and a
`.codex-supervisor.toml` that points each host at prompts, queues, and a session
name. Shared acceptance blockers go in `codex-tasks/blockers.txt` and are
counted as first-priority dynamic-worker work. Generic work goes in
`codex-tasks/open.txt`; specialized work goes in `codex-tasks/<lane>.txt`.

`csup` supplies capacity; the project-level AI factory supplies convergence.
Before a project is governed, its validator should keep
`docs/parallel-sessions/TEAM_PLAN.md` current with the batch outcome,
acceptance checklist, artifact ledger, leases, and blockers. The governor then
starts only the workers needed to shrink those queues toward acceptance.

## Runtime and disk policy

Default runtime root:

```text
/Volumes/MyDrive/codex-supervisor
```

If MyDrive is not mounted, the fallback is `~/.codex-supervisor`. Override with
`CODEX_SUPERVISOR_ROOT` or `CSUP_RUNTIME_ROOT`.

Worker processes inherit these redirected locations:

- `CODEX_HOME=$CODEX_SUPERVISOR_ROOT/codex-home/<session>`
- `XDG_CACHE_HOME=$CODEX_SUPERVISOR_ROOT/cache/<session>/xdg`
- `npm_config_cache=$CODEX_SUPERVISOR_ROOT/cache/<session>/npm`
- `UV_CACHE_DIR=$CODEX_SUPERVISOR_ROOT/cache/<session>/uv`
- `PIP_CACHE_DIR=$CODEX_SUPERVISOR_ROOT/cache/<session>/pip`
- `PLAYWRIGHT_BROWSERS_PATH=$CODEX_SUPERVISOR_ROOT/cache/<session>/playwright`
- `CARGO_HOME=$CODEX_SUPERVISOR_ROOT/cache/<session>/cargo`
- `TMPDIR=$CODEX_SUPERVISOR_ROOT/tmp/<session>`

This keeps npm/uv/pip/playwright/codex logs away from the root disk.

## Queue submission

```bash
csup submit <project> <lane> "short goal text"
# generic dynamic-worker task:
csup submit <project> open "short goal text"
```

If the text does not start with `/goal`, `csup submit` prefixes it. The target
file is `codex-tasks/<lane>.txt` in the first host config that declares a
`tasks_dir`.

## Dynamic allocation

```bash
csup capacity
csup govern --dry-run
csup govern --apply
```

The governor:

1. Discovers projects from `.codex-supervisor.toml`.
2. Counts queued `/goal` tasks per specified lane and in shared dynamic queues
   (`blockers`, `blocker`, `open`, `worker`, `workers`, `dynamic`).
3. Checks local CPU load, free RAM, free disk on the runtime root, and currently
   running tmux panes.
4. Starts only non-running local sessions with queued work that fits capacity.
5. Passes `CODEX_SUPERVISOR_LANES`, `CODEX_SUPERVISOR_DYNAMIC_WORKERS`, and
   `CODEX_SUPERVISOR_MAX_PANES` so one prompts file can be filtered down to
   fixed `GM`/`DEBUG`/`VALIDATOR` panes, specified lanes, and the dynamic worker
   count needed for open tasks.

Run `csup capacity` first when trying to maximize parallelism. It exposes the
same capacity calculation as `govern` with `available=<N>` and
`bottleneck=<session_cap|ram|disk|load>`, plus the per-resource room, so the
operator can scale workers up to the current safe ceiling instead of guessing.
The `govern` header repeats that bottleneck so dry-runs explain why a host can
or cannot accept another worker wave. Use `csup capacity --json` for scripts
or dashboards that need the same calculation in a stable machine-readable
shape.

The governor intentionally does not decide product direction. If queues grow
without closing acceptance checklist gaps, the project validator should stop
queueing side work and refresh the factory board.

## Factory audit

```bash
csup factory-audit <project>
csup factory-audit --project=<project>
```

`factory-audit` is the management-system check above `govern`. It reads each
host stanza's prompt file and task directory, checks whether factory docs and
`docs/blocker-schema.md` plus `docs/parallel-sessions/VERSION_BOARD.md` are
installed, counts shared blockers, open work, lane-specific work, and prompt
lines, verifies the shared `blockers.txt` queue exists when a task directory
exists, then emits:

- `RED` when factory docs are missing or `blockers.txt` contains `/goal` lines.
- `YELLOW` when no shared blocker exists but queued acceptance-gap work remains.
- `GREEN` when no queued work remains and the validator should confirm accepted
  outcomes or queue the next acceptance gap.

Useful knobs:

- `CSUP_GOVERNOR_MAX_TOTAL_PANES` default `8`
- `CSUP_GOVERNOR_RAM_MB_PER_PANE` default `700`
- `CSUP_GOVERNOR_MIN_FREE_RAM_MB` default `2048`
- `CSUP_GOVERNOR_DISK_MB_PER_PANE` default `1024`
- `CSUP_GOVERNOR_MIN_FREE_DISK_GB` default `10`
- `CSUP_GOVERNOR_MAX_LOAD_PER_CPU` default `1.25`

## Station allocation for SLURM/LUNARC

Use `csup station` when an AI/operator session needs remote capacity instead
of hand-picking a login shell or compute node:

```bash
csup station <project> --host=lunarc --sessions=1 --workers=4 --dry-run
csup station <project> --host=lunarc --sessions=1 --workers=4 --apply
```

The station API treats a request as:

- `sessions`: number of supervisor tmux sessions to place.
- `workers`: number of generated dynamic workers per session.
- `panes_per_session = workers + 3` for the fixed `GM`, `DEBUG`, and `VALIDATOR`
  panes.

For SLURM hosts, station placement:

1. checks the login endpoint only for scheduler control;
2. inspects configured holder slots (`slurm_job_name`, then
   `slurm_job_name-2`, ... up to `slurm_slots`);
3. measures current tmux pane usage inside each running allocation with
   `srun --jobid=<job> --overlap`;
4. starts on an existing allocation when `slurm_max_panes - used` can fit the
   requested panes;
5. submits the next empty slot when all running slots are full; and
6. prints `HOLD ... reason=slurm_queue` when the submitted allocation is still
   queued.

This command is fail-closed: it does not run Codex work on the login node, and
it does not silently fall back to local resources. Configure per-host
`slurm_max_panes` in `~/.config/csup/hosts.toml` so station capacity reflects
how many panes that node can run without overload. The default project node cap
is two computer nodes (`CSUP_PROJECT_MAX_NODES`, or `project_max_nodes` in host
inventory for a lower cap; values above 2 are clamped). `slurm_slots` is capped by that policy: do not expand a project beyond two SLURM allocations; instead pack more panes into
the existing allocations until CPU/load/disk/RAM headroom says they are full.

## Cleanup cadence

`codex-supervisor` now prunes supervisor-owned cache/tmp directories every 120s
and removes entries older than 5 minutes. The explicit `cleanup` command also
runs the same runtime-root prune before sweeping old worktrees and logs.
