# codex-supervisor

Run multiple [codex](https://github.com/openai/codex) CLI sessions in parallel
tmux panes, with auto-prompting, auto-respawn on usage limits, auto-resend
when a `/goal` completes, an even MxN grid layout that stays equal, and a
clean subcommand CLI for inspecting and controlling individual panes.

Cross-platform: macOS + Linux. Single Bash file. No build step.

```
PANE  LANE         STATE        TAIL
----  ----         -----        ----
0     bugs         WORKING      gpt-5.5 ... Pursuing goal (9m)
1     perf         READY        gpt-5.5 xhigh fast ...
2     data         DONE         Goal achieved (2m)
3     qa-ui        WORKING      Pursuing goal (9m)
4     ux           WORKING      Pursuing goal (9m)
5     sec          STARTING     Starting MCP servers (12/15)
6     test         WORKING      Pursuing goal (9m)
7     parity       LIMITED      You've hit your usage limit ...
```

---

## Install

```sh
git clone https://github.com/SzeChunYiu/codex-supervisor.git
cd codex-supervisor
chmod +x codex-supervisor.sh
ln -s "$(pwd)/codex-supervisor.sh" ~/.local/bin/codex-supervisor   # optional
```

Requirements:

- `tmux` (`brew install tmux` / `apt install tmux`)
- `codex` CLI on `$PATH`
- Bash 3.2+ (macOS default works; Linux distros ship 5.x)
- `python3` (used to compute equal-grid tmux layout strings; falls back to tmux's built-in `tiled` if missing)

---

## Quick start

```sh
# 1. Create a prompts file. Every non-comment line must start with `/goal`,
#    stay within 50 words, and point at markdown instructions.
cp codex-prompts.example.txt codex-prompts.txt
$EDITOR codex-prompts.txt

# 2. Validate the prompt contract.
codex-supervisor validate-prompts

# 3. Start the supervisor.
codex-supervisor start

# (or just `codex-supervisor` -- with no subcommand it runs `start`)
```

A new terminal window opens attached to the tmux session, with one tiled
codex pane per prompt. Each pane runs the `codex` CLI; once it's ready,
the supervisor auto-types the prompt and submits it. By default the
supervisor also appends three generated fixed panes unless your prompt file
already defines them:

- `GM` — a real executive Codex session that sets direction, reviews managers,
  and makes staffing/escalation decisions.
- `DEBUG` — carefully debugs/optimizes one code slice per iteration.
- `VALIDATOR` — acts as the default manager: validates worker results, refreshes
  `docs/parallel-sessions/TEAM_PLAN.md`, reports to GM, and queues the next
  compact-safe prompts.

Default safety cap: at most 8 prompts/panes per supervisor session
(`CODEX_SUPERVISOR_MAX_PANES=8`). Start fewer when the work or host resources
do not justify 8. For 12-20 total Codex workers, split deliberately across
projects/hosts with `csup`; keep each project/batch right-sized.

---

## Prompt design — short prompts, details in `.md`

The supervisor types each `/goal` prompt **character-by-character** into
the codex TUI. Multi-paragraph prompts get truncated, scrambled, or
rejected, and panes time out at the readiness gate. Long prompts also
hide the rules from the lane after its first iteration, since codex
won't re-type them.

**Pattern (recommended): one-line `/goal` that names per-lane `.md`.**

`codex-prompts.txt`:

```
/goal You are PANE 0, lane bugs. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then iterate per the protocol until rate-limited.
/goal You are PANE 1, lane perf. Read docs/parallel-sessions.md and docs/parallel-sessions/perf.md, then iterate per the protocol until rate-limited.
```

Each prompt is one line, no embedded newlines, and at most 50 words. The
supervisor validates this before launch. See [`docs/prompts.md`](docs/prompts.md)
for the full prompt contract.

Detail lives in `.md` files under your repo:

- `docs/parallel-sessions.md` — **shared protocol** (lanes table,
  per-iteration cycle, branching/merging rules, stop conditions, "when
  to ask" exceptions). Lanes re-read this at the start of every
  iteration so edits flow without re-typing prompts.
- `docs/distributed-protocol.md` — **multi-host constitution** for projects
  that may run on laptop, local Mac/Mac mini, LUNARC, or another remote node:
  one project identity, no anonymous source copies, one writable lease per
  scope, Git-only source movement, and fail-closed conflict handling.
- `docs/ai-factory.md` — **factory operating model**: one batch outcome,
  GM/manager-owned acceptance checklist, artifact ledger, lane leases, and
  blocker-driven queues so panes converge on the same outcome.
- `docs/company-operating-model.md` — **company-style role model**: real GM
  session, fixed management/quality roles, specified functional leads, dynamic workers,
  specialist contractors, DRI rows, decision rights, and manager/escalation
  paths.
- `docs/gm-staffing.md` — **GM staffing/scaling gate**: add, reduce, hold, or move workers from queue demand and node resources.
- `docs/version-management.md` — **batch PR train**: worker branches feed one
  accepted `batch/<date>-<slug>` PR instead of creating small review-facing PRs.
- `templates/TEAM_PLAN.md` — starter board to copy into each project as
  `docs/parallel-sessions/TEAM_PLAN.md`.
- `templates/ROLE_CHARTER.md` — starter charter for each fixed, specified,
  dynamic, or specialist pane role.
- `templates/BATCH_VERSION_PLAN.md` — starter release-train board to copy into
  each project as `docs/parallel-sessions/VERSION_BOARD.md`.
- `docs/parallel-sessions/<lane>.md` — **per-lane spec** (branch
  prefix, writable targets, required reading, working rhythm, scope
  guardrails, stop condition).
- `docs/parallel-sessions/general-manager.md`,
  `docs/parallel-sessions/debugger.md`,
  `docs/parallel-sessions/validator-planner.md`, and
  `docs/parallel-sessions/dynamic-worker.md` — default fixed-role and worker
  pool contracts.

Why this works:

- The TUI only has to receive ~20 chars before pressing enter.
- Codex `cd`s, reads the doc, and follows it — exactly as a human would.
- Editing the lane spec edits everyone's behaviour at the next
  iteration; you don't have to stop the supervisor.
- Each lane pane stays comprehensible at the next code review:
  "what is pane 3 doing?" → open `docs/parallel-sessions/<lane>.md`.

What goes in the **prompt** (verbatim, every char counts):

- A pane identifier (`PANE N`).
- A lane label (`lane bugs`).
- Two doc paths to read (relative to codex's CWD).
- A loop directive (`iterate per the protocol until rate-limited`).

What goes in the **shared `.md`**:

- Lanes table (pane → branch → worktree → focus).
- Rules every session follows: re-read protocol; stay in lane; commit
  message format; worker branches feed the batch PR train; rebase before push;
  status board entry; conflict policy; "when to stop and ask".
- The current batch outcome and definition of accepted evidence, normally in
  `docs/parallel-sessions/TEAM_PLAN.md`.
- For distributed projects, host/source-tree leases: canonical checkout vs.
  registered Git worktree vs. execution mirror, and which lane owns each
  writable path.

What goes in the **per-lane `.md`**:

- Branch prefix and worktree path.
- Host role and source tree class.
- Writable targets (which files this lane is allowed to touch).
- Goal (one paragraph).
- Working rhythm (numbered iteration cycle).
- Scope guardrails ("don't write a scraper if the spec says no scrapers").
- Required reading.
- Stop condition.

Reference example: <https://github.com/SzeChunYiu/babbloo> demonstrates
this pattern at scale (8 lanes, dedicated + worker pool).

### Fixed roles plus dynamic workers

For new queue-backed projects, prefer this shape:

1. Keep the fixed `DEBUG` and `VALIDATOR` sessions enabled.
2. Copy `templates/TEAM_PLAN.md` into the project and let VALIDATOR maintain
   the batch outcome, DRI-based acceptance checklist, role roster, and artifact
   ledger.
3. Copy `templates/BATCH_VERSION_PLAN.md` into the project as
   `docs/parallel-sessions/VERSION_BOARD.md`; only VALIDATOR/RELEASE_LEAD opens
   the normal review-facing PR for the batch branch.
4. Add specified functional leads only when the work needs a durable role such
   as `TECH_LEAD`, `RESEARCH_LEAD`, `OPS_LEAD`, `DATA_LEAD`,
   `RELEASE_LEAD`, or `SECURITY_REVIEWER`.
5. Put generic follow-up tasks in `codex-tasks/open.txt`.
6. Start N generated dynamic workers with `CODEX_SUPERVISOR_DYNAMIC_WORKERS=N`.
7. Use `codex-tasks/<lane>.txt` only for specialized lanes with explicit leases.

Dynamic workers consume shared blocker queues first, then their own
worker-specific queue, then shared open queues (`open`, `worker`, `workers`,
`dynamic`). `blockers` / `blocker` is stop-the-line work: common acceptance
blockers outrank worker-specific and normal open progress. Dynamic workers do
not consume specified lane queues unless a lane spec/lease grants that
ownership. When their queue is empty, they inspect the factory board and either
close an unchecked acceptance gap or leave a validator handoff; they should not
invent a parallel product.

### Anti-pattern: long inline prompts

```
/goal LANE L0. Working directory: /Volumes/MyDrive/.../simulation-L0. Branch: lane/L0. Sole writable target: docs/foo.md. Read CODING_STANDARDS.md and docs/foo.md first. Then for each X under Y/*.cc and each Z under W/*.cc, expand the relevant § with a long list of requirements ... Per-iteration cycle: (a) one X or Z per iteration; (b) edit only the target file; (c) keep every file <= 500 lines; (d) git add, git commit with message "..." and trailers ...; (e) run bash /path/to/merge.sh ...; (f) continue. Stop only when ...
```

This kind of multi-clause prompt fails reliably:

- Backslash-escaping into the TUI input gets out of sync.
- The pane status reads "Press enter to continue" forever.
- Even when delivered, the agent sees the rules only once and forgets
  the merge step on iteration 2.

If you find yourself writing extra clauses into a `/goal`, move that detail to
a `.md`. The hard budget is 50 words; shorter is better.

### Cwd matters

Codex panes inherit the working directory of `codex-supervisor` when
launched. If your prompts use relative paths like
`docs/parallel-sessions.md`, invoke the supervisor from the repo root
that contains those paths, **not** from the directory holding
`codex-prompts.txt` if that directory is a sub-folder.

A common pattern is a thin `start.sh` that `cd`s to the repo root and
sets `CODEX_SUPERVISOR_PROMPTS=$REPO/scripts/codex-supervisor/codex-prompts.txt`.

---

## Subcommands

```
codex-supervisor [SUBCOMMAND] [args...]

  start [--no-attach]       launch the session (default if no subcommand)
  stop                      kill the session and all panes
  status                    print pane states (lane, state, last activity)
  attach                    attach to the session
  logs [-f]                 show or tail the supervisor log
  send <pane|lane> <text>   send text to a specific pane
  restart <pane|lane>       respawn one pane with a fresh codex
  relayout                  re-apply the equal MxN grid (use after window resize)
  prompts                   print the resolved prompts file
  validate-prompts          validate /goal + 50-word + markdown-backed prompts
  queue                     show queued tasks per lane
  help                      this help text
```

`<pane|lane>` accepts either the numeric tmux pane index (`0`, `1`, ...)
or the lane label parsed from the prompt (`bugs`, `parity`, ...).

Examples:

```sh
codex-supervisor status
codex-supervisor send 3 "/goal write a smoke test for the search input"
codex-supervisor restart parity
codex-supervisor logs -f
codex-supervisor stop
```

### Cross-project system mode (`csup`)

`bin/csup` is the project/host-level control plane. Projects expose
`.codex-supervisor.toml` and optional `codex-tasks/<lane>.txt` queues; the
governor scans those queues, checks local CPU/RAM/disk headroom, and starts
only the queued lanes that fit.

When a project can run on more than one host, treat
[`docs/distributed-protocol.md`](docs/distributed-protocol.md) as mandatory
operating law. `csup` may start the same project on laptop, Mac, and LUNARC,
but the project must still have one canonical identity, registered source
trees only, and one writable lease per branch/worktree/path.

```sh
csup submit <project> <lane> "short task for that lane"
csup govern --dry-run     # explain what would start
csup govern --apply       # start right-sized lane subsets
csup factory-audit <project>  # classify factory health before expanding work
csup staff <project> --scenario=resume --dry-run
csup staff <project> --scenario=resume --apply
csup factory-run <project> --scenario=resume --dry-run
csup factory-run <project> --scenario=resume --apply
csup station <project> --host=lunarc --sessions=1 --workers=4 --apply
csup status               # all configured projects/hosts
```

`govern` passes `CODEX_SUPERVISOR_LANES=<lane,csv>`,
`CODEX_SUPERVISOR_DYNAMIC_WORKERS=<N>`, and
`CODEX_SUPERVISOR_MAX_PANES=<fixed roles + selected lanes + dynamic workers>`
into `codex-supervisor`, so one large prompts file can be reused while the
system opens only the fixed roles, specified lanes, and open-task workers that
fit available resources.

`factory-audit` is the management gate for the AI factory model. It reports
`RED` when factory docs are missing, `docs/blocker-schema.md` is absent/invalid,
`docs/parallel-sessions/VERSION_BOARD.md` is missing, the shared
`blockers.txt` queue is missing, or shared blockers exist, `YELLOW` when queued
acceptance-gap work remains, and `GREEN` when the validator should either
confirm acceptance or queue the next gap. Use it before starting more panes.

`factory-run` is the safer one-command entrypoint for AI sessions that need to
resume a project without hand-sizing every station request. It counts queued
`/goal` work, refuses to allocate when there is no queued work, maps scenarios
to conservative budgets (`resume`, `balanced`, `full`, or `blockers`), and then
delegates to `govern` for local hosts or `station` for SLURM hosts. It defaults
to `--dry-run`; use `--apply` only after the plan shows the intended host,
session count, worker count, and pane count. Use `--max-workers`, `--max-panes`,
or `--sessions` to lower the budget, not to bypass station capacity checks.

For LUNARC and other SLURM hosts, `csup station` is the standardized
resource-allocation API for AI/operator sessions. Callers request a number of
supervisor sessions and dynamic workers; the station checks existing SLURM
holder allocations, places the session on an allocation with enough free pane
capacity, submits the next configured slot when current nodes are full, and
prints `HOLD ... reason=slurm_queue` instead of falling back to the login node
when the scheduler has not started the new node yet. The default project policy
is at most two computer nodes; maximize safe pane density within those nodes
rather than adding a third allocation.

Station starts are batched per running SLURM allocation: many supervisor
sessions can be launched by one persistent `srun --overlap` step instead of one
new job step per session. Tune `slurm_start_batch_size` (or
`CSUP_STATION_START_BATCH_SIZE`) only when the generated launch command becomes
too large; tune `slurm_start_stagger_secs` (or
`CSUP_STATION_START_STAGGER_SECS`) to control serialized starts inside that
single step. LUNARC hosts must be configured with `scheduler = "slurm"`; `csup`
refuses non-SLURM LUNARC starts so Codex panes are never spawned on the login
node.

---

## Pane controls (inside the attached tmux)

| Action                                   | Keys                          |
| ---------------------------------------- | ----------------------------- |
| Click pane to focus, drag border to resize, scroll to scroll back | mouse |
| Jump directly to pane 0..9               | `Alt+0` .. `Alt+9`            |
| Zoom focused pane fullscreen / restore   | `Ctrl+b` then `z`             |
| Detach without killing                   | `Ctrl+b` then `d`             |
| Cycle pane focus                         | `Ctrl+b` then `o`             |
| Scroll mode in / out                     | `Ctrl+b` then `[` / `q`       |

Each pane border shows its lane label (parsed from the prompt) so you
always know which pane is which.

---

## How it works

| Step              | Mechanism                                                                 |
| ----------------- | ------------------------------------------------------------------------- |
| Launch            | `tmux new-session` + N-1 `tmux split-window`, then equal-grid layout.     |
| Fixed roles       | Adds one `GM`, one `DEBUG`, and one `VALIDATOR` pane by default unless the prompt file already defines equivalent lanes. |
| Wait for ready    | Polls `tmux capture-pane` for `Tip:` AND no `Starting MCP`, then settles 5s and re-verifies before sending. |
| Send prompt       | `tmux send-keys` types the prompt + double Enter (codex's slash-command popup eats the first). |
| Detect limit      | Polls each pane every 60s for `You've hit your usage limit`.              |
| Recover           | After 3 consecutive hits, dead pane detection, or compact-task failure: `tmux respawn-pane -k` + resend prompt. Per-pane cooldown prevents MCP-reload thrashing. |
| Recreate session  | If the tmux session disappears while the daemon is still alive, it runs cleanup/resource checks and rebuilds the session (`CODEX_SUPERVISOR_AUTO_RECREATE_SESSION=1`). |
| Avoid compaction  | Short markdown-backed prompts, fresh Codex per goal, a 45-minute iteration cap, and fast respawn on compacting/compact-task markers keep lanes out of long-context compaction. |
| Auto-resend       | When a pane shows `Goal achieved` and stays idle past the grace window, the prompt is resent automatically so the lane keeps iterating. |
| Fresh-codex per goal | Before resending the next prompt, `tmux respawn-pane -k` kills the codex CLI and starts a new one (`CODEX_SUPERVISOR_RESPAWN_ON_GOAL=1`, default). Each iteration begins with a clean codex — no carried context, no stale MCP children, no leaked worktree handles. Set to `0` only if you specifically want the next `/goal` delivered into the same codex session. |
| Idempotent terminal open | `start` and `attach` check `tmux list-clients` and skip the new-window spawn if a client is already attached. This prevents window pile-up when scripts / recovery loops invoke them repeatedly. Set `CODEX_SUPERVISOR_FORCE_OPEN=1` to force a new window even when one is attached. |

---

## Configuration

Everything is overridable via env or CLI without editing the script:

| Env var                              | Default                                            |
| ------------------------------------ | -------------------------------------------------- |
| `CODEX_SUPERVISOR_PROMPTS`           | `./codex-prompts.txt` then `~/codex-prompts.txt`   |
| `CODEX_SUPERVISOR_SESSION`           | `codex-supervisor`                                 |
| `CODEX_SUPERVISOR_CMD`               | `codex --dangerously-bypass-approvals-and-sandbox` |
| `CODEX_SUPERVISOR_ROOT`              | `/Volumes/MyDrive/codex-supervisor` when mounted; else `~/.codex-supervisor` |
| `CODEX_SUPERVISOR_MCP_MODE`          | `off` (`off` / `inherit`)                          |
| `CODEX_SUPERVISOR_CODEX_HOME`        | `$CODEX_SUPERVISOR_ROOT/codex-home/<session>`      |
| `CODEX_SUPERVISOR_CACHE_ROOT`        | `$CODEX_SUPERVISOR_ROOT/cache/<session>`           |
| `CODEX_SUPERVISOR_TMP_ROOT`          | `$CODEX_SUPERVISOR_ROOT/tmp/<session>`             |
| `CODEX_SUPERVISOR_CODEX_HOME_PROFILE`| `lean` (`lean` omits skills/memories/plugins; `full` links them) |
| `CODEX_SUPERVISOR_NICE`              | `5` (`0` disables CPU priority lowering)           |
| `CODEX_SUPERVISOR_POLL`              | `60`                                               |
| `CODEX_SUPERVISOR_READY_TIMEOUT`     | `600`                                              |
| `CODEX_SUPERVISOR_READY`             | `Tip: `                                            |
| `CODEX_SUPERVISOR_NOT_READY`         | `Starting MCP`                                     |
| `CODEX_SUPERVISOR_READY_SETTLE`      | `5`                                                |
| `CODEX_SUPERVISOR_LIMIT`             | `You've hit your usage limit`                      |
| `CODEX_SUPERVISOR_HITS`              | `3`                                                |
| `CODEX_SUPERVISOR_RESPAWN_COOLDOWN`  | `300`                                              |
| `CODEX_SUPERVISOR_CAPTURE_LINES`     | `80`                                               |
| `CODEX_SUPERVISOR_LOG`               | `$CODEX_SUPERVISOR_ROOT/logs/<session>.log`        |
| `CODEX_SUPERVISOR_OPEN`              | `1`                                                |
| `CODEX_SUPERVISOR_AUTO_RESEND`       | `1`                                                |
| `CODEX_SUPERVISOR_RESEND_GRACE`      | `30`                                               |
| `CODEX_SUPERVISOR_ON_COMPLETE`       | `queue-redo` (`queue` / `queue-redo` / `redo` / `rest`) |
| `CODEX_SUPERVISOR_CONTINUOUS_LANES`  | `*` (every lane re-sends `/goal` after GOAL_DONE — see `docs/never-waste-workers.md`. Set to a space-separated lane list to limit, or empty to disable) |
| `CODEX_SUPERVISOR_RESPAWN_ON_GOAL`   | `1`                                                |
| `CODEX_SUPERVISOR_GM`               | `1` (append one generated GM lane if missing) |
| `CODEX_SUPERVISOR_GM_DOC`           | `/Users/billy/Desktop/projects/codex-supervisor/docs/parallel-sessions/general-manager.md` |
| `CODEX_SUPERVISOR_DEBUGGER`          | `1` (append one generated DEBUG lane if missing) |
| `CODEX_SUPERVISOR_DEBUGGER_DOC`      | `/Users/billy/Desktop/projects/codex-supervisor/docs/parallel-sessions/debugger.md` |
| `CODEX_SUPERVISOR_VALIDATOR`         | `1` (append one generated VALIDATOR lane if missing) |
| `CODEX_SUPERVISOR_PLANNER`           | Alias for `CODEX_SUPERVISOR_VALIDATOR` |
| `CODEX_SUPERVISOR_VALIDATOR_DOC`     | `/Users/billy/Desktop/projects/codex-supervisor/docs/parallel-sessions/validator-planner.md` |
| `CODEX_SUPERVISOR_DYNAMIC_WORKERS`   | `0` generated dynamic worker panes |
| `CODEX_SUPERVISOR_DYNAMIC_WORKER_DOC`| `/Users/billy/Desktop/projects/codex-supervisor/docs/parallel-sessions/dynamic-worker.md` |
| `CODEX_SUPERVISOR_GENERATED_ONLY`    | `0`; set `1` to ignore prompt-file lanes and run generated fixed/dynamic lanes only |
| `CODEX_SUPERVISOR_RESPAWN_DEAD_PANES`| `1`                                                |
| `CODEX_SUPERVISOR_AUTO_RECREATE_SESSION` | `1`                                            |
| `CODEX_SUPERVISOR_MAX_ITERATION_SECS`| `2700`                                             |
| `CODEX_SUPERVISOR_MAX_PROMPT_WORDS`  | `50`                                               |
| `CODEX_SUPERVISOR_LANES`             | unset; optional comma/space lane allowlist          |
| `CODEX_SUPERVISOR_MAX_PANES`         | `8`                                                |
| `CODEX_SUPERVISOR_RAM_MB_PER_PANE`   | `600`                                              |
| `CODEX_SUPERVISOR_DISK_MB_PER_PANE`  | `1024`                                             |
| `CODEX_SUPERVISOR_START_STAGGER_SECS`| unset = auto (`0` for <=2 panes, `1` for 3-5, `2` for 6+) |
| `CODEX_SUPERVISOR_FORCE_OPEN`        | `0`                                                |

`start` accepts: `--prompts <file>`, `--session <name>`, `--no-attach`.

---

## Prompts file format

```text
# Comments start with #, blank lines ignored.
# One prompt per line; sent verbatim to its codex pane.
# Every prompt starts with /goal, has <=50 words, and references .md docs.
# Lines must NOT contain literal newlines (newlines submit prematurely).

/goal You are PANE 0, lane BUGS. Read docs/parallel-sessions.md and ...
/goal You are PANE 1, lane PERF. Read docs/parallel-sessions.md and ...
```

Detailed rules and templates:

- [`docs/prompts.md`](docs/prompts.md) — prompt contract and validation.
- [`docs/parallel-sessions.md`](docs/parallel-sessions.md) — shared compact-safe
  workflow.
- [`docs/parallel-sessions/lane-template.md`](docs/parallel-sessions/lane-template.md)
  — per-lane markdown template.

The supervisor parses a lane label from each prompt (`lane FOO` /
`lane: FOO` / `[FOO]`) and uses it for pane border titles and as a friendly
alias in `send` / `restart`.

---

## Performance notes

This script has been tuned to keep system load reasonable while running
8-10 codex sessions in parallel:

- **Respawn cooldown** (5 min/pane default) — prevents MCP-server reload
  thrash when a pane is in a sustained limit/error state.
- **Bounded `capture-pane`** — only the last 80 lines are scanned per check
  (status bar always at the bottom; full pane is wasted work).
- **Compact-safe iterations** — prompt detail lives in markdown, each goal is
  expected to finish one bounded iteration, `RESPAWN_ON_GOAL=1` starts the next
  task fresh, and `MAX_ITERATION_SECS=2700` restarts sessions before long
  conversations drift into remote compaction.
- **MCP-free startup by default** — panes run with an isolated `CODEX_HOME`
  whose `config.toml` preserves normal Codex settings but strips
  `[mcp_servers.*]`. This avoids every pane starting `npx`/`uvx` MCP trees,
  timing out at `Starting MCP`, and leaving orphaned child processes. Set
  `CODEX_SUPERVISOR_MCP_MODE=inherit` only for lanes that truly need MCP tools.
- **Lean worker Codex home by default** — the isolated `CODEX_HOME` preserves
  auth, core config, `AGENTS.md`, `RTK.md`, and hooks, but omits
  skills/memories/plugins unless `CODEX_SUPERVISOR_CODEX_HOME_PROFILE=full`.
  This keeps 12-20 supervised workers from loading operator-only context.
- **MyDrive runtime/cache root by default** — when `/Volumes/MyDrive` is
  mounted, supervisor runtime goes under `/Volumes/MyDrive/codex-supervisor`.
  Worker `CODEX_HOME`, `XDG_CACHE_HOME`, `npm_config_cache`, `UV_CACHE_DIR`,
  `PIP_CACHE_DIR`, `PLAYWRIGHT_BROWSERS_PATH`, `CARGO_HOME`, logs, and temp
  files are redirected there instead of the cramped root volume.
- **Aggressive cleanup cadence** — periodic cleanup now runs every 120s and
  prunes supervisor-owned cache/tmp entries older than 5 minutes, while
  explicit `cleanup` also sweeps the runtime root and old Codex logs/sessions.
- **Resource-budget preflight** — `start` refuses when projected RAM/disk for
  the selected pane count would violate the configured reserve. Disk projection
  uses the supervisor runtime root (MyDrive when mounted), while the existing
  minimum-free check still protects the project checkout volume. Tune with
  `CODEX_SUPERVISOR_RAM_MB_PER_PANE` and `CODEX_SUPERVISOR_DISK_MB_PER_PANE`
  only after measuring real workloads.
- **CPU priority + staged startup** — workers run through `nice -n 5` by
  default, and sessions with 3+ panes stagger pane/prompt startup to avoid a
  CPU/RAM spike from all Codex processes booting simultaneously.
- **60s poll interval** — 30s was overhead for limited additional signal.
- **Equal grid via custom layout string** — tmux's built-in `tiled` gives
  the last row extra height when N isn't a perfect square; we compute and
  apply an even MxN layout instead.
- **`mouse on` + `escape-time 50ms` + `status off`** in the session config
  — fewer redraws on the attached client.

If you still find the attached terminal laggy with many panes, the biggest
remaining lever is the terminal emulator: GPU-accelerated terminals
(Alacritty, Wezterm, Ghostty) handle 8-10 simultaneously-redrawing TUI
sessions far better than the system default.

---

## Caveats

- The codex usage-limit message is account-wide. Respawning gives you a
  fresh client, but the same account hits the same limit again until the
  reset time printed in the message. The script keeps respawning (with
  cooldown) by design — so you resume the moment the window opens.
- Concurrent codex sessions writing to the same git checkout will collide
  (`index.lock`). For multi-session work on one repo, use
  [`git worktree`](https://git-scm.com/docs/git-worktree) per pane and
  unique branch prefixes.
- Prompts are sent verbatim. If your prompt has a literal `/`, codex's
  slash-command palette behavior may differ; the double-Enter heuristic
  handles the common case.

---

## License

MIT.
