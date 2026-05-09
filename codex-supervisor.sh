#!/usr/bin/env bash
# codex-supervisor.sh -- run multiple codex CLI sessions in parallel tmux panes,
# auto-send a per-pane prompt once each session is ready, and respawn any pane
# whose codex hits the usage limit so the prompt resumes after the reset window.
#
# Architecture: ONE tmux session, ONE window, N tiled panes -- one pane per
# prompt. All panes are visible simultaneously when attached. On startup the
# script auto-opens Terminal.app attached to the session (configurable).
#
# Per pane: launch codex, wait for the ready marker, send the prompt verbatim
# (with a double-Enter so a slash-command popup doesn't eat the submit). A
# poll loop checks each pane every POLL_INTERVAL seconds for the usage-limit
# message; LIMIT_HITS_BEFORE_KILL consecutive hits respawns that pane (fresh
# codex) and resends its prompt. Pane index/layout are preserved across
# respawns via `tmux respawn-pane -k`.
#
# Usage:
#   codex-supervisor.sh [--prompts <file>] [--session <name>] [--no-open]
#
# Prompts file: one prompt per line. Blank lines and lines starting with `#`
# are ignored. Each non-empty line is sent verbatim to its codex pane, so
# include the `/goal ` (or any other slash command) prefix yourself if you
# want it.
#
# Discovery order for the prompts file:
#   1. --prompts <path> CLI flag
#   2. CODEX_SUPERVISOR_PROMPTS env var
#   3. ./codex-prompts.txt in the current directory
#   4. ~/codex-prompts.txt
#
# Environment overrides (all optional):
#   CODEX_SUPERVISOR_PROMPTS       prompts file path
#   CODEX_SUPERVISOR_SESSION       tmux session name (default codex-supervisor)
#   CODEX_SUPERVISOR_CMD           codex command (default `codex --dangerously-bypass-approvals-and-sandbox`)
#   CODEX_SUPERVISOR_POLL          seconds between limit checks (default 30)
#   CODEX_SUPERVISOR_READY_TIMEOUT seconds to wait for Ready (default 180)
#   CODEX_SUPERVISOR_READY         ready marker substring (default `Ready · Context`)
#   CODEX_SUPERVISOR_LIMIT         usage-limit substring (default `You've hit your usage limit`)
#   CODEX_SUPERVISOR_HITS          consecutive limit polls before respawn (default 3)
#   CODEX_SUPERVISOR_LOG           log file path (default ~/codex-supervisor.log)
#   CODEX_SUPERVISOR_OPEN          1 = auto-open Terminal.app, 0 = print attach hint
#
# Stop everything: Ctrl+C in the supervisor terminal (kills tmux session + panes).
# Detach without killing (from inside the attached tmux): Ctrl+b then d.
# Cycle pane focus: Ctrl+b then o.   Zoom one pane fullscreen: Ctrl+b then z.

set -u

SESSION="${CODEX_SUPERVISOR_SESSION:-codex-supervisor}"
CODEX_CMD="${CODEX_SUPERVISOR_CMD:-codex --dangerously-bypass-approvals-and-sandbox}"
POLL_INTERVAL="${CODEX_SUPERVISOR_POLL:-30}"
READY_TIMEOUT="${CODEX_SUPERVISOR_READY_TIMEOUT:-600}"
# Default contains an apostrophe -- can't put it inside ${VAR:-...} (the
# apostrophe opens an unbalanced single-quoted region in parameter expansion).
LIMIT_PATTERN="You've hit your usage limit"
[[ -n "${CODEX_SUPERVISOR_LIMIT:-}" ]] && LIMIT_PATTERN="$CODEX_SUPERVISOR_LIMIT"
# Default `Tip: ` rather than `Ready · Context` -- the latter gets visually
# truncated by codex when a pane is narrower than ~50 columns, so capture-pane
# never sees the full string. `Tip: ` always sits at column 2 of the help line
# that codex prints once it's ready for input.
READY_PATTERN="${CODEX_SUPERVISOR_READY:-Tip: }"
# Substring that must be ABSENT for the pane to be considered ready -- codex
# shows "Starting MCP servers" while MCP plugins are loading, and during that
# window keystrokes can be silently lost.
NOT_READY_PATTERN="${CODEX_SUPERVISOR_NOT_READY:-Starting MCP}"
# After the ready condition is first met, wait this long for the input handler
# to fully attach, then re-verify the ready condition before sending. Codex's
# UI sometimes flips back to "Starting" briefly even after Tip first appears.
READY_SETTLE_SECS="${CODEX_SUPERVISOR_READY_SETTLE:-5}"
LIMIT_HITS_BEFORE_KILL="${CODEX_SUPERVISOR_HITS:-3}"
LOG_FILE="${CODEX_SUPERVISOR_LOG:-$HOME/codex-supervisor.log}"
AUTO_OPEN_TERMINAL="${CODEX_SUPERVISOR_OPEN:-1}"
PROMPTS_FILE="${CODEX_SUPERVISOR_PROMPTS:-}"

usage() {
  sed -n '2,46p' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompts)  PROMPTS_FILE="$2"; shift 2 ;;
    --session)  SESSION="$2"; shift 2 ;;
    --no-open)  AUTO_OPEN_TERMINAL=0; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Discover prompts file if not set explicitly.
if [[ -z "$PROMPTS_FILE" ]]; then
  if   [[ -f "./codex-prompts.txt" ]]; then PROMPTS_FILE="./codex-prompts.txt"
  elif [[ -f "$HOME/codex-prompts.txt" ]]; then PROMPTS_FILE="$HOME/codex-prompts.txt"
  fi
fi

[[ -n "$PROMPTS_FILE" && -f "$PROMPTS_FILE" ]] || {
  echo "prompts file not found." >&2
  echo "use --prompts <file>, set CODEX_SUPERVISOR_PROMPTS, or create ./codex-prompts.txt" >&2
  exit 1
}

# One prompt per non-blank, non-comment line.
declare -a PROMPTS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  PROMPTS+=("$line")
done < "$PROMPTS_FILE"

(( ${#PROMPTS[@]} > 0 )) || { echo "no prompts found in $PROMPTS_FILE" >&2; exit 1; }

# ----------------------------------------------------------------------------
# implementation
# ----------------------------------------------------------------------------

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE" >&2; }

declare -a PANE_IDX=()
declare -A LIMIT_STREAK=()

pane_target() { printf '%s:0.%d' "$SESSION" "${PANE_IDX[$1]}"; }

# Force an even MxN grid so cells are equal (tmux's `tiled` algorithm gives
# the last row extra height when N isn't a perfect square -- e.g. N=8 in a
# 3-col layout leaves 2 cells in the bottom row that get the row's full
# height, making them taller than the 6 cells above).
apply_even_grid() {
  local n=${#PROMPTS[@]} session=$1 cols rows W H
  read W H < <(tmux display-message -p -t "$session:0" '#{window_width} #{window_height}')

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

avail_x = W - (cols - 1)
cw = avail_x // cols
last_w = avail_x - cw * (cols - 1)
avail_y = H - (rows - 1)
ch = avail_y // rows
last_h = avail_y - ch * (rows - 1)

def cell(w, h, x, y, pid):
    return f"{w}x{h},{x},{y},{pid}"

if N == 1:
    body = f"{W}x{H},0,0,{panes[0]}"
elif rows == 1:
    parts = [cell(cw if c < cols - 1 else last_w, H, c * (cw + 1), 0, panes[c]) for c in range(N)]
    body = f"{W}x{H},0,0" + "{" + SEP.join(parts) + "}"
else:
    row_parts = []
    for r in range(rows):
        y = r * (ch + 1)
        rh = ch if r < rows - 1 else last_h
        cells = []
        for c in range(cols):
            idx = r * cols + c
            if idx >= N:
                break
            x = c * (cw + 1)
            cwid = cw if c < cols - 1 else last_w
            cells.append(cell(cwid, rh, x, y, panes[idx]))
        row_parts.append(f"{W}x{rh},0,{y}" + "{" + SEP.join(cells) + "}")
    body = f"{W}x{H},0,0[" + SEP.join(row_parts) + "]"

csum = 0
for c in body.encode():
    csum = ((csum >> 1) | ((csum & 1) << 15)) & 0xFFFF
    csum = (csum + c) & 0xFFFF
print(f"{csum:x},{body}")
') || { log "apply_even_grid: python3 failed, leaving tiled layout in place"; return 1; }

  if tmux select-layout -t "$session:0" "$body" >/dev/null 2>&1; then
    log "applied even ${cols}x${rows} grid for $n panes"
  else
    log "apply_even_grid: select-layout rejected layout, leaving tiled in place"
  fi
}

wait_ready_and_send() {
  local i=$1 prompt=$2 target s cap
  target=$(pane_target "$i")
  # Codex shows the welcome banner (with `Tip: ...`) BEFORE it starts loading
  # MCP servers, and during that pre-MCP window keystrokes can be silently
  # swallowed. Require both: Tip line visible (welcome rendered) AND no
  # "Starting MCP" line (MCP server load complete). Then wait READY_SETTLE_SECS
  # and re-verify before sending -- the input handler attaches a beat after
  # MCP completes, and codex can briefly flip back to a transitional state.
  for ((s=1; s<=READY_TIMEOUT; s++)); do
    cap=$(tmux capture-pane -t "$target" -p 2>/dev/null)
    if printf '%s' "$cap" | grep -qF "$READY_PATTERN" \
       && ! printf '%s' "$cap" | grep -qF "$NOT_READY_PATTERN"; then
      log "[pane $i] ready candidate after ${s}s, settling for ${READY_SETTLE_SECS}s..."
      sleep "$READY_SETTLE_SECS"
      cap=$(tmux capture-pane -t "$target" -p 2>/dev/null)
      if ! printf '%s' "$cap" | grep -qF "$READY_PATTERN" \
         || printf '%s' "$cap" | grep -qF "$NOT_READY_PATTERN"; then
        log "[pane $i] state regressed during settle, re-waiting"
        continue
      fi
      tmux send-keys -t "$target" "$prompt"
      sleep 0.5
      tmux send-keys -t "$target" Enter   # slash-command popup eats this one
      sleep 0.4
      tmux send-keys -t "$target" Enter   # actual submit
      log "[pane $i] sent after settle: $(printf '%.80s' "$prompt")..."
      return 0
    fi
    sleep 1
  done
  log "[pane $i] ERROR: ready timeout (${READY_TIMEOUT}s)"
  return 1
}

check_pane() {
  local i=$1 prompt=$2 target
  target=$(pane_target "$i")
  if tmux capture-pane -t "$target" -p 2>/dev/null | grep -qF "$LIMIT_PATTERN"; then
    LIMIT_STREAK[$i]=$(( ${LIMIT_STREAK[$i]:-0} + 1 ))
    log "[pane $i] limit hit ${LIMIT_STREAK[$i]}/${LIMIT_HITS_BEFORE_KILL}"
    if (( ${LIMIT_STREAK[$i]} >= LIMIT_HITS_BEFORE_KILL )); then
      log "[pane $i] respawning with fresh codex + resending prompt"
      tmux respawn-pane -k -t "$target" "$CODEX_CMD"
      LIMIT_STREAK[$i]=0
      ( wait_ready_and_send "$i" "$prompt" ) &
    fi
  else
    if (( ${LIMIT_STREAK[$i]:-0} > 0 )); then
      log "[pane $i] limit cleared, streak reset"
    fi
    LIMIT_STREAK[$i]=0
  fi
}

cleanup() {
  log "shutting down: killing session '$SESSION'"
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  exit 0
}
trap cleanup INT TERM

main() {
  command -v tmux  >/dev/null || { echo "tmux not on PATH"  >&2; exit 1; }
  # Codex command is checked by attempting to launch; we only check the first word
  # exists on PATH so aliases / flags pass through.
  local first_word; first_word=$(awk '{print $1}' <<<"$CODEX_CMD")
  command -v "$first_word" >/dev/null || { echo "$first_word not on PATH" >&2; exit 1; }

  tmux kill-session -t "$SESSION" 2>/dev/null || true

  # Pane 0 from new-session, then one split per remaining prompt; tile after each.
  tmux new-session -d -s "$SESSION" -x 240 -y 70 "$CODEX_CMD"
  local i
  for ((i=1; i<${#PROMPTS[@]}; i++)); do
    tmux split-window -t "$SESSION:0" "$CODEX_CMD"
    tmux select-layout -t "$SESSION:0" tiled >/dev/null
  done
  tmux select-layout -t "$SESSION:0" tiled >/dev/null

  # Capture actual pane indices in creation order (handles base-index ≠ 0 configs).
  # Avoid `mapfile` -- it's bash 4+; macOS still ships bash 3.2 by default.
  PANE_IDX=()
  while IFS= read -r _idx; do PANE_IDX+=("$_idx"); done \
    < <(tmux list-panes -t "$SESSION:0" -F '#{pane_index}')
  if (( ${#PANE_IDX[@]} != ${#PROMPTS[@]} )); then
    log "ERROR: pane count ${#PANE_IDX[@]} != prompt count ${#PROMPTS[@]}"
    exit 1
  fi
  log "tmux session '$SESSION' has ${#PROMPTS[@]} tiled panes (indices: ${PANE_IDX[*]})"
  log "prompts loaded from: $PROMPTS_FILE"

  # Force exact equal cell sizes (tmux's tiled is uneven for non-perfect-square N).
  apply_even_grid "$SESSION"

  if (( AUTO_OPEN_TERMINAL )) && command -v osascript >/dev/null; then
    osascript -e "tell application \"Terminal\" to do script \"tmux attach -t $SESSION\"" \
              -e 'tell application "Terminal" to activate' >/dev/null 2>&1 \
      && log "opened Terminal.app attached to session" \
      || log "auto-open failed; attach manually: tmux attach -t $SESSION"
  else
    log "auto-open disabled; attach manually: tmux attach -t $SESSION"
  fi

  # Parallel fill: wait-for-ready + send-prompt for every pane concurrently.
  for i in "${!PROMPTS[@]}"; do
    LIMIT_STREAK[$i]=0
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

main "$@"
