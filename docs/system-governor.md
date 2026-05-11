# Cross-project supervisor system

`csup` is the system-level governor for multiple `codex-supervisor` projects.
Each project contributes work by keeping queue files in `codex-tasks/<lane>.txt`
and a `.codex-supervisor.toml` that points each host at prompts, queues, and a
session name.

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
```

If the text does not start with `/goal`, `csup submit` prefixes it. The target
file is `codex-tasks/<lane>.txt` in the first host config that declares a
`tasks_dir`.

## Dynamic allocation

```bash
csup govern --dry-run
csup govern --apply
```

The governor:

1. Discovers projects from `.codex-supervisor.toml`.
2. Counts queued `/goal` tasks per lane.
3. Checks local CPU load, free RAM, free disk on the runtime root, and currently
   running tmux panes.
4. Starts only non-running local sessions with queued lanes that fit capacity.
5. Passes `CODEX_SUPERVISOR_LANES` and `CODEX_SUPERVISOR_MAX_PANES` so one
   prompts file can be filtered down to the active lanes plus one planner pane.

Useful knobs:

- `CSUP_GOVERNOR_MAX_TOTAL_PANES` default `8`
- `CSUP_GOVERNOR_RAM_MB_PER_PANE` default `700`
- `CSUP_GOVERNOR_MIN_FREE_RAM_MB` default `2048`
- `CSUP_GOVERNOR_DISK_MB_PER_PANE` default `1024`
- `CSUP_GOVERNOR_MIN_FREE_DISK_GB` default `10`
- `CSUP_GOVERNOR_MAX_LOAD_PER_CPU` default `1.25`

## Cleanup cadence

`codex-supervisor` now prunes supervisor-owned cache/tmp directories every 120s
and removes entries older than 5 minutes. The explicit `cleanup` command also
runs the same runtime-root prune before sweeping old worktrees and logs.
