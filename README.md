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
# 1. Create a prompts file (one prompt per line). Each line is sent verbatim
#    to its codex pane -- include `/goal ` etc. yourself.
cp codex-prompts.example.txt codex-prompts.txt
$EDITOR codex-prompts.txt

# 2. Start the supervisor.
codex-supervisor start

# (or just `codex-supervisor` -- with no subcommand it runs `start`)
```

A new terminal window opens attached to the tmux session, with one tiled
codex pane per prompt. Each pane runs the `codex` CLI; once it's ready,
the supervisor auto-types the prompt and submits it.

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

Each prompt is ~20 words, one line, no embedded newlines.

Detail lives in `.md` files under your repo:

- `docs/parallel-sessions.md` — **shared protocol** (lanes table,
  per-iteration cycle, branching/merging rules, stop conditions, "when
  to ask" exceptions). Lanes re-read this at the start of every
  iteration so edits flow without re-typing prompts.
- `docs/parallel-sessions/<lane>.md` — **per-lane spec** (branch
  prefix, writable targets, required reading, working rhythm, scope
  guardrails, stop condition).

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
  message format; one PR per iteration; rebase before push; status
  board entry; conflict policy; "when to stop and ask".

What goes in the **per-lane `.md`**:

- Branch prefix and worktree path.
- Writable targets (which files this lane is allowed to touch).
- Goal (one paragraph).
- Working rhythm (numbered iteration cycle).
- Scope guardrails ("don't write a scraper if the spec says no scrapers").
- Required reading.
- Stop condition.

Reference example: <https://github.com/SzeChunYiu/babbloo> demonstrates
this pattern at scale (8 lanes, dedicated + worker pool).

### Anti-pattern: long inline prompts

```
/goal LANE L0. Working directory: /Volumes/MyDrive/.../simulation-L0. Branch: lane/L0. Sole writable target: docs/foo.md. Read CODING_STANDARDS.md and docs/foo.md first. Then for each X under Y/*.cc and each Z under W/*.cc, expand the relevant § with a long list of requirements ... Per-iteration cycle: (a) one X or Z per iteration; (b) edit only the target file; (c) keep every file <= 500 lines; (d) git add, git commit with message "..." and trailers ...; (e) run bash /path/to/merge.sh ...; (f) continue. Stop only when ...
```

This kind of multi-clause prompt fails reliably:

- Backslash-escaping into the TUI input gets out of sync.
- The pane status reads "Press enter to continue" forever.
- Even when delivered, the agent sees the rules only once and forgets
  the merge step on iteration 2.

If you find yourself writing > 30 words in a `/goal`, move detail to a
`.md`.

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
| Wait for ready    | Polls `tmux capture-pane` for `Tip:` AND no `Starting MCP`, then settles 5s and re-verifies before sending. |
| Send prompt       | `tmux send-keys` types the prompt + double Enter (codex's slash-command popup eats the first). |
| Detect limit      | Polls each pane every 60s for `You've hit your usage limit`.              |
| Recover           | After 3 consecutive hits: `tmux respawn-pane -k` + resend prompt. Per-pane 5-min cooldown prevents MCP-reload thrashing. |
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
| `CODEX_SUPERVISOR_POLL`              | `60`                                               |
| `CODEX_SUPERVISOR_READY_TIMEOUT`     | `600`                                              |
| `CODEX_SUPERVISOR_READY`             | `Tip: `                                            |
| `CODEX_SUPERVISOR_NOT_READY`         | `Starting MCP`                                     |
| `CODEX_SUPERVISOR_READY_SETTLE`      | `5`                                                |
| `CODEX_SUPERVISOR_LIMIT`             | `You've hit your usage limit`                      |
| `CODEX_SUPERVISOR_HITS`              | `3`                                                |
| `CODEX_SUPERVISOR_RESPAWN_COOLDOWN`  | `300`                                              |
| `CODEX_SUPERVISOR_CAPTURE_LINES`     | `80`                                               |
| `CODEX_SUPERVISOR_LOG`               | `~/codex-supervisor.log`                           |
| `CODEX_SUPERVISOR_OPEN`              | `1`                                                |
| `CODEX_SUPERVISOR_AUTO_RESEND`       | `1`                                                |
| `CODEX_SUPERVISOR_RESEND_GRACE`      | `30`                                               |
| `CODEX_SUPERVISOR_ON_COMPLETE`       | `queue` (`queue` / `queue-redo` / `redo` / `rest`) |
| `CODEX_SUPERVISOR_RESPAWN_ON_GOAL`   | `1`                                                |
| `CODEX_SUPERVISOR_FORCE_OPEN`        | `0`                                                |

`start` accepts: `--prompts <file>`, `--session <name>`, `--no-attach`.

---

## Prompts file format

```text
# Comments start with #, blank lines ignored.
# One prompt per line; sent verbatim to its codex pane.
# Include `/goal ` (or any other slash command) yourself.
# Lines must NOT contain literal newlines (newlines submit prematurely).

/goal You are PANE 0, lane BUGS. Read docs/parallel-sessions.md and ...
/goal You are PANE 1, lane PERF. Read docs/parallel-sessions.md and ...
```

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
