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
READY_TIMEOUT="${CODEX_SUPERVISOR_READY_TIMEOUT:-180}"
# Default contains an apostrophe -- can't put it inside ${VAR:-...} (the
# apostrophe opens an unbalanced single-quoted region in parameter expansion).
LIMIT_PATTERN="You've hit your usage limit"
[[ -n "${CODEX_SUPERVISOR_LIMIT:-}" ]] && LIMIT_PATTERN="$CODEX_SUPERVISOR_LIMIT"
READY_PATTERN="${CODEX_SUPERVISOR_READY:-Ready · Context}"
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

wait_ready_and_send() {
  local i=$1 prompt=$2 target s
  target=$(pane_target "$i")
  for ((s=1; s<=READY_TIMEOUT; s++)); do
    if tmux capture-pane -t "$target" -p 2>/dev/null | grep -qF "$READY_PATTERN"; then
      log "[pane $i] ready after ${s}s"
      tmux send-keys -t "$target" "$prompt"
      sleep 0.5
      tmux send-keys -t "$target" Enter   # slash-command popup eats this one
      sleep 0.4
      tmux send-keys -t "$target" Enter   # actual submit
      log "[pane $i] sent: $(printf '%.80s' "$prompt")..."
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
  mapfile -t PANE_IDX < <(tmux list-panes -t "$SESSION:0" -F '#{pane_index}')
  if (( ${#PANE_IDX[@]} != ${#PROMPTS[@]} )); then
    log "ERROR: pane count ${#PANE_IDX[@]} != prompt count ${#PROMPTS[@]}"
    exit 1
  fi
  log "tmux session '$SESSION' has ${#PROMPTS[@]} tiled panes (indices: ${PANE_IDX[*]})"
  log "prompts loaded from: $PROMPTS_FILE"

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
