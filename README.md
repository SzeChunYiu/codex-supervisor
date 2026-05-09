# codex-supervisor

Run multiple [codex](https://github.com/openai/codex) CLI sessions in parallel
tmux panes, auto-send a per-pane prompt once each session is ready, and respawn
any pane whose codex hits the usage limit so the prompt resumes after the reset
window.

All panes live in **one tmux session, one window, tiled** — every codex is
visible at once. Auto-opens Terminal.app attached to the session on launch
(macOS).

---

## Install

Anywhere on `$PATH`, or just run from the repo:

```sh
# Optional: symlink to ~ for convenience
ln -sf "$(pwd)/codex-supervisor.sh" ~/codex-supervisor.sh
```

Requirements:

- `tmux` (`brew install tmux`)
- `codex` CLI on `$PATH`
- macOS for the auto-open Terminal.app convenience (optional — falls back to a
  printed `tmux attach` hint on other platforms or with `--no-open`)

---

## Usage

```sh
# 1. Create a prompts file (one prompt per line, # comments and blank lines
#    ignored). Each line is sent verbatim — include `/goal ` etc. yourself.
cp codex-prompts.example.txt codex-prompts.txt
$EDITOR codex-prompts.txt

# 2. Run from the directory containing codex-prompts.txt:
./codex-supervisor.sh

# Or point at any prompts file:
./codex-supervisor.sh --prompts /path/to/prompts.txt

# Don't auto-open Terminal.app:
./codex-supervisor.sh --no-open

# Stop everything: Ctrl+C in the supervisor terminal.
```

### Inside the attached tmux session

| Keys              | Action                                  |
| ----------------- | --------------------------------------- |
| `Ctrl+b` then `o` | cycle pane focus                        |
| `Ctrl+b` then `z` | zoom focused pane fullscreen / restore  |
| `Ctrl+b` then `d` | detach (panes keep running)             |
| `Ctrl+b` then `[` | scroll mode (`q` to exit)               |

Reattach later: `tmux attach -t codex-supervisor`.

---

## How it works

| Step              | Mechanism                                                                 |
| ----------------- | ------------------------------------------------------------------------- |
| Launch            | `tmux new-session` + N-1 `tmux split-window`, then `select-layout tiled`. |
| Wait for ready    | Polls `tmux capture-pane` for the substring `Ready · Context`.            |
| Send prompt       | `tmux send-keys` types the prompt + double Enter (slash-popup eats one).  |
| Detect limit      | Polls each pane every 30 s for `You've hit your usage limit`.             |
| Recover           | After 3 consecutive hits: `tmux respawn-pane -k` + resend prompt.         |

Layout and pane indices stay stable across respawns, so each pane keeps its
slot and its prompt.

---

## Configuration

Everything is overridable via env or CLI without editing the script:

| Env var                            | Default                                            |
| ---------------------------------- | -------------------------------------------------- |
| `CODEX_SUPERVISOR_PROMPTS`         | `./codex-prompts.txt` then `~/codex-prompts.txt`   |
| `CODEX_SUPERVISOR_SESSION`         | `codex-supervisor`                                 |
| `CODEX_SUPERVISOR_CMD`             | `codex --dangerously-bypass-approvals-and-sandbox` |
| `CODEX_SUPERVISOR_POLL`            | `30`                                               |
| `CODEX_SUPERVISOR_READY_TIMEOUT`   | `180`                                              |
| `CODEX_SUPERVISOR_READY`           | `Ready · Context`                                  |
| `CODEX_SUPERVISOR_LIMIT`           | `You've hit your usage limit`                      |
| `CODEX_SUPERVISOR_HITS`            | `3`                                                |
| `CODEX_SUPERVISOR_LOG`             | `~/codex-supervisor.log`                           |
| `CODEX_SUPERVISOR_OPEN`            | `1` (set `0` to disable Terminal.app auto-open)    |

CLI: `--prompts <file>`, `--session <name>`, `--no-open`.

---

## Prompts file format

```text
# Comments start with #, blank lines ignored.
# One prompt per line; sent verbatim to its codex pane.

/goal Recursively find bugs and fix them...
/goal Optimize hot paths for speed...
```

Each non-empty, non-comment line spawns one tiled pane. **Line count =
pane count.** Lines must not contain literal newlines (newlines submit
prematurely to codex).

---

## Caveats

- The codex usage-limit message is account-wide. Respawning gives you a fresh
  client, but the same account hits the same limit again until the reset time
  printed in the message. The script will re-fire on each respawn — that's by
  design (so you resume the moment the window opens).
- Concurrent codex sessions writing to the same git checkout will collide
  (`index.lock`). For multi-session work on one repo, use unique branch
  prefixes per pane and serialize merges, or run each pane in its own
  `git worktree`.
- Prompts are sent verbatim. If codex's slash-command palette intercepts a
  character or your prompt has a literal `/`, behavior may differ.

---

## License

MIT.
