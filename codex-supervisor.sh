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
#   stop                      kill the session and all panes
#   status                    print pane states (lane, state, last activity)
#   attach                    attach (or open a terminal attached) to the session
#   logs [-f]                 show or tail the supervisor log
#   send <pane> <text>        send text to a specific pane (handles /-command popup)
#   restart <pane>            respawn one pane with a fresh codex
#   relayout                  re-apply the equal MxN grid (use after window resize)
#   prompts                   print the resolved prompts file
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
CODEX_CMD="${CODEX_SUPERVISOR_CMD:-codex --dangerously-bypass-approvals-and-sandbox}"
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
PROMPTS_FILE="${CODEX_SUPERVISOR_PROMPTS:-}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
    | tee -a "$LOG_FILE" >&2
}

err() { echo "error: $*" >&2; }

# Discover the prompts file across CLI / env / cwd / home.
resolve_prompts_file() {
  if [[ -n "$PROMPTS_FILE" ]]; then return 0; fi
  if   [[ -f "./codex-prompts.txt" ]]; then PROMPTS_FILE="./codex-prompts.txt"
  elif [[ -f "$HOME/codex-prompts.txt" ]]; then PROMPTS_FILE="$HOME/codex-prompts.txt"
  fi
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
open_terminal_attached() {
  local cmd="tmux attach -t $SESSION"
  case "$(uname -s)" in
    Darwin)
      if command -v osascript >/dev/null 2>&1; then
        osascript \
          -e "tell application \"Terminal\" to do script \"$cmd\"" \
          -e 'tell application "Terminal" to activate' >/dev/null 2>&1 \
          && return 0
      fi
      ;;
    Linux)
      for term in x-terminal-emulator gnome-terminal konsole xfce4-terminal alacritty kitty wezterm xterm; do
        if command -v "$term" >/dev/null 2>&1; then
          case "$term" in
            gnome-terminal) "$term" -- bash -lc "$cmd" >/dev/null 2>&1 & return 0 ;;
            konsole)        "$term" -e bash -lc "$cmd" >/dev/null 2>&1 & return 0 ;;
            *)              "$term" -e "bash -lc '$cmd'" >/dev/null 2>&1 & return 0 ;;
          esac
        fi
      done
      ;;
  esac
  return 1
}

# Apply tmux configuration to make the session easy to control.
apply_tmux_config() {
  # Cosmetic + speed
  tmux set-option -t "$SESSION" -g status off >/dev/null 2>&1 || true
  tmux set-option -t "$SESSION" -g pane-active-border-style 'fg=default' >/dev/null 2>&1 || true
  tmux set-option -t "$SESSION" -g pane-border-status top >/dev/null 2>&1 || true
  tmux set-option -t "$SESSION" -g pane-border-format ' #[bold]##{pane_index} #{?pane_title,#{pane_title},} ' >/dev/null 2>&1 || true
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

# Send a prompt to a pane with the codex-aware double-Enter sequence.
send_prompt_to_pane() {
  local target="$1" prompt="$2"
  tmux send-keys -t "$target" "$prompt"
  sleep 0.5
  tmux send-keys -t "$target" Enter   # /-command popup eats this one
  sleep 0.4
  tmux send-keys -t "$target" Enter   # actual submit
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
      send_prompt_to_pane "$target" "$prompt"
      log "[pane $i ${LANE_LABELS[$i]}] sent: $(printf '%.80s' "$prompt")..."
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

  # Usage limit handling
  if printf '%s' "$cap" | grep -qF "$LIMIT_PATTERN"; then
    LIMIT_STREAK[$i]=$(( ${LIMIT_STREAK[$i]:-0} + 1 ))
    log "[pane $i ${LANE_LABELS[$i]}] limit hit ${LIMIT_STREAK[$i]}/${LIMIT_HITS_BEFORE_KILL}"
    if (( ${LIMIT_STREAK[$i]} >= LIMIT_HITS_BEFORE_KILL )); then
      since_last=$(( now - ${LAST_RESPAWN[$i]:-0} ))
      if (( since_last < RESPAWN_COOLDOWN_SECS )); then
        log "[pane $i ${LANE_LABELS[$i]}] cooldown active (${since_last}s/${RESPAWN_COOLDOWN_SECS}s) -- skipping respawn"
        LIMIT_STREAK[$i]=0
        return
      fi
      log "[pane $i ${LANE_LABELS[$i]}] respawning + resending prompt"
      tmux respawn-pane -k -t "$target" "$CODEX_CMD"
      LAST_RESPAWN[$i]=$now
      LIMIT_STREAK[$i]=0
      LAST_GOAL_DONE[$i]=0
      ( wait_ready_and_send "$i" "$prompt" ) &
    fi
    return
  fi
  if (( ${LIMIT_STREAK[$i]:-0} > 0 )); then
    log "[pane $i ${LANE_LABELS[$i]}] limit cleared, streak reset"
    LIMIT_STREAK[$i]=0
  fi

  # Goal-completion auto-resend
  if (( AUTO_RESEND )); then
    if printf '%s' "$cap" | grep -qiE "Goal (achieved|complete|reached)"; then
      # First time we see it, mark; on later check, if still idle past grace, resend.
      if (( ${LAST_GOAL_DONE[$i]:-0} == 0 )); then
        LAST_GOAL_DONE[$i]=$now
        log "[pane $i ${LANE_LABELS[$i]}] goal achieved; auto-resend in ${RESEND_GRACE_SECS}s if still idle"
      else
        local idle=$(( now - LAST_GOAL_DONE[$i] ))
        if (( idle >= RESEND_GRACE_SECS )); then
          # Confirm not actively working before resending
          if ! printf '%s' "$cap" | grep -qF "Working" \
             && ! printf '%s' "$cap" | grep -qF "Pursuing goal"; then
            log "[pane $i ${LANE_LABELS[$i]}] auto-resending prompt for next iteration"
            send_prompt_to_pane "$target" "$prompt"
            LAST_GOAL_DONE[$i]=0
          else
            LAST_GOAL_DONE[$i]=0  # actually working again, reset
          fi
        fi
      fi
    else
      LAST_GOAL_DONE[$i]=0
    fi
  fi
}

# Populate PANE_IDX from a running tmux session (used by status / send / restart).
populate_pane_idx_from_running() {
  PANE_IDX=()
  while IFS= read -r _idx; do PANE_IDX+=("$_idx"); done \
    < <(tmux list-panes -t "$SESSION:0" -F '#{pane_index}' 2>/dev/null)
}

cleanup_session() {
  log "shutting down session '$SESSION'"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_help() {
  sed -n '2,30p' "$0"
}

cmd_start() {
  local attach_after=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-attach) attach_after=0; shift ;;
      --prompts)   PROMPTS_FILE="$2"; shift 2 ;;
      --session)   SESSION="$2"; shift 2 ;;
      *) err "start: unknown arg $1"; return 1 ;;
    esac
  done

  command -v tmux  >/dev/null || { err "tmux not on PATH";  exit 1; }
  local first_word; first_word=$(awk '{print $1}' <<<"$CODEX_CMD")
  command -v "$first_word" >/dev/null || { err "$first_word not on PATH"; exit 1; }

  load_prompts
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

  if (( attach_after && AUTO_OPEN_TERMINAL )); then
    if open_terminal_attached; then
      log "opened terminal attached to '$SESSION'"
    else
      log "auto-open unavailable; attach manually: tmux attach -t $SESSION"
    fi
  else
    log "attach manually: tmux attach -t $SESSION"
  fi

  for i in "${!PROMPTS[@]}"; do
    LIMIT_STREAK[$i]=0; LAST_RESPAWN[$i]=0; LAST_GOAL_DONE[$i]=0
    ( wait_ready_and_send "$i" "${PROMPTS[$i]}" ) &
  done
  wait
  log "all panes prompted; entering poll loop (every ${POLL_INTERVAL}s)"

  while true; do
    sleep "$POLL_INTERVAL"
    for i in "${!PROMPTS[@]}"; do
      check_pane "$i" "${PROMPTS[$i]}"
    done
  done
}

cmd_stop() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "no session '$SESSION' running"; return 0
  fi
  cleanup_session
  echo "stopped session '$SESSION'"
}

cmd_status() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "no session '$SESSION' running"; return 1
  fi
  load_prompts
  populate_pane_idx_from_running
  printf '%-5s %-12s %-12s %s\n' 'PANE' 'LANE' 'STATE' 'TAIL'
  printf '%-5s %-12s %-12s %s\n' '----' '----' '-----' '----'
  local i state tail label cap
  for i in "${!PANE_IDX[@]}"; do
    cap=$(capture_tail "$(pane_target "$i")")
    label="${LANE_LABELS[$i]:-pane$i}"
    state="?"
    if   printf '%s' "$cap" | grep -qF "$LIMIT_PATTERN"; then state="LIMITED"
    elif printf '%s' "$cap" | grep -qF "Starting MCP"; then state="STARTING"
    elif printf '%s' "$cap" | grep -qiE "Goal (achieved|complete|reached)"; then state="DONE"
    elif printf '%s' "$cap" | grep -qF "Pursuing goal"; then state="WORKING"
    elif printf '%s' "$cap" | grep -qF "Working"; then state="WORKING"
    elif printf '%s' "$cap" | grep -qF "$READY_PATTERN"; then state="READY"
    fi
    tail=$(printf '%s' "$cap" | grep -v '^$' | tail -1 | tr -s ' \t' ' ' | head -c 60)
    printf '%-5s %-12s %-12s %s\n' "${PANE_IDX[$i]}" "$label" "$state" "$tail"
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
  -h|--help|help) cmd_help ;;
  # Backwards-compat: legacy flags went straight to start
  --prompts|--session|--no-open|--no-attach) cmd_start "$@" ;;
  *) err "unknown subcommand: $1"; cmd_help; exit 1 ;;
esac
