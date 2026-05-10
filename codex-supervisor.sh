#!/usr/bin/env bash
# codex-supervisor -- run multiple codex CLI sessions in parallel tmux panes.
#
# Single tmux session, single window, N tiled panes -- one pane per prompt.
# Auto-sends each prompt once its pane is ready, respawns panes whose codex
# hits the usage limit, auto-resends prompts when a /goal completes, and
# applies an even MxN grid layout so cells stay equal.
#
# Subcommands:
#   start [--no-attach]       launch the session (default if no subcommand)
#                             refuses if free disk < CODEX_SUPERVISOR_MIN_FREE_GB (default 5)
#   stop                      kill session, reap MCP orphans, prune git worktrees
#   cleanup                   prune worktrees, npm cache, old /private/tmp/claude-501,
#                             Time Machine local snapshots
#   status                    print pane states (lane, state, last activity)
#   attach                    attach (or open a terminal attached) to the session
#   logs [-f]                 show or tail the supervisor log
#   send <pane> <text>        send text to a specific pane (handles /-command popup)
#   restart <pane>            respawn one pane with a fresh codex
#   relayout                  re-apply the equal MxN grid (use after window resize)
#   prompts                   print the resolved prompts file
#   queue                     show queued tasks per lane (count + next preview)
#   help                      this help text
#
# Run without a subcommand to start (legacy behavior).
#
# Pane controls (inside the attached tmux):
#   Mouse:  click pane to focus, drag border to resize, scroll to scroll back.
#   Alt+0 .. Alt+9                jump to pane 0..9
#   Ctrl+b z                      zoom focused pane fullscreen / restore
#   Ctrl+b d                      detach without killing
#   Ctrl+b [   then q             scroll mode in/out
#
# Configuration (all env vars, all overridable):
#   CODEX_SUPERVISOR_PROMPTS         prompts file path
#                                    (auto-discovers ./codex-prompts.txt then ~/codex-prompts.txt)
#   CODEX_SUPERVISOR_SESSION         tmux session name (default: codex-supervisor)
#   CODEX_SUPERVISOR_CMD             codex command (default: codex --dangerously-bypass-approvals-and-sandbox)
#   CODEX_SUPERVISOR_POLL            seconds between health checks (default: 60)
#   CODEX_SUPERVISOR_READY_TIMEOUT   seconds to wait for Ready (default: 600)
#   CODEX_SUPERVISOR_READY           ready-marker substring (default: "Tip: ")
#   CODEX_SUPERVISOR_NOT_READY       must-be-absent substring (default: "Starting MCP")
#   CODEX_SUPERVISOR_READY_SETTLE    seconds to settle after first Ready (default: 5)
#   CODEX_SUPERVISOR_LIMIT           usage-limit substring (default: "You've hit your usage limit")
#   CODEX_SUPERVISOR_HITS            consecutive limit polls before respawn (default: 3)
#   CODEX_SUPERVISOR_RESPAWN_COOLDOWN  per-pane respawn cooldown secs (default: 300)
#   CODEX_SUPERVISOR_CAPTURE_LINES   tail size for capture-pane scans (default: 80)
#   CODEX_SUPERVISOR_LOG             log file path (default: ~/codex-supervisor.log)
#   CODEX_SUPERVISOR_OPEN            1 = auto-open terminal, 0 = print attach hint (default: 1)
#   CODEX_SUPERVISOR_AUTO_RESEND     1 = auto-resend prompt when /goal completes, 0 = stay idle (default: 1)
#   CODEX_SUPERVISOR_RESEND_GRACE    seconds idle after Goal achieved before resend (default: 30)

set -u

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SESSION="${CODEX_SUPERVISOR_SESSION:-codex-supervisor}"
# When DISABLE_MCP=1, prepend `-c mcp_servers={}` to clear the MCP server
# table for these sessions. Each codex instance otherwise spawns one node
# process per configured MCP server (~14-17 typical), which costs ~500MB
# RAM and 60-180s of startup time per pane. Lanes do not need MCP servers
# for git/gh/npm/build work -- those go through codex's built-in shell tool.
# Default OFF: codex's `-c mcp_servers={}` only merges (does not replace),
# so MCP servers still attempt to load and time out instead of being skipped.
# That actually leaves orphaned node processes around. To genuinely disable
# MCPs, edit ~/.codex/config.toml and remove (or set startup_timeout_sec=1
# on) the [mcp_servers.*] blocks you don't want.
DISABLE_MCP="${CODEX_SUPERVISOR_DISABLE_MCP:-0}"
if [[ -n "${CODEX_SUPERVISOR_CMD:-}" ]]; then
  CODEX_CMD="$CODEX_SUPERVISOR_CMD"
elif (( DISABLE_MCP )); then
  CODEX_CMD="codex -c mcp_servers={} --dangerously-bypass-approvals-and-sandbox"
else
  CODEX_CMD="codex --dangerously-bypass-approvals-and-sandbox"
fi
POLL_INTERVAL="${CODEX_SUPERVISOR_POLL:-60}"
READY_TIMEOUT="${CODEX_SUPERVISOR_READY_TIMEOUT:-600}"
READY_PATTERN="${CODEX_SUPERVISOR_READY:-Tip: }"
NOT_READY_PATTERN="${CODEX_SUPERVISOR_NOT_READY:-Starting MCP}"
READY_SETTLE_SECS="${CODEX_SUPERVISOR_READY_SETTLE:-5}"
# Apostrophe-bearing default can't go in ${VAR:-...} form.
LIMIT_PATTERN="You've hit your usage limit"
[[ -n "${CODEX_SUPERVISOR_LIMIT:-}" ]] && LIMIT_PATTERN="$CODEX_SUPERVISOR_LIMIT"
LIMIT_HITS_BEFORE_KILL="${CODEX_SUPERVISOR_HITS:-3}"
RESPAWN_COOLDOWN_SECS="${CODEX_SUPERVISOR_RESPAWN_COOLDOWN:-300}"
CAPTURE_TAIL_LINES="${CODEX_SUPERVISOR_CAPTURE_LINES:-80}"
LOG_FILE="${CODEX_SUPERVISOR_LOG:-$HOME/codex-supervisor.log}"
AUTO_OPEN_TERMINAL="${CODEX_SUPERVISOR_OPEN:-1}"
AUTO_RESEND="${CODEX_SUPERVISOR_AUTO_RESEND:-1}"
RESEND_GRACE_SECS="${CODEX_SUPERVISOR_RESEND_GRACE:-30}"
# What to do when a pane shows "Goal achieved" and stays idle past grace.
#   queue       - pop next line from codex-tasks/<lane>.txt; if empty, rest. (default)
#   queue-redo  - pop next line from queue; if empty, resend original prompt.
#   redo        - always resend the original prompt.
#   rest        - leave the pane idle.
ON_COMPLETE="${CODEX_SUPERVISOR_ON_COMPLETE:-queue}"
# Lane names that are "continuous" — they have no queue file and should
# always re-run their original prompt when goal achieved (instead of
# resting). Space-separated, lowercased. Match is on the lane label
# parsed from the /goal prompt.
CONTINUOUS_LANES="${CODEX_SUPERVISOR_CONTINUOUS_LANES:-bugs optimize}"
# When 1, on "Goal achieved" the supervisor respawns the codex process in
# the pane (kills + restarts) before sending the next task. Gives each
# iteration a fresh codex with no accumulated context/memory and severs
# any worktree the previous iteration was holding open. Trade-off: ~10s
# of MCP boot per iteration.
RESPAWN_ON_GOAL_DONE="${CODEX_SUPERVISOR_RESPAWN_ON_GOAL:-1}"
# How often (seconds) the main poll loop runs an in-flight cleanup
# (worktree prune + tmp sweep). 0 disables.
PERIODIC_CLEANUP_SECS="${CODEX_SUPERVISOR_PERIODIC_CLEANUP_SECS:-300}"
# Worktree age threshold for periodic cleanup (minutes). Codex creates
# fresh worktrees per iteration; abandoning them after ~30 min is safe
# given typical iteration is ≤25 min.
PERIODIC_WORKTREE_AGE_MIN="${CODEX_SUPERVISOR_PERIODIC_WORKTREE_AGE_MIN:-15}"
# Hard cap on a single goal iteration before we forcibly respawn the pane
# to prevent the conversation from growing long enough to need a remote
# compaction step (which can fail under usage-limit and brick the pane).
# 0 disables. Default 90 minutes — long enough for any normal task to
# finish, short enough to bound context growth.
MAX_ITERATION_SECS="${CODEX_SUPERVISOR_MAX_ITERATION_SECS:-5400}"
# Where per-lane task queues live. Auto-discovered: ./codex-tasks/ then ~/codex-tasks/.
TASKS_DIR="${CODEX_SUPERVISOR_TASKS_DIR:-}"
PROMPTS_FILE="${CODEX_SUPERVISOR_PROMPTS:-}"
# Disk-space guard. start refuses below MIN_FREE_GB; warns below WARN_FREE_GB.
# 8 codex panes with their own worktrees + node_modules can blow through ~10 GB
# fast; refusing under 5 GB prevents the disk-full crash mode where the
# supervisor dies mid-spin and orphans MCP children.
MIN_FREE_GB="${CODEX_SUPERVISOR_MIN_FREE_GB:-5}"
WARN_FREE_GB="${CODEX_SUPERVISOR_WARN_FREE_GB:-10}"
# RAM pre-flight. Mac mini has 16 GB; with 8 panes spawning npm/playwright,
# swap fills and tmux gets sniped. Below MIN_FREE_RAM_MB, the poll loop
# runs cleanup and skips respawn for one tick instead of OOM-ing.
MIN_FREE_RAM_MB="${CODEX_SUPERVISOR_MIN_FREE_RAM_MB:-512}"
# Auto-prune worktrees older than this many hours on `cleanup` subcommand.
# -1 disables. Note: PERIODIC_WORKTREE_AGE_MIN (default 30 min) is used by
# the in-loop cleanup; this is the slower-cadence manual `cleanup` knob.
PRUNE_WORKTREE_AGE_HOURS="${CODEX_SUPERVISOR_PRUNE_AGE_HOURS:-1}"
# Codex CLI log directory cap (GB). When ~/.codex/log exceeds this, contents are
# wiped. Observed in the wild: ~/.codex/log grew to 34 GB on a single Mac mini
# running 8 panes for ~24h. Default 2 GB. Set to 0 to disable.
CODEX_LOG_MAX_GB="${CODEX_SUPERVISOR_CODEX_LOG_MAX_GB:-2}"
# Codex CLI sessions retention (days). ~/.codex/sessions accumulates per-task
# JSONL transcripts; default 7 days keeps recent forensics but bounds growth.
# Set to 0 to disable session pruning.
CODEX_SESSIONS_RETAIN_DAYS="${CODEX_SUPERVISOR_CODEX_SESSIONS_RETAIN_DAYS:-7}"
# Supervisor log rotation cap (MB). LOG_FILE is truncated when above this.
SUPERVISOR_LOG_MAX_MB="${CODEX_SUPERVISOR_LOG_MAX_MB:-50}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
    | tee -a "$LOG_FILE" >&2
}

err() { echo "error: $*" >&2; }

# Per-session state file remembers the prompts file path the supervisor was
# started with, so subsequent `status` / `send` / `restart` etc. don't have
# to be invoked from the project dir or with the env var set.
STATE_FILE="${CODEX_SUPERVISOR_STATE_FILE:-$HOME/.codex-supervisor-${SESSION}.state}"

# Discover the prompts file across CLI / env / cwd / state-file / walk-up / home.
resolve_prompts_file() {
  if [[ -n "$PROMPTS_FILE" ]]; then return 0; fi
  if [[ -f "./codex-prompts.txt" ]]; then PROMPTS_FILE="$(pwd)/codex-prompts.txt"; return 0; fi
  # Walk up from cwd looking for codex-prompts.txt.
  local d="$PWD"
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -f "$d/codex-prompts.txt" ]]; then PROMPTS_FILE="$d/codex-prompts.txt"; return 0; fi
    d="${d%/*}"
  done
  # Fall back to the state file the daemon wrote on `start`.
  if [[ -f "$STATE_FILE" ]]; then
    local saved
    saved=$(grep -E '^PROMPTS_FILE=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
    if [[ -n "$saved" && -f "$saved" ]]; then PROMPTS_FILE="$saved"; return 0; fi
  fi
  if [[ -f "$HOME/codex-prompts.txt" ]]; then PROMPTS_FILE="$HOME/codex-prompts.txt"; fi
}

# Persist resolved state so future commands don't need env vars or cwd.
write_state_file() {
  resolve_prompts_file
  resolve_tasks_dir
  {
    echo "PROMPTS_FILE=${PROMPTS_FILE}"
    echo "TASKS_DIR=${TASKS_DIR}"
    echo "STARTED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$STATE_FILE" 2>/dev/null
}

# Load prompts and lane labels from the prompts file.
# Sets PROMPTS array (one prompt per non-blank, non-comment line) and LANE_LABELS
# (best-effort lane name extracted from each prompt for pane border titles).
declare -a PROMPTS=()
declare -a LANE_LABELS=()
load_prompts() {
  resolve_prompts_file
  if [[ -z "$PROMPTS_FILE" || ! -f "$PROMPTS_FILE" ]]; then
    err "prompts file not found"
    err "use --prompts <file>, set CODEX_SUPERVISOR_PROMPTS, or create ./codex-prompts.txt"
    exit 1
  fi
  PROMPTS=(); LANE_LABELS=()
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    PROMPTS+=("$line")
    # Best-effort lane label: prefer "lane FOO" / "lane: FOO" / "[FOO]" / first quoted word
    local label=""
    if   [[ "$line" =~ lane[[:space:]]+([A-Za-z0-9_-]+) ]]; then label="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ \[([^]]+)\] ]]; then label="${BASH_REMATCH[1]}"
    else label="pane$((${#LANE_LABELS[@]}))"
    fi
    LANE_LABELS+=("$label")
  done < "$PROMPTS_FILE"
  if (( ${#PROMPTS[@]} == 0 )); then
    err "no prompts found in $PROMPTS_FILE"; exit 1
  fi
}

# Per-pane state used by `start` / poll loop.
# Plain indexed arrays (bash 3.2-compatible: macOS ships 3.2 by default,
# which lacks `declare -A`). Pane index is integer so indexed arrays suffice.
PANE_IDX=()
LIMIT_STREAK=()
LAST_RESPAWN=()
LAST_GOAL_DONE=()  # epoch seconds when a "Goal achieved" was first seen per pane
ITERATION_STARTED=()  # epoch seconds when current iteration started (after goal-done respawn or after start)

# Bounded pane snapshot -- single capture-pane call, last N lines only.
capture_tail() {
  tmux capture-pane -t "$1" -p 2>/dev/null | tail -n "$CAPTURE_TAIL_LINES"
}

pane_target() { printf '%s:0.%d' "$SESSION" "${PANE_IDX[$1]}"; }

# Resolve a user-supplied pane reference (numeric index or lane label) to
# a tmux pane index. Echoes the index on stdout, returns 0 on success.
resolve_pane() {
  local ref="$1" i
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    for i in "${!PANE_IDX[@]}"; do
      [[ "${PANE_IDX[$i]}" == "$ref" ]] && { echo "$i"; return 0; }
    done
    return 1
  fi
  for i in "${!LANE_LABELS[@]}"; do
    if [[ "${LANE_LABELS[$i],,}" == "${ref,,}" ]]; then echo "$i"; return 0; fi
  done
  return 1
}

# Cross-platform: open the tmux session in a new terminal window.
# Prefers GPU-accelerated terminals (Ghostty / Alacritty / WezTerm / Kitty)
# over the system default -- they handle 8-10 simultaneously-redrawing TUI
# panes far more efficiently than CPU-bound renderers like macOS Terminal.app.
# Override with CODEX_SUPERVISOR_TERMINAL=<one of: ghostty alacritty wezterm kitty terminal iterm2 gnome-terminal konsole xterm>
open_terminal_attached() {
  local cmd="tmux attach -t $SESSION"
  local pref="${CODEX_SUPERVISOR_TERMINAL:-}"
  local sys; sys=$(uname -s)

  # Idempotency: if a client is already attached to the session, don't
  # spawn another window. This prevents window pile-up when callers
  # (recovery loops, wrappers, scripts) invoke `start` or `attach`
  # repeatedly. To force a new window even when one is attached, set
  # CODEX_SUPERVISOR_FORCE_OPEN=1.
  if [[ "${CODEX_SUPERVISOR_FORCE_OPEN:-0}" != "1" ]] \
     && tmux list-clients -t "$SESSION" 2>/dev/null | grep -q .; then
    log "session '$SESSION' already has an attached client; skipping new window"
    return 0
  fi

  # Try a single explicit choice if the user pinned one.
  if [[ -n "$pref" ]]; then
    _open_in_terminal "$pref" "$cmd" && return 0
    log "preferred terminal '$pref' not available; falling back"
  fi

  if [[ "$sys" == "Darwin" ]]; then
    for t in ghostty alacritty wezterm kitty iterm2 terminal; do
      _open_in_terminal "$t" "$cmd" && return 0
    done
  else
    for t in ghostty alacritty wezterm kitty x-terminal-emulator gnome-terminal konsole xfce4-terminal xterm; do
      _open_in_terminal "$t" "$cmd" && return 0
    done
  fi
  return 1
}

# Try to launch one specific terminal app with the given command.
_open_in_terminal() {
  local name="$1" cmd="$2"
  case "$name" in
    ghostty)
      # Ghostty's `-e` runs the command via `/usr/bin/login -flp <user> <argv>`,
      # so multi-word / shell-syntax commands fail. Wrap in `bash -lc`.
      # Even with the wrapper, AppleScript -> Ghostty handoff hits issues
      # in some installs, so we prefer a single-arg shell exec.
      if command -v ghostty >/dev/null 2>&1; then
        ghostty -e bash -lc "$cmd" >/dev/null 2>&1 & return 0
      fi
      [[ -d /Applications/Ghostty.app ]] && {
        # Pass `-e bash -lc <cmd>` as separate argv to Ghostty.
        open -na Ghostty.app --args -e bash -lc "$cmd" >/dev/null 2>&1 && return 0
      }
      return 1
      ;;
    alacritty)
      command -v alacritty >/dev/null 2>&1 && { alacritty -e bash -lc "$cmd" >/dev/null 2>&1 & return 0; }
      [[ -d /Applications/Alacritty.app ]] && { open -na Alacritty.app --args -e "$cmd" >/dev/null 2>&1 && return 0; }
      return 1
      ;;
    wezterm)
      command -v wezterm >/dev/null 2>&1 && { wezterm start -- bash -lc "$cmd" >/dev/null 2>&1 & return 0; }
      [[ -d /Applications/WezTerm.app ]] && { open -na WezTerm.app --args -e bash -lc "$cmd" >/dev/null 2>&1 && return 0; }
      return 1
      ;;
    kitty)
      command -v kitty >/dev/null 2>&1 && { kitty bash -lc "$cmd" >/dev/null 2>&1 & return 0; }
      [[ -d /Applications/kitty.app ]] && { open -na kitty.app --args bash -lc "$cmd" >/dev/null 2>&1 && return 0; }
      return 1
      ;;
    terminal)
      [[ "$(uname -s)" == "Darwin" ]] || return 1
      command -v osascript >/dev/null 2>&1 && {
        osascript \
          -e "tell application \"Terminal\" to do script \"$cmd\"" \
          -e 'tell application "Terminal" to activate' >/dev/null 2>&1 && return 0
      }
      return 1
      ;;
    iterm2|iterm)
      [[ "$(uname -s)" == "Darwin" ]] || return 1
      [[ -d /Applications/iTerm.app ]] && command -v osascript >/dev/null 2>&1 && {
        osascript \
          -e "tell application \"iTerm\" to create window with default profile command \"$cmd\"" \
          -e 'tell application "iTerm" to activate' >/dev/null 2>&1 && return 0
      }
      return 1
      ;;
    gnome-terminal)
      command -v gnome-terminal >/dev/null 2>&1 && { gnome-terminal -- bash -lc "$cmd" >/dev/null 2>&1 & return 0; }
      return 1
      ;;
    konsole)
      command -v konsole >/dev/null 2>&1 && { konsole -e bash -lc "$cmd" >/dev/null 2>&1 & return 0; }
      return 1
      ;;
    xfce4-terminal|xterm|x-terminal-emulator)
      command -v "$name" >/dev/null 2>&1 && { "$name" -e "bash -lc '$cmd'" >/dev/null 2>&1 & return 0; }
      return 1
      ;;
  esac
  return 1
}

# Apply tmux configuration to make the session easy to control.
apply_tmux_config() {
  # Cosmetic + speed
  tmux set-option -t "$SESSION" -g status off >/dev/null 2>&1 || true
  # Keep dead panes visible so we can diagnose why a codex exited (instead
  # of having the pane silently disappear). Press Enter on a dead pane to
  # close it, or use respawn-pane to relaunch.
  tmux set-option -t "$SESSION" -g remain-on-exit on >/dev/null 2>&1 || true
  tmux set-option -t "$SESSION" -g pane-active-border-style 'fg=default' >/dev/null 2>&1 || true
  tmux set-option -t "$SESSION" -g pane-border-status top >/dev/null 2>&1 || true
  # Format: ' [bold]<pane_index> · <pane_title> '. In tmux format strings,
  # `#{...}` is an expansion; `##` is a literal `#`. Earlier this was
  # `##{pane_index}` which rendered the literal text `{pane_index}` instead
  # of the index value.
  tmux set-option -t "$SESSION" -g pane-border-format ' #[bold]#{pane_index} · #{?pane_title,#{pane_title},} ' >/dev/null 2>&1 || true
  tmux set-option -t "$SESSION" -g escape-time 50 >/dev/null 2>&1 || true
  # Mouse: click to focus, drag to resize, scroll to scroll back.
  tmux set-option -t "$SESSION" -g mouse on >/dev/null 2>&1 || true
  # Alt+0..9 jump directly to a pane (no Ctrl+b prefix).
  for n in 0 1 2 3 4 5 6 7 8 9; do
    tmux bind-key -T root "M-$n" select-pane -t ":.$n" 2>/dev/null || true
  done
}

# Build and apply an even MxN grid layout (equal cell sizes). Falls back
# silently to tmux's default `tiled` if python3 is missing or layout is rejected.
apply_even_grid() {
  local n=${#PANE_IDX[@]} cols rows W H
  if (( n == 0 )); then return; fi
  if ! command -v python3 >/dev/null; then
    tmux select-layout -t "$SESSION:0" tiled >/dev/null 2>&1 || true
    return
  fi
  read W H < <(tmux display-message -p -t "$SESSION:0" '#{window_width} #{window_height}')
  case $n in
    1)        cols=1 ;;
    2)        cols=2 ;;
    3|4)      cols=2 ;;
    5|6)      cols=3 ;;
    7|8)      cols=4 ;;
    9)        cols=3 ;;
    10|11|12) cols=4 ;;
    *)        cols=4 ;;
  esac
  rows=$(( (n + cols - 1) / cols ))

  local body
  body=$(LAYOUT_W="$W" LAYOUT_H="$H" LAYOUT_N="$n" LAYOUT_COLS="$cols" \
         LAYOUT_ROWS="$rows" LAYOUT_PANES="${PANE_IDX[*]}" python3 -c '
import os
W, H = int(os.environ["LAYOUT_W"]), int(os.environ["LAYOUT_H"])
N = int(os.environ["LAYOUT_N"])
cols = int(os.environ["LAYOUT_COLS"])
rows = int(os.environ["LAYOUT_ROWS"])
panes = os.environ["LAYOUT_PANES"].split()
SEP = ","
avail_y = H - (rows - 1)
ch = avail_y // rows
last_h = avail_y - ch * (rows - 1)

def cell(w, h, x, y, pid):
    return f"{w}x{h},{x},{y},{pid}"

if N == 1:
    body = f"{W}x{H},0,0,{panes[0]}"
elif rows == 1:
    avail_x = W - (cols - 1)
    cw = avail_x // cols
    last_w = avail_x - cw * (cols - 1)
    parts = [cell(cw if c < cols - 1 else last_w, H, c * (cw + 1), 0, panes[c]) for c in range(N)]
    body = f"{W}x{H},0,0" + "{" + SEP.join(parts) + "}"
else:
    row_parts = []
    for r in range(rows):
        y = r * (ch + 1)
        rh = ch if r < rows - 1 else last_h
        cells_this_row = min(cols, N - r * cols)
        avail_x_row = W - (cells_this_row - 1)
        cw_row = avail_x_row // cells_this_row
        last_w_row = avail_x_row - cw_row * (cells_this_row - 1)
        cells = []
        for c in range(cells_this_row):
            x = c * (cw_row + 1)
            cwid = cw_row if c < cells_this_row - 1 else last_w_row
            cells.append(cell(cwid, rh, x, y, panes[r * cols + c]))
        row_parts.append(f"{W}x{rh},0,{y}" + "{" + SEP.join(cells) + "}")
    body = f"{W}x{H},0,0[" + SEP.join(row_parts) + "]"

csum = 0
for c in body.encode():
    csum = ((csum >> 1) | ((csum & 1) << 15)) & 0xFFFF
    csum = (csum + c) & 0xFFFF
print(f"{csum:x},{body}")
') || { log "apply_even_grid: python3 failed, leaving tiled in place"; tmux select-layout -t "$SESSION:0" tiled >/dev/null 2>&1; return; }

  if tmux select-layout -t "$SESSION:0" "$body" >/dev/null 2>&1; then
    log "applied even ${cols}x${rows} grid for $n panes"
  else
    log "apply_even_grid: select-layout rejected layout, using tiled"
    tmux select-layout -t "$SESSION:0" tiled >/dev/null 2>&1
  fi
}

# Set each pane's border title to its lane label (visible on attached client).
apply_pane_titles() {
  local i
  for i in "${!PANE_IDX[@]}"; do
    tmux select-pane -t "$(pane_target "$i")" -T "${LANE_LABELS[$i]}" >/dev/null 2>&1 || true
  done
}

# Send a prompt to a pane with the codex-aware double-Enter sequence,
# then verify codex actually started processing it. If the input box still
# looks idle (no Working/Pursuing) within ~10s, retry up to 2 more times.
# Returns 0 on confirmed-active, 1 on give-up.
send_prompt_to_pane() {
  local target="$1" prompt="$2" attempt cap
  for attempt in 1 2 3; do
    # Cancel any open popup / partial state. NEVER send C-c -- that exits
    # codex (which kills the pane). Esc closes its slash-command popup.
    tmux send-keys -t "$target" Escape 2>/dev/null
    sleep 0.2
    tmux send-keys -t "$target" "$prompt"
    sleep 0.5
    tmux send-keys -t "$target" Enter   # /-command popup eats this one
    sleep 0.4
    tmux send-keys -t "$target" Enter   # actual submit
    # Verify within ~10s that codex started processing
    local s
    for ((s=1; s<=10; s++)); do
      sleep 1
      cap=$(tmux capture-pane -t "$target" -p 2>/dev/null | tail -n 30)
      if printf '%s' "$cap" | grep -qE "Pursuing goal|Working \(|Goal active"; then
        return 0
      fi
    done
    # No confirmation -- retry (up to 3 attempts total)
  done
  return 1
}

# Wait for a pane to become ready, then send its prompt.
wait_ready_and_send() {
  local i=$1 prompt=$2 target s cap
  target=$(pane_target "$i")
  for ((s=2; s<=READY_TIMEOUT; s+=2)); do
    cap=$(capture_tail "$target")
    if printf '%s' "$cap" | grep -qF "$READY_PATTERN" \
       && ! printf '%s' "$cap" | grep -qF "$NOT_READY_PATTERN"; then
      log "[pane $i ${LANE_LABELS[$i]}] ready candidate after ${s}s, settling for ${READY_SETTLE_SECS}s..."
      sleep "$READY_SETTLE_SECS"
      cap=$(capture_tail "$target")
      if ! printf '%s' "$cap" | grep -qF "$READY_PATTERN" \
         || printf '%s' "$cap" | grep -qF "$NOT_READY_PATTERN"; then
        log "[pane $i ${LANE_LABELS[$i]}] state regressed during settle, re-waiting"
        continue
      fi
      if send_prompt_to_pane "$target" "$prompt"; then
        log "[pane $i ${LANE_LABELS[$i]}] sent + verified active: $(printf '%.60s' "$prompt")..."
      else
        log "[pane $i ${LANE_LABELS[$i]}] sent but UNCONFIRMED (retries exhausted): $(printf '%.60s' "$prompt")..."
      fi
      return 0
    fi
    sleep 2
  done
  log "[pane $i ${LANE_LABELS[$i]}] ERROR: ready timeout (${READY_TIMEOUT}s)"
  return 1
}

# Per-pane health check called by the poll loop.
# Detects: usage-limit hit (with cooldown-bounded respawn) and goal-completion
# (with grace-bounded auto-resend).
check_pane() {
  local i=$1 prompt=$2 target now since_last
  target=$(pane_target "$i")
  local cap; cap=$(capture_tail "$target")
  now=$(date +%s)

  # FAST PATH: codex's compact-task failure (context too long → remote
  # compaction calls the API → API rejects with usage limit). The pane
  # is dead until restarted, and waiting for the 3-strike streak wastes
  # 3 polls (≈3 minutes). Respawn on first sight, subject to the same
  # cooldown so a globally-limited account doesn't thrash.
  if printf '%s' "$cap" | grep -qF "Error running remote compact task"; then
    since_last=$(( now - ${LAST_RESPAWN[$i]:-0} ))
    local fast_cooldown=$RESPAWN_COOLDOWN_SECS
    if printf '%s' "$cap" | grep -qiE "try again at"; then
      fast_cooldown=$((60 * 60))
    fi
    if (( since_last < fast_cooldown )); then
      log "[pane $i ${LANE_LABELS[$i]}] compact-task failure but cooldown active (${since_last}s/${fast_cooldown}s)"
      return
    fi
    log "[pane $i ${LANE_LABELS[$i]}] compact-task failure -- fast respawn + resend prompt"
    tmux respawn-pane -k -t "$target" "$CODEX_CMD"
    LAST_RESPAWN[$i]=$now
    LIMIT_STREAK[$i]=0
    LAST_GOAL_DONE[$i]=0
    ( wait_ready_and_send "$i" "$prompt" ) &
    return
  fi

  # Usage limit handling
  if printf '%s' "$cap" | grep -qF "$LIMIT_PATTERN"; then
    LIMIT_STREAK[$i]=$(( ${LIMIT_STREAK[$i]:-0} + 1 ))
    # Codex prints "try again at <date> <time>" on hard limits. When we see
    # this we use a much longer cooldown (1h) since the limit is account-
    # wide and respawning won't help — it'll just hit the same wall.
    local cooldown=$RESPAWN_COOLDOWN_SECS
    if printf '%s' "$cap" | grep -qiE "try again at"; then
      cooldown=$((60 * 60))
    fi
    log "[pane $i ${LANE_LABELS[$i]}] limit hit ${LIMIT_STREAK[$i]}/${LIMIT_HITS_BEFORE_KILL} (cooldown ${cooldown}s)"
    if (( ${LIMIT_STREAK[$i]} >= LIMIT_HITS_BEFORE_KILL )); then
      since_last=$(( now - ${LAST_RESPAWN[$i]:-0} ))
      if (( since_last < cooldown )); then
        log "[pane $i ${LANE_LABELS[$i]}] cooldown active (${since_last}s/${cooldown}s) -- skipping respawn"
        LIMIT_STREAK[$i]=0
        return
      fi
      log "[pane $i ${LANE_LABELS[$i]}] respawning + resending prompt"
      tmux respawn-pane -k -t "$target" "$CODEX_CMD"
      LAST_RESPAWN[$i]=$now
      LIMIT_STREAK[$i]=0
      LAST_GOAL_DONE[$i]=0
      ITERATION_STARTED[$i]=$now
      ( wait_ready_and_send "$i" "$prompt" ) &
    fi
    return
  fi
  if (( ${LIMIT_STREAK[$i]:-0} > 0 )); then
    log "[pane $i ${LANE_LABELS[$i]}] limit cleared, streak reset"
    LIMIT_STREAK[$i]=0
  fi

  # Goal-completion handling. Modes (ON_COMPLETE):
  #   queue       - pop next from codex-tasks/<lane>.txt; if empty, rest
  #   queue-redo  - pop next from queue; if empty, resend original prompt
  #   redo        - always resend original
  #   rest        - leave idle
  if (( AUTO_RESEND )) && [[ "$ON_COMPLETE" != "rest" ]]; then
    if printf '%s' "$cap" | grep -qiE "Goal (achieved|complete|reached)"; then
      if (( ${LAST_GOAL_DONE[$i]:-0} == 0 )); then
        LAST_GOAL_DONE[$i]=$now
        log "[pane $i ${LANE_LABELS[$i]}] goal achieved; on-complete=$ON_COMPLETE in ${RESEND_GRACE_SECS}s"
      else
        local idle=$(( now - LAST_GOAL_DONE[$i] ))
        if (( idle >= RESEND_GRACE_SECS )); then
          # Reset BEFORE deciding to avoid re-firing if the action takes time
          LAST_GOAL_DONE[$i]=0
          # Skip if pane has gotten busy again in the meantime
          if printf '%s' "$cap" | grep -qF "Working" \
             || printf '%s' "$cap" | grep -qF "Pursuing goal"; then
            return
          fi
          local lane="${LANE_LABELS[$i]}" next_task="" sent_label=""
          # Per-lane override: continuous lanes (bugs, optimize) always redo
          # when queue is empty regardless of global ON_COMPLETE policy.
          local lane_lc effective="$ON_COMPLETE"
          lane_lc=$(printf '%s' "$lane" | tr '[:upper:]' '[:lower:]')
          if [[ " $CONTINUOUS_LANES " == *" $lane_lc "* ]]; then
            effective="queue-redo"
          fi
          case "$effective" in
            queue|queue-redo)
              if next_task=$(pop_next_task "$lane") && [[ -n "$next_task" ]]; then
                sent_label="next from queue"
              elif [[ "$effective" == "queue-redo" ]]; then
                next_task="$prompt"; sent_label="redo (queue empty)"
              fi
              ;;
            redo)
              next_task="$prompt"; sent_label="redo"
              ;;
          esac
          if [[ -n "$next_task" ]]; then
            # RAM pre-flight: if free RAM is below threshold, run cleanup
            # and skip respawn this tick. The pane stays idle (cheap)
            # rather than spawning into OOM and killing the tmux server.
            local _ram; _ram=$(free_ram_mb)
            local _disk; _disk=$(free_gb_on_cwd)
            if (( _ram < MIN_FREE_RAM_MB )); then
              log "[pane $i $lane] low RAM (${_ram}MB < ${MIN_FREE_RAM_MB}MB) — running cleanup, deferring respawn"
              run_periodic_cleanup
              # Reset iteration timer so we don't trip the MAX_ITERATION_SECS cap
              # while we're intentionally deferring.
              ITERATION_STARTED[$i]=$now
            elif (( _disk < MIN_FREE_GB )); then
              # Disk pre-flight: same logic as RAM. Codex respawn writes
              # session JSONL + ~/.codex/log + sometimes spawns worktrees;
              # skipping respawn under disk pressure prevents the cascade.
              log "[pane $i $lane] low disk (${_disk}G < ${MIN_FREE_GB}G) — running cleanup, deferring respawn"
              run_periodic_cleanup
              ITERATION_STARTED[$i]=$now
            elif (( RESPAWN_ON_GOAL_DONE )); then
              log "[pane $i $lane] respawning codex before next task ($sent_label)"
              tmux respawn-pane -k -t "$target" "$CODEX_CMD"
              # Send the next prompt once codex is ready again (background).
              ( wait_ready_and_send "$i" "$next_task" ) &
              ITERATION_STARTED[$i]=$now
            else
              log "[pane $i $lane] sending $sent_label: $(printf '%.60s' "$next_task")..."
              send_prompt_to_pane "$target" "$next_task"
              ITERATION_STARTED[$i]=$now
            fi
          else
            log "[pane $i $lane] resting (no queued task)"
          fi
        fi
      fi
    else
      LAST_GOAL_DONE[$i]=0
    fi
  fi

  # Hard iteration cap. If a pane has been "Working" past MAX_ITERATION_SECS
  # without showing "Goal achieved", forcibly respawn — assume it's stuck
  # in a long compaction/exploration loop. Bounds context growth too,
  # which helps avoid the remote-compact-task usage-limit failure.
  if (( MAX_ITERATION_SECS > 0 )); then
    local started=${ITERATION_STARTED[$i]:-0}
    if (( started > 0 )) && (( now - started >= MAX_ITERATION_SECS )); then
      log "[pane $i ${LANE_LABELS[$i]}] iteration exceeded ${MAX_ITERATION_SECS}s — forcing respawn"
      tmux respawn-pane -k -t "$target" "$CODEX_CMD"
      LAST_RESPAWN[$i]=$now
      LIMIT_STREAK[$i]=0
      LAST_GOAL_DONE[$i]=0
      ITERATION_STARTED[$i]=$now
      ( wait_ready_and_send "$i" "$prompt" ) &
    fi
  fi
}

# Populate PANE_IDX from a running tmux session (used by status / send / restart).
populate_pane_idx_from_running() {
  PANE_IDX=()
  while IFS= read -r _idx; do PANE_IDX+=("$_idx"); done \
    < <(tmux list-panes -t "$SESSION:0" -F '#{pane_index}' 2>/dev/null)
}

resolve_tasks_dir() {
  [[ -n "$TASKS_DIR" ]] && return 0
  if [[ -d "./codex-tasks" ]]; then TASKS_DIR="$(pwd)/codex-tasks"; return 0; fi
  # Walk up from cwd looking for a sibling codex-tasks/ dir.
  local d="$PWD"
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -d "$d/codex-tasks" ]]; then TASKS_DIR="$d/codex-tasks"; return 0; fi
    d="${d%/*}"
  done
  # Fall back to the state file.
  if [[ -f "$STATE_FILE" ]]; then
    local saved
    saved=$(grep -E '^TASKS_DIR=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
    if [[ -n "$saved" && -d "$saved" ]]; then TASKS_DIR="$saved"; return 0; fi
  fi
  # If we have a resolved prompts file, use its sibling codex-tasks/.
  if [[ -n "$PROMPTS_FILE" ]]; then
    local pdir; pdir=$(dirname "$PROMPTS_FILE")
    if [[ -d "$pdir/codex-tasks" ]]; then TASKS_DIR="$pdir/codex-tasks"; return 0; fi
  fi
  if [[ -d "$HOME/codex-tasks" ]]; then TASKS_DIR="$HOME/codex-tasks"; fi
}

# Pop the first non-blank, non-comment line from the lane's queue file and
# echo it to stdout. Removes the line from the file (atomic via tmp+mv).
# Returns 0 if a task was popped, 1 if queue was empty/missing.
pop_next_task() {
  local lane="$1"
  resolve_tasks_dir
  [[ -n "$TASKS_DIR" && -d "$TASKS_DIR" ]] || return 1
  local file="$TASKS_DIR/${lane}.txt"
  [[ -f "$file" ]] || return 1
  # Find first non-blank, non-comment line
  local task line_no=0 found=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    task="$line"
    found=1
    break
  done < "$file"
  (( found )) || return 1
  # Remove that specific line, preserving the rest verbatim
  awk -v ln="$line_no" 'NR != ln' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  printf '%s' "$task"
}

cleanup_session() {
  log "shutting down session '$SESSION'"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  reap_orphan_mcps
  # Also kill any stale supervisor daemons (other than ourselves). Each
  # `start` forks a daemon; without this they accumulate across restarts
  # and fight over the same panes.
  reap_stale_daemons
  # Drop the per-session state file so a fresh `start` can rediscover.
  rm -f "$STATE_FILE" 2>/dev/null
}

# Kill any other codex-supervisor daemon processes for this session,
# excluding the current process tree.
reap_stale_daemons() {
  local self="$$" parent
  parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
  local n=0 killed_pids=()
  for pid in $(pgrep -f "codex-supervisor\.sh" 2>/dev/null); do
    [[ "$pid" == "$self" || "$pid" == "$parent" ]] && continue
    # Match `--session <SESSION>` exactly, not bare $SESSION substring.
    # The script path itself is `codex-supervisor.sh`, so a bare grep for
    # SESSION="codex-supervisor" matches every supervisor process —
    # including ones for OTHER sessions (e.g. nnbar-rebuild). That bug
    # let one project's `start` kill another project's running daemon.
    local cmd; cmd=$(ps -p "$pid" -o command= 2>/dev/null)
    if printf '%s' "$cmd" | grep -qE "[-]-session[[:space:]]+${SESSION}([[:space:]]|\$)"; then
      :
    elif [[ "$SESSION" == "codex-supervisor" ]] \
         && ! printf '%s' "$cmd" | grep -qE "[-]-session"; then
      # Backwards-compat: a daemon launched without --session uses the
      # default "codex-supervisor". Match it only when our own SESSION
      # is also the default (otherwise we'd kill the default-session
      # daemon when running a named session).
      :
    else
      continue
    fi
    # SIGKILL (not TERM) so the dying daemon's trap can't fire
    # cleanup_session and tear down the tmux session that the new
    # daemon is bringing up. We've hit this race repeatedly.
    kill -KILL "$pid" 2>/dev/null && { n=$((n+1)); killed_pids+=("$pid"); }
  done
  if (( n > 0 )); then
    log "reap_stale_daemons: killed $n stale supervisor process(es)"
    # Wait briefly for the OS to reap so any in-flight tmux commands
    # they queued can't ride past us.
    sleep 1
  fi
}

# Kill any orphaned MCP node processes (parent PID == 1 and the command
# matches typical MCP-server invocations). Safe: only orphans are killed.
reap_orphan_mcps() {
  local pids n=0
  pids=$(ps -axo pid,ppid,command \
    | awk '$2==1 && /node.*\b(mcp|context7|figma|notion|playwright|macos-tools|sequential-thinking|memory-mcp|openalex|arxiv|semanticscholar|filesystem-mcp|github-mcp|token-savior)\b/ {print $1}')
  for pid in $pids; do
    kill -TERM "$pid" 2>/dev/null && n=$((n+1))
  done
  # Also npm exec wrappers that linger
  for pid in $(ps -axo pid,ppid,command | awk '$2==1 && /npm exec/ {print $1}'); do
    kill -TERM "$pid" 2>/dev/null && n=$((n+1))
  done
  (( n > 0 )) && log "reap_orphan_mcps: killed $n orphan process(es)"
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_help() {
  sed -n '2,30p' "$0"
}

# Returns free GB on the working volume (rounded down). Cross-platform
# (BSD/macOS df has -k; -PG isn't portable). 0 on parse failure.
free_gb_on_cwd() {
  df -k . 2>/dev/null | awk 'NR==2 { printf "%d\n", $4/1024/1024 }' || echo 0
}

# Free RAM in MB. Pages are 16 KB on Apple Silicon, 4 KB on Intel.
# vm_stat reports "Pages free", "Pages inactive" — both are reclaimable.
# We use free+inactive because macOS aggressively keeps "inactive" cached
# memory that the kernel will return to processes on demand.
free_ram_mb() {
  local pgsz; pgsz=$(vm_stat 2>/dev/null | awk '/page size of/{print $8}')
  [[ -z "$pgsz" ]] && pgsz=16384
  vm_stat 2>/dev/null | awk -v pg="$pgsz" '
    /Pages free/     { f=$3+0 }
    /Pages inactive/ { i=$3+0 }
    END { printf "%d\n", (f+i)*pg/1024/1024 }
  '
}

# Refuse to start when free space is dangerously low. Each codex pane will
# spawn a git worktree + node_modules + its own MCP server tree; we've seen
# 8 panes blow through ~15 GB in an hour. Refusing under MIN_FREE_GB
# prevents the disk-full crash mode that orphans MCP children.
ensure_disk_space() {
  local free; free=$(free_gb_on_cwd)
  if (( free < MIN_FREE_GB )); then
    err "disk too full to start: ${free}G free on $(pwd) (need >= ${MIN_FREE_GB}G)"
    err "free space first; try: $0 cleanup"
    return 1
  fi
  if (( free < WARN_FREE_GB )); then
    log "WARNING: only ${free}G free on $(pwd); consider running: $0 cleanup"
  fi
  return 0
}

# Prune git worktrees not actively in use, plus npm caches, plus old
# Claude Code session tmp dirs. Idempotent. Safe to run while supervisor
# is running (only touches state outside the live tmux session).
cmd_cleanup() {
  local before after freed
  before=$(free_gb_on_cwd)
  log "cleanup: starting ($before G free on $(pwd))"

  # 1) git worktree prune across the current repo. Removes registry
  #    entries whose checkout dirs are gone. Then physically remove
  #    worktrees older than PRUNE_WORKTREE_AGE_HOURS that aren't the
  #    main checkout.
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git worktree prune 2>/dev/null
    if (( PRUNE_WORKTREE_AGE_HOURS >= 0 )); then
      local main_dir; main_dir=$(git rev-parse --show-toplevel)
      git worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print substr($0,10)}' \
        | while read -r wt; do
            [[ -z "$wt" || "$wt" == "$main_dir" ]] && continue
            # find -mmin: minutes since modified. PRUNE_WORKTREE_AGE_HOURS*60
            local age_min=$((PRUNE_WORKTREE_AGE_HOURS * 60))
            if find "$wt" -maxdepth 0 -mmin +"$age_min" 2>/dev/null | grep -q .; then
              log "cleanup: removing stale worktree $wt"
              git worktree remove --force "$wt" 2>/dev/null \
                || rm -rf "$wt"
            fi
          done
      git worktree prune 2>/dev/null
    fi
  fi

  # 2) npm cache. Safe; re-downloads on demand.
  rm -rf "$HOME/.npm/_cacache" 2>/dev/null

  # 3) Old Claude Code session tmp dirs (>24h). The harness writes per-tool
  #    output here; old session UUIDs sit forever otherwise.
  if [[ -d /private/tmp/claude-501 ]]; then
    find /private/tmp/claude-501 -mindepth 2 -maxdepth 2 -type d -mmin +1440 \
      -exec rm -rf {} + 2>/dev/null
  fi

  # 4) Codex worktree leftovers in /private/tmp. Codex creates per-task
  #    worktrees here that aren't always cleaned up. We've seen 60+
  #    accumulate. Skip /private/tmp/<repo>-saved-before by convention
  #    (those are user-saved snapshots).
  find /private/tmp -maxdepth 1 -type d -name '*-*' -mmin +60 2>/dev/null | while read -r wt; do
    case "$(basename "$wt")" in
      *-saved-before|claude-501) continue ;;
    esac
    # Only nuke if it has a .git pointing somewhere (i.e., it's a worktree)
    if [[ -e "$wt/.git" ]]; then
      log "cleanup: removing tmp worktree $wt"
      git -C "$wt" rev-parse --git-common-dir >/dev/null 2>&1 \
        && (cd "$wt/.." 2>/dev/null && git -C "$(git -C "$wt" rev-parse --git-common-dir)/.." worktree remove --force "$wt" 2>/dev/null) \
        || rm -rf "$wt"
    fi
  done

  # 5) Sibling worktree clones at ~/.config/superpowers/worktrees/<repo>/*
  #    that aren't tied to the current project. Each repo dir under there
  #    gets a `git worktree prune` from its main checkout if findable.
  if [[ -d "$HOME/.config/superpowers/worktrees" ]]; then
    find "$HOME/.config/superpowers/worktrees" -mindepth 2 -maxdepth 2 -type d -mmin +1440 2>/dev/null | while read -r wt; do
      log "cleanup: removing stale superpowers worktree $wt"
      rm -rf "$wt"
    done
  fi

  # 6) Sibling per-pane clones in ~/Desktop/projects/<repo>-* that aren't
  #    git worktrees (orphaned codex per-pane copies).
  find "$HOME/Desktop/projects" -mindepth 1 -maxdepth 1 -type d -name '*-*' -mmin +1440 2>/dev/null | while read -r d; do
    # Skip if it's the main repo or a registered worktree
    [[ -e "$d/.git" ]] || continue
    if [[ -d "$d/.git" ]]; then continue; fi   # main checkout has .git/ as dir
    log "cleanup: removing orphan sibling clone $d"
    rm -rf "$d"
  done

  # 7) Build caches inside any project we know about (best-effort, age-gated)
  for cachedir in $(find "$HOME/Desktop/projects" -maxdepth 3 -type d \( -name '.next' -o -name '.turbo' -o -name 'dist' \) -mmin +720 2>/dev/null); do
    rm -rf "$cachedir" 2>/dev/null
  done

  # 8) Homebrew cache + downloads.
  if command -v brew >/dev/null 2>&1; then
    brew cleanup --prune=all >/dev/null 2>&1 || true
  fi

  # 9) Time Machine local snapshots. Often the silent killer on macOS.
  #    Try without sudo first; if it fails the user can rerun by hand.
  if command -v tmutil >/dev/null 2>&1; then
    tmutil deletelocalsnapshots / >/dev/null 2>&1 || true
  fi

  # 10) Codex CLI log directory. THIS IS THE #1 DISK EATER. Observed at 34 GB
  #     on a single Mac mini after ~24h of 8-pane operation. Codex writes
  #     verbose per-turn JSONL here; safe to wipe — codex regenerates as it
  #     runs. We empty the directory but keep the dir itself so codex's
  #     in-flight handle stays valid.
  if [[ -d "$HOME/.codex/log" ]]; then
    local log_kb log_gb
    log_kb=$(du -sk "$HOME/.codex/log" 2>/dev/null | awk '{print $1}')
    log_gb=$(( log_kb / 1024 / 1024 ))
    if (( log_gb >= 1 )); then
      log "cleanup: clearing ~/.codex/log (${log_gb}G)"
      find "$HOME/.codex/log" -mindepth 1 -delete 2>/dev/null
    fi
  fi

  # 11) Codex CLI sessions older than CODEX_SESSIONS_RETAIN_DAYS. Per-task
  #     JSONL transcripts. Default 7 days. Skipped if retention is 0.
  if (( CODEX_SESSIONS_RETAIN_DAYS > 0 )) && [[ -d "$HOME/.codex/sessions" ]]; then
    find "$HOME/.codex/sessions" -type f -mtime +"${CODEX_SESSIONS_RETAIN_DAYS}" \
      -delete 2>/dev/null
  fi

  # 12) Supervisor's own log. Truncate if oversized.
  if [[ -f "$LOG_FILE" ]]; then
    local sv_mb
    sv_mb=$(du -sm "$LOG_FILE" 2>/dev/null | awk '{print $1}')
    if (( sv_mb > SUPERVISOR_LOG_MAX_MB )); then
      log "cleanup: rotating supervisor log (${sv_mb}M -> 0)"
      : > "$LOG_FILE"
    fi
  fi

  # 13) uv cache prune (Python tool venv wheels). Cheap; redownloads on demand.
  command -v uv >/dev/null 2>&1 && uv cache prune --ci >/dev/null 2>&1 || true

  # 14) npm _npx cache. Codex spawns `npx` heavily; npx caches whole node
  #     project trees here. Safe to wipe.
  rm -rf "$HOME/.npm/_npx" 2>/dev/null

  # 15) macOS-specific app caches that codex/playwright/claude write.
  if [[ -d "$HOME/Library/Caches/com.openai.codex" ]]; then
    find "$HOME/Library/Caches/com.openai.codex" -mindepth 1 -delete 2>/dev/null
  fi

  after=$(free_gb_on_cwd)
  freed=$((after - before))
  log "cleanup: done ($after G free on $(pwd); ${freed}G recovered)"
  echo "cleanup: ${after}G free (${freed}G recovered)"
}

cmd_start() {
  local attach_after=1 daemon_mode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-attach) attach_after=0; shift ;;
      --prompts)   PROMPTS_FILE="$2"; shift 2 ;;
      --session)   SESSION="$2"; shift 2 ;;
      --daemon)    daemon_mode=1; shift ;;   # internal: do the actual work
      *) err "start: unknown arg $1"; return 1 ;;
    esac
  done

  # If we're invoked with --daemon, skip the launcher fork and just run.
  if (( daemon_mode )); then
    _start_supervisor_main
    return
  fi

  command -v tmux >/dev/null || { err "tmux not on PATH"; exit 1; }
  local first_word; first_word=$(awk '{print $1}' <<<"$CODEX_CMD")
  command -v "$first_word" >/dev/null || { err "$first_word not on PATH"; exit 1; }

  # Disk-space guard. Each pane is a worktree + node_modules + node MCP tree;
  # a fresh start on a near-full disk has historically crashed the daemon
  # mid-spin and orphaned MCP children. Refuse early instead.
  ensure_disk_space || exit 1

  # Reap any stale daemon processes from prior runs before forking a new one.
  # `stop` doesn't always get called between restarts, and the daemon
  # survives terminal close, so they accumulate.
  reap_stale_daemons

  # Don't double-launch: if a session of this name is already up, just attach.
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    log "session '$SESSION' already running; attaching"
  else
    # Fork ourselves as a background daemon. nohup + &  + disown means the
    # daemon survives even when the launcher window closes. Pass --daemon so
    # the forked invocation skips this branch and runs _start_supervisor_main.
    local fork_args=("start" "--daemon" "--session" "$SESSION")
    [[ -n "$PROMPTS_FILE" ]] && fork_args+=("--prompts" "$PROMPTS_FILE")
    log "forking supervisor daemon..."
    nohup bash "$0" "${fork_args[@]}" >/dev/null 2>&1 &
    disown $!

    # Wait for the daemon to spin the tmux session up.
    local i
    for ((i=0; i<60; i++)); do
      tmux has-session -t "$SESSION" 2>/dev/null && break
      sleep 1
    done
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      err "daemon did not bring up session within 60s; check $LOG_FILE"
      exit 1
    fi
  fi

  if (( ! attach_after )); then
    echo "session '$SESSION' running in background; attach: tmux attach -t $SESSION"
    return 0
  fi

  # Single window: replace this launcher with `tmux attach`. The daemon
  # keeps running independently, so detaching (Ctrl+b d) or closing the
  # window does not stop the supervisor.
  if [[ -t 0 && -t 1 ]]; then
    exec tmux attach -t "$SESSION"
  fi
  # Non-TTY launcher (e.g. invoked from another script): open a terminal.
  if (( AUTO_OPEN_TERMINAL )); then
    open_terminal_attached \
      || echo "attach: tmux attach -t $SESSION"
  else
    echo "attach: tmux attach -t $SESSION"
  fi
}

# The actual supervisor body, run by the daemon child.
_start_supervisor_main() {
  load_prompts
  write_state_file
  trap 'cleanup_session; exit 0' INT TERM

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -x 240 -y 70 "$CODEX_CMD"
  apply_tmux_config

  local i
  for ((i=1; i<${#PROMPTS[@]}; i++)); do
    tmux split-window -t "$SESSION:0" "$CODEX_CMD"
    tmux select-layout -t "$SESSION:0" tiled >/dev/null
  done

  populate_pane_idx_from_running
  if (( ${#PANE_IDX[@]} != ${#PROMPTS[@]} )); then
    log "ERROR: pane count ${#PANE_IDX[@]} != prompt count ${#PROMPTS[@]}"
    exit 1
  fi
  log "session '$SESSION': ${#PROMPTS[@]} panes (lanes: ${LANE_LABELS[*]})"
  log "prompts: $PROMPTS_FILE"

  apply_even_grid
  apply_pane_titles

  for i in "${!PROMPTS[@]}"; do
    LIMIT_STREAK[$i]=0; LAST_RESPAWN[$i]=0; LAST_GOAL_DONE[$i]=0; ITERATION_STARTED[$i]=$(date +%s)
    ( wait_ready_and_send "$i" "${PROMPTS[$i]}" ) &
  done
  wait
  log "all panes prompted; entering poll loop (every ${POLL_INTERVAL}s)"

  local last_periodic_cleanup=$(date +%s)
  while true; do
    sleep "$POLL_INTERVAL"
    # If the tmux session is gone (e.g. user ran `stop`), exit cleanly.
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      log "tmux session disappeared; daemon exiting"
      exit 0
    fi
    for i in "${!PROMPTS[@]}"; do
      check_pane "$i" "${PROMPTS[$i]}"
    done
    # Periodic cleanup: prune worktrees + sweep tmp dirs every
    # PERIODIC_CLEANUP_SECS seconds. Lightweight enough to run from
    # the poll loop; only does no-op work when nothing is stale.
    if (( PERIODIC_CLEANUP_SECS > 0 )); then
      local now_ts; now_ts=$(date +%s)
      if (( now_ts - last_periodic_cleanup >= PERIODIC_CLEANUP_SECS )); then
        last_periodic_cleanup=$now_ts
        run_periodic_cleanup
      fi
    fi
  done
}

cmd_stop() {
  local was_running=0
  tmux has-session -t "$SESSION" 2>/dev/null && was_running=1
  cleanup_session
  # After tearing down the panes, prune the worktrees they created. Each
  # codex pane spawns its own git worktree + node_modules; without this,
  # they pile up across restarts (we hit 11 GB orphaned in one session).
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git worktree prune 2>/dev/null
  fi
  if (( was_running )); then
    echo "stopped session '$SESSION', reaped orphan MCP children, pruned worktrees"
  else
    echo "no session '$SESSION' running; reaped any leftover MCP orphans + pruned worktrees"
  fi
}

# Lightweight in-flight cleanup, called periodically from the poll loop.
# Targets the highest-yield, fastest-to-scan culprits only. Skips brew
# cleanup and Time Machine snapshots (expensive); save those for the
# explicit `cleanup` subcommand.
run_periodic_cleanup() {
  local before after removed=0
  before=$(free_gb_on_cwd)

  # 1) Walk `git worktree list` for every registered worktree (these can
  #    live in /private/tmp, ~/.config/superpowers/worktrees, or anywhere)
  #    and remove any older than PERIODIC_WORKTREE_AGE_MIN minutes that
  #    isn't the main checkout or a "saved-before" snapshot.
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local main_dir; main_dir=$(git rev-parse --show-toplevel)
    git worktree prune 2>/dev/null
    git worktree list --porcelain 2>/dev/null \
      | awk '/^worktree /{print substr($0,10)}' \
      | while read -r wt; do
          [[ -z "$wt" || "$wt" == "$main_dir" ]] && continue
          case "$(basename "$wt")" in *-saved-before) continue ;; esac
          if find "$wt" -maxdepth 0 -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" 2>/dev/null | grep -q .; then
            git worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
            removed=$((removed+1))
          fi
        done
    git worktree prune 2>/dev/null
  fi

  # 2) /private/tmp/<repo>-* dirs that are NOT registered worktrees
  #    (codex sometimes creates plain temp dirs there).
  find /private/tmp -maxdepth 1 -type d -name '*-*' -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" 2>/dev/null | while read -r d; do
    case "$(basename "$d")" in
      *-saved-before|claude-501) continue ;;
    esac
    rm -rf "$d" 2>/dev/null
  done

  # 3) Stale superpowers worktree dirs not registered (mmin +PERIODIC).
  # `~/.config/superpowers/worktrees` may be a symlink to MyDrive — find -L
  # follows symlinks so MyDrive contents get swept just like local would.
  if [[ -e "$HOME/.config/superpowers/worktrees" ]]; then
    find -L "$HOME/.config/superpowers/worktrees" -mindepth 2 -maxdepth 2 -type d -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" \
      -exec rm -rf {} + 2>/dev/null
  fi

  # 3b) Direct MyDrive paths (cleanup external drive too — runner _work
  # caches and worktree dirs accumulate there as well).
  for d in /Volumes/MyDrive/superpowers/worktrees /Volumes/MyDrive/actions-runner-work; do
    [[ -d "$d" ]] || continue
    find "$d" -mindepth 2 -maxdepth 2 -type d -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" \
      -exec rm -rf {} + 2>/dev/null
  done

  # 4) Orphan sibling clones in ~/Desktop/projects/<repo>-*.
  find "$HOME/Desktop/projects" -mindepth 1 -maxdepth 1 -type d -name '*-*' -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" 2>/dev/null | while read -r d; do
    [[ -e "$d/.git" ]] || continue
    [[ -d "$d/.git" ]] && continue   # main checkout
    rm -rf "$d"
  done

  # 5) Kill orphan dev/test processes that lost their parent codex pane.
  #    These pile up across iterations and are the #1 RAM eater. Only kill
  #    procs whose parent is PID 1 (init) — anything still under codex
  #    is in-flight and must not be touched.
  local p ppid kc=0
  for pat in "next-server" "next dev" "chrome-headless-shell" "chrome_crashpad_handler"; do
    while read -r p; do
      [[ -z "$p" ]] && continue
      ppid=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
      [[ "$ppid" == "1" ]] && kill -TERM "$p" 2>/dev/null && kc=$((kc+1))
    done < <(pgrep -f "$pat" 2>/dev/null)
  done
  # npm-exec / npm-cli orphans (parent gone). pgrep -f matches the long
  # node /path/to/npm-cli.js form codex spawns.
  while read -r p; do
    [[ -z "$p" ]] && continue
    ppid=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [[ "$ppid" == "1" ]] && kill -TERM "$p" 2>/dev/null && kc=$((kc+1))
  done < <(pgrep -f "npm-cli.js\|npm exec" 2>/dev/null)
  (( kc > 0 )) && log "periodic cleanup: killed $kc orphan dev/test procs"

  # 6) HIBEAM/babbloo/weather-market scratch dirs in /private/tmp older
  #    than 1 day. These came from physics + research scratchpads and
  #    never get reclaimed otherwise.
  find /private/tmp -maxdepth 1 -type d \
    \( -name 'HIBEAM_*' -o -name 'babbloo-*' -o -name 'wm-*' \) \
    -mtime +1 -exec rm -rf {} + 2>/dev/null

  # 7) uv cache prune (Python tool). 6 GB+ accumulates from agent venvs.
  #    --ci keeps recently used wheels but drops stale ones. Cheap enough
  #    to run every cleanup tick.
  command -v uv >/dev/null 2>&1 && uv cache prune --ci >/dev/null 2>&1 &

  # 8) APFS local snapshots. macOS keeps Time Machine local snapshots
  #    indefinitely when the destination is offline; they hold space
  #    that df shows as "used" but is reclaimable.
  command -v tmutil >/dev/null 2>&1 && \
    tmutil listlocalsnapshots / 2>/dev/null \
      | awk -F. '/com.apple.TimeMachine/{print $NF}' \
      | while read -r s; do
          [[ -z "$s" ]] && continue
          tmutil deletelocalsnapshots "$s" >/dev/null 2>&1 || true
        done

  # 9) Truncate macOS DiagnosticMessages older than 7 days. They grow
  #    silently to hundreds of MB.
  find /private/var/log/DiagnosticMessages -name '*.asl' -mtime +7 \
    -exec rm -f {} + 2>/dev/null

  # 10) Codex CLI log directory — capped at CODEX_LOG_MAX_GB. This is the
  #     single biggest disk eater for long-running supervisor sessions.
  #     Triggered ONLY when oversized; cheap when within bounds (one du call).
  if (( CODEX_LOG_MAX_GB > 0 )) && [[ -d "$HOME/.codex/log" ]]; then
    local log_kb log_gb
    log_kb=$(du -sk "$HOME/.codex/log" 2>/dev/null | awk '{print $1}')
    log_gb=$(( log_kb / 1024 / 1024 ))
    if (( log_gb >= CODEX_LOG_MAX_GB )); then
      log "periodic cleanup: ~/.codex/log at ${log_gb}G > cap ${CODEX_LOG_MAX_GB}G; clearing"
      find "$HOME/.codex/log" -mindepth 1 -delete 2>/dev/null
    fi
  fi

  # 11) Supervisor's own log — truncate if oversized. Cheap stat.
  if [[ -f "$LOG_FILE" ]]; then
    local sv_mb
    sv_mb=$(du -sm "$LOG_FILE" 2>/dev/null | awk '{print $1}')
    if (( sv_mb > SUPERVISOR_LOG_MAX_MB )); then
      log "periodic cleanup: rotating supervisor log (${sv_mb}M)"
      : > "$LOG_FILE"
    fi
  fi

  after=$(free_gb_on_cwd)
  if (( after != before )); then
    log "periodic cleanup: ${before}G -> ${after}G free"
  fi
}

cmd_status() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "no session '$SESSION' running"; return 1
  fi
  load_prompts
  populate_pane_idx_from_running
  resolve_tasks_dir
  # ANSI color helpers; auto-disabled when stdout isn't a TTY or NO_COLOR is set.
  local C_RESET C_RED C_YELLOW C_GREEN C_CYAN C_DIM C_BOLD
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'; C_CYAN=$'\033[36m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  fi
  printf '%s%-5s %-12s %-9s %5s %s%s\n' "$C_BOLD" 'PANE' 'LANE' 'STATE' 'QUEUE' 'TAIL' "$C_RESET"
  printf '%s%-5s %-12s %-9s %5s %s%s\n' "$C_DIM"  '----' '----' '-----' '-----' '----' "$C_RESET"
  local i state tail label cap color queue_count queue_file lane_lc
  for i in "${!PANE_IDX[@]}"; do
    cap=$(capture_tail "$(pane_target "$i")")
    label="${LANE_LABELS[$i]:-pane$i}"
    state="?"; color="$C_DIM"
    if   printf '%s' "$cap" | grep -qF "$LIMIT_PATTERN"; then state="LIMITED";  color="$C_RED"
    elif printf '%s' "$cap" | grep -qF "Starting MCP"; then  state="STARTING"; color="$C_CYAN"
    elif printf '%s' "$cap" | grep -qiE "Goal (achieved|complete|reached)"; then state="DONE"; color="$C_YELLOW"
    elif printf '%s' "$cap" | grep -qF "Pursuing goal"; then state="WORKING";  color="$C_GREEN"
    elif printf '%s' "$cap" | grep -qF "Working"; then       state="WORKING";  color="$C_GREEN"
    elif printf '%s' "$cap" | grep -qF "$READY_PATTERN"; then state="READY";    color="$C_CYAN"
    elif printf '%s' "$cap" | grep -qE "gpt-[0-9]"; then     state="READY";    color="$C_CYAN"
    fi
    # Queue depth: count uncommented /goal lines in the lane queue file (if any).
    queue_count="-"
    lane_lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    if [[ -n "$TASKS_DIR" ]]; then
      queue_file="$TASKS_DIR/${lane_lc}.txt"
      if [[ -f "$queue_file" ]]; then
        queue_count=$(grep -cE '^/goal' "$queue_file" 2>/dev/null); queue_count=${queue_count:-0}
      fi
    fi
    tail=$(printf '%s' "$cap" | grep -v '^$' | tail -1 | tr -s ' \t' ' ' | head -c 60)
    printf '%-5s %-12s %s%-9s%s %5s %s\n' \
      "${PANE_IDX[$i]}" "$label" "$color" "$state" "$C_RESET" "$queue_count" "$tail"
  done
  # Footer: a one-line summary so you don't have to count states by eye.
  local total=${#PANE_IDX[@]}
  echo
  printf '%s%d panes · session %s · prompts %s%s\n' "$C_DIM" "$total" "$SESSION" "${PROMPTS_FILE:-?}" "$C_RESET"
}

# Peek at queued tasks per lane without consuming them.
cmd_queue() {
  load_prompts
  resolve_tasks_dir
  if [[ -z "$TASKS_DIR" || ! -d "$TASKS_DIR" ]]; then
    echo "no tasks dir found (looked for ./codex-tasks then ~/codex-tasks)"; return 1
  fi
  local C_DIM C_BOLD C_RESET
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
  fi
  printf '%s%-15s %5s  %s%s\n' "$C_BOLD" 'QUEUE FILE' 'COUNT' 'NEXT TASK PREVIEW' "$C_RESET"
  printf '%s%-15s %5s  %s%s\n' "$C_DIM"  '----------' '-----' '-----------------' "$C_RESET"
  local f base count next
  for f in "$TASKS_DIR"/*.txt; do
    [[ -e "$f" ]] || continue
    base=$(basename "$f")
    count=$(grep -cE '^/goal' "$f" 2>/dev/null); count=${count:-0}
    next=$(grep -E '^/goal' "$f" 2>/dev/null | head -1 | head -c 80)
    printf '%-15s %5d  %s\n' "$base" "$count" "${next:-(empty)}"
  done
}

cmd_attach() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    err "no session '$SESSION' running"; return 1
  fi
  if [[ -t 0 && -t 1 ]]; then
    exec tmux attach -t "$SESSION"
  fi
  if open_terminal_attached; then
    echo "opened a new terminal attached to '$SESSION'"
  else
    echo "no TTY and no auto-open available; run: tmux attach -t $SESSION"
  fi
}

cmd_logs() {
  local follow=0
  [[ "${1:-}" == "-f" ]] && follow=1
  [[ -f "$LOG_FILE" ]] || { echo "log not found: $LOG_FILE"; return 1; }
  if (( follow )); then tail -f "$LOG_FILE"; else cat "$LOG_FILE"; fi
}

cmd_send() {
  if (( $# < 2 )); then err "usage: send <pane|lane> <text>"; return 1; fi
  local ref="$1"; shift
  local text="$*"
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    err "no session '$SESSION' running"; return 1
  fi
  load_prompts
  populate_pane_idx_from_running
  local idx; idx=$(resolve_pane "$ref") || { err "no pane matches '$ref'"; return 1; }
  send_prompt_to_pane "$(pane_target "$idx")" "$text"
  echo "sent to pane ${PANE_IDX[$idx]} (${LANE_LABELS[$idx]:-?}): $(printf '%.60s' "$text")..."
}

cmd_restart() {
  if (( $# < 1 )); then err "usage: restart <pane|lane>"; return 1; fi
  local ref="$1"
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    err "no session '$SESSION' running"; return 1
  fi
  load_prompts
  populate_pane_idx_from_running
  local idx; idx=$(resolve_pane "$ref") || { err "no pane matches '$ref'"; return 1; }
  log "[pane ${PANE_IDX[$idx]} ${LANE_LABELS[$idx]:-?}] manual restart"
  tmux respawn-pane -k -t "$(pane_target "$idx")" "$CODEX_CMD"
  ( wait_ready_and_send "$idx" "${PROMPTS[$idx]}" ) &
  echo "restarted pane ${PANE_IDX[$idx]}; prompt will be re-sent when ready"
}

cmd_relayout() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    err "no session '$SESSION' running"; return 1
  fi
  load_prompts
  populate_pane_idx_from_running
  apply_even_grid
  apply_pane_titles
  echo "re-applied layout"
}

cmd_prompts() {
  resolve_prompts_file
  if [[ -z "$PROMPTS_FILE" || ! -f "$PROMPTS_FILE" ]]; then
    err "no prompts file resolved"; return 1
  fi
  echo "# $PROMPTS_FILE"
  cat "$PROMPTS_FILE"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if (( $# == 0 )); then
  cmd_start; exit $?
fi

case "$1" in
  start)    shift; cmd_start "$@" ;;
  stop)     shift; cmd_stop  "$@" ;;
  status)   shift; cmd_status "$@" ;;
  attach)   shift; cmd_attach "$@" ;;
  logs)     shift; cmd_logs "$@" ;;
  send)     shift; cmd_send "$@" ;;
  restart)  shift; cmd_restart "$@" ;;
  relayout) shift; cmd_relayout ;;
  prompts)  shift; cmd_prompts ;;
  cleanup)  shift; cmd_cleanup ;;
  queue|q)  shift; cmd_queue ;;
  -h|--help|help) cmd_help ;;
  # Backwards-compat: legacy flags went straight to start
  --prompts|--session|--no-open|--no-attach) cmd_start "$@" ;;
  *) err "unknown subcommand: $1"; cmd_help; exit 1 ;;
esac
