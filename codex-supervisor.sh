#!/usr/bin/env bash
# codex-supervisor -- run multiple codex CLI sessions in parallel tmux panes.
#
# Single tmux session, single window, N tiled panes -- one pane per prompt
# plus one generated PLANNER lane by default. Auto-sends each prompt once its
# pane is ready, respawns panes whose codex exits or hits the usage limit,
# recreates a missing tmux session after resource checks, auto-resends prompts
# when a /goal completes, and applies an even MxN grid layout so cells stay
# equal.
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
#   validate-prompts          check prompt contract without starting panes
#   queue                     show queued tasks per lane (count + next preview)
#   help                      this help text
#
# Run without a subcommand to start (legacy behavior).
# `start` also makes sure the unified csup dashboard is running so all
# supervisor sessions are visible at http://127.0.0.1:7777 with low delay.
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
#   CODEX_SUPERVISOR_ROOT            runtime/cache root (default: /Volumes/MyDrive/codex-supervisor if mounted)
#   CODEX_SUPERVISOR_MCP_MODE        off = use MCP-free CODEX_HOME, inherit = use normal Codex MCPs (default: off)
#   CODEX_SUPERVISOR_CODEX_HOME      MCP-free runtime CODEX_HOME path
#   CODEX_SUPERVISOR_CACHE_ROOT      per-session worker cache root
#   CODEX_SUPERVISOR_TMP_ROOT        per-session worker temp root
#   CODEX_SUPERVISOR_CODEX_HOME_PROFILE lean = omit skills/memories/plugins, full = link them (default: lean)
#   CODEX_SUPERVISOR_NICE            worker CPU priority niceness; 0 disables (default: 5)
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
#   CODEX_SUPERVISOR_PLANNER         1 = append a generated PLANNER lane if missing (default: 1)
#   CODEX_SUPERVISOR_PLANNER_DOC     planner markdown path
#   CODEX_SUPERVISOR_LANES           comma/space-separated lane allowlist for right-sized starts
#   CODEX_SUPERVISOR_RESPAWN_DEAD_PANES 1 = respawn exited codex panes (default: 1)
#   CODEX_SUPERVISOR_AUTO_RECREATE_SESSION 1 = rebuild a vanished tmux session (default: 1)
#   CODEX_SUPERVISOR_MAX_PANES       hard cap on final prompts/panes per session incl. planner (default: 8)
#   CODEX_SUPERVISOR_RAM_MB_PER_PANE projected RAM budget per pane for start preflight (default: 600)
#   CODEX_SUPERVISOR_DISK_MB_PER_PANE projected disk budget per pane for start preflight (default: 1024)
#   CODEX_SUPERVISOR_START_STAGGER_SECS startup delay between pane spawns/prompts; unset = auto

set -u

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SESSION="${CODEX_SUPERVISOR_SESSION:-codex-supervisor}"
DEFAULT_SUPERVISOR_ROOT="$HOME/.codex-supervisor"
[[ -d "/Volumes/MyDrive" ]] && DEFAULT_SUPERVISOR_ROOT="/Volumes/MyDrive/codex-supervisor"
SUPERVISOR_ROOT="${CODEX_SUPERVISOR_ROOT:-$DEFAULT_SUPERVISOR_ROOT}"
# Supervisor panes are MCP-free by default. `codex -c mcp_servers={}` only
# merges config and does not clear already configured servers, so the reliable
# startup fix is an isolated CODEX_HOME with the user's config copied minus
# [mcp_servers.*] sections. Set CODEX_SUPERVISOR_MCP_MODE=inherit if a lane
# explicitly needs MCP servers.
MCP_MODE="${CODEX_SUPERVISOR_MCP_MODE:-off}"
case "${CODEX_SUPERVISOR_DISABLE_MCP:-}" in
  1|true|TRUE|yes|YES|on|ON) MCP_MODE="off" ;;
  0|false|FALSE|no|NO|off|OFF) MCP_MODE="inherit" ;;
esac
CODEX_BASE_CMD="${CODEX_SUPERVISOR_CMD:-codex --dangerously-bypass-approvals-and-sandbox}"
SUPERVISOR_CODEX_HOME="${CODEX_SUPERVISOR_CODEX_HOME:-$SUPERVISOR_ROOT/codex-home/${SESSION}}"
SUPERVISOR_CODEX_HOME_EXPLICIT="${CODEX_SUPERVISOR_CODEX_HOME+x}"
SUPERVISOR_CACHE_ROOT="${CODEX_SUPERVISOR_CACHE_ROOT:-$SUPERVISOR_ROOT/cache/${SESSION}}"
SUPERVISOR_CACHE_ROOT_EXPLICIT="${CODEX_SUPERVISOR_CACHE_ROOT+x}"
SUPERVISOR_TMP_ROOT="${CODEX_SUPERVISOR_TMP_ROOT:-$SUPERVISOR_ROOT/tmp/${SESSION}}"
SUPERVISOR_TMP_ROOT_EXPLICIT="${CODEX_SUPERVISOR_TMP_ROOT+x}"
CODEX_HOME_PROFILE="${CODEX_SUPERVISOR_CODEX_HOME_PROFILE:-lean}"
CODEX_HOME_EXTRA_ITEMS="${CODEX_SUPERVISOR_CODEX_HOME_EXTRA_ITEMS:-}"
NICE_LEVEL="${CODEX_SUPERVISOR_NICE:-5}"
STATE_FILE_EXPLICIT="${CODEX_SUPERVISOR_STATE_FILE+x}"
CODEX_CMD=""
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
LOG_FILE="${CODEX_SUPERVISOR_LOG:-$SUPERVISOR_ROOT/logs/${SESSION}.log}"
LOG_FILE_EXPLICIT="${CODEX_SUPERVISOR_LOG+x}"
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
PERIODIC_CLEANUP_SECS="${CODEX_SUPERVISOR_PERIODIC_CLEANUP_SECS:-120}"
# Worktree age threshold for periodic cleanup (minutes). Codex creates
# fresh worktrees per iteration; abandoning them after ~30 min is safe
# given typical iteration is ≤25 min.
PERIODIC_WORKTREE_AGE_MIN="${CODEX_SUPERVISOR_PERIODIC_WORKTREE_AGE_MIN:-5}"
# Hard cap on a single goal iteration before we forcibly respawn the pane
# to prevent the conversation from growing long enough to need a remote
# compaction step (which can fail under usage-limit and brick the pane).
# 0 disables. Default 45 minutes: long enough for small lane iterations,
# short enough to keep the context below compacting territory.
MAX_ITERATION_SECS="${CODEX_SUPERVISOR_MAX_ITERATION_SECS:-2700}"
# Planner lane. By default every supervisor batch gets exactly one generated
# PLANNER pane unless the prompt file already defines a planner lane. The
# planner is the team's leader: it reviews pane updates, keeps a written plan
# current, and queues/steers next work without editing production code.
PLANNER_ENABLED="${CODEX_SUPERVISOR_PLANNER:-1}"
PLANNER_DOC_DEFAULT="/Users/billy/Desktop/projects/codex-supervisor/docs/parallel-sessions/planner.md"
PLANNER_DOC="${CODEX_SUPERVISOR_PLANNER_DOC:-$PLANNER_DOC_DEFAULT}"
LANE_FILTER="${CODEX_SUPERVISOR_LANES:-}"
# Tmux resilience. Dead panes are common when codex exits, and full tmux
# sessions can disappear under resource pressure. Keep them recoverable by
# default; `stop` still kills the daemon, so explicit stops stay stopped.
AUTO_RESPAWN_DEAD_PANES="${CODEX_SUPERVISOR_RESPAWN_DEAD_PANES:-1}"
AUTO_RECREATE_SESSION="${CODEX_SUPERVISOR_AUTO_RECREATE_SESSION:-1}"
# Prompt contract: each non-comment prompt must be a short /goal command
# pointing at markdown instructions. Keep detail in .md files, not inline.
PROMPT_MAX_WORDS="${CODEX_SUPERVISOR_MAX_PROMPT_WORDS:-50}"
# Hard pane cap. The operator/skill should right-size total project work
# across hosts; this script enforces a safe per-session ceiling so one prompt
# file cannot accidentally spawn a tmux-crashing pane farm.
MAX_PANES="${CODEX_SUPERVISOR_MAX_PANES:-8}"
RAM_MB_PER_PANE="${CODEX_SUPERVISOR_RAM_MB_PER_PANE:-600}"
DISK_MB_PER_PANE="${CODEX_SUPERVISOR_DISK_MB_PER_PANE:-1024}"
START_STAGGER_SECS="${CODEX_SUPERVISOR_START_STAGGER_SECS:-}"
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
CODEX_LOG_MAX_GB="${CODEX_SUPERVISOR_CODEX_LOG_MAX_GB:-1}"
# Codex CLI sessions retention (days). ~/.codex/sessions accumulates per-task
# JSONL transcripts; default 7 days keeps recent forensics but bounds growth.
# Set to 0 to disable session pruning.
CODEX_SESSIONS_RETAIN_DAYS="${CODEX_SUPERVISOR_CODEX_SESSIONS_RETAIN_DAYS:-3}"
# Supervisor log rotation cap (MB). LOG_FILE is truncated when above this.
SUPERVISOR_LOG_MAX_MB="${CODEX_SUPERVISOR_LOG_MAX_MB:-50}"
# Unified dashboard. `start` launches this once if it is not already healthy.
# Default refresh is 1s so the browser sees live pane output with minimum delay.
DASHBOARD_ENABLED="${CODEX_SUPERVISOR_DASHBOARD:-1}"
DASHBOARD_CMD="${CODEX_SUPERVISOR_DASHBOARD_CMD:-$HOME/bin/csup-dashboard}"
DASHBOARD_PORT="${CODEX_SUPERVISOR_DASHBOARD_PORT:-7777}"
DASHBOARD_LINES="${CODEX_SUPERVISOR_DASHBOARD_LINES:-28}"
DASHBOARD_REFRESH="${CODEX_SUPERVISOR_DASHBOARD_REFRESH:-1}"
DASHBOARD_LOG="${CODEX_SUPERVISOR_DASHBOARD_LOG:-$SUPERVISOR_ROOT/logs/csup-dashboard.log}"
DASHBOARD_LOG_EXPLICIT="${CODEX_SUPERVISOR_DASHBOARD_LOG+x}"
DASHBOARD_PID_FILE="${CODEX_SUPERVISOR_DASHBOARD_PID_FILE:-$SUPERVISOR_ROOT/run/csup-dashboard.pid}"
DASHBOARD_PID_FILE_EXPLICIT="${CODEX_SUPERVISOR_DASHBOARD_PID_FILE+x}"
DASHBOARD_LOCK_DIR="${CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR:-$SUPERVISOR_ROOT/run/csup-dashboard.lock}"
DASHBOARD_LOCK_DIR_EXPLICIT="${CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR+x}"
DASHBOARD_SESSION="${CODEX_SUPERVISOR_DASHBOARD_SESSION:-csup-dashboard}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
    | tee -a "$LOG_FILE" >&2
}

err() { echo "error: $*" >&2; }

shell_quote() {
  # POSIX-safe single-quote escaping for tmux shell commands.
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

prepare_runtime_dirs() {
  mkdir -p \
    "$SUPERVISOR_ROOT" \
    "$SUPERVISOR_ROOT/logs" \
    "$SUPERVISOR_ROOT/run" \
    "$SUPERVISOR_ROOT/work" \
    "$SUPERVISOR_CACHE_ROOT/xdg" \
    "$SUPERVISOR_CACHE_ROOT/npm" \
    "$SUPERVISOR_CACHE_ROOT/uv" \
    "$SUPERVISOR_CACHE_ROOT/pip" \
    "$SUPERVISOR_CACHE_ROOT/playwright" \
    "$SUPERVISOR_CACHE_ROOT/cargo" \
    "$SUPERVISOR_TMP_ROOT" 2>/dev/null || return 1
}

prune_supervisor_runtime_dirs() {
  local age_min="${1:-$PERIODIC_WORKTREE_AGE_MIN}" d
  [[ "$age_min" =~ ^[0-9]+$ ]] || age_min=5
  (( age_min >= 0 )) || return 0
  prepare_runtime_dirs || return 0
  for d in \
    "$SUPERVISOR_CACHE_ROOT/xdg" \
    "$SUPERVISOR_CACHE_ROOT/npm" \
    "$SUPERVISOR_CACHE_ROOT/uv" \
    "$SUPERVISOR_CACHE_ROOT/pip" \
    "$SUPERVISOR_CACHE_ROOT/playwright" \
    "$SUPERVISOR_CACHE_ROOT/cargo" \
    "$SUPERVISOR_TMP_ROOT"
  do
    [[ -d "$d" ]] || continue
    case "$d" in "$SUPERVISOR_ROOT"/*) ;; *) continue ;; esac
    find "$d" -mindepth 1 -maxdepth 1 -mmin +"$age_min" -exec rm -rf {} + 2>/dev/null || true
  done
}

source_codex_home() {
  printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"
}

strip_mcp_config() {
  local src="$1" dst="$2"
  if [[ ! -f "$src" ]]; then
    : > "$dst"
    return 0
  fi
  awk '
    /^\[/ { in_mcp = ($0 ~ /^\[mcp_servers(\.|])/); }
    !in_mcp { print }
  ' "$src" > "$dst"
}

link_codex_home_item() {
  local src="$1" dst="$2"
  [[ -e "$src" || -L "$src" ]] || return 0
  rm -rf "$dst"
  ln -s "$src" "$dst" 2>/dev/null || cp -R "$src" "$dst"
}

prepare_codex_home() {
  prepare_runtime_dirs || return 1
  [[ "$MCP_MODE" == "off" ]] || return 0

  local src_home dst_home item
  src_home="$(source_codex_home)"
  dst_home="$SUPERVISOR_CODEX_HOME"
  if [[ "$dst_home" == "$src_home" ]]; then
    err "CODEX_SUPERVISOR_CODEX_HOME must differ from source CODEX_HOME ($src_home)"
    return 1
  fi
  mkdir -p "$dst_home" "$dst_home/log" "$dst_home/sessions" "$dst_home/tmp"

  strip_mcp_config "$src_home/config.toml" "$dst_home/config.toml"

  # Preserve auth and useful local Codex assets while keeping the config MCP-free.
  # The default "lean" profile intentionally omits skills/memories/plugins:
  # supervised worker panes should read project markdown, not load every
  # operator skill/memory into 12-20 parallel processes.
  for item in \
    auth.json .credentials.json installation_id version.json models_cache.json \
    AGENTS.md RTK.md hooks hooks.json
  do
    link_codex_home_item "$src_home/$item" "$dst_home/$item"
  done

  for item in plugins cache skills memories rules; do
    rm -rf "$dst_home/$item"
  done

  case "$CODEX_HOME_PROFILE" in
    full)
      for item in plugins cache skills memories rules; do
        link_codex_home_item "$src_home/$item" "$dst_home/$item"
      done
      ;;
    lean|"")
      ;;
    *)
      err "unknown CODEX_SUPERVISOR_CODEX_HOME_PROFILE=$CODEX_HOME_PROFILE (use lean or full)"
      return 1
      ;;
  esac

  for item in $CODEX_HOME_EXTRA_ITEMS; do
    link_codex_home_item "$src_home/$item" "$dst_home/$item"
  done
}

priority_wrapped_codex_command() {
  if [[ "$NICE_LEVEL" =~ ^-?[0-9]+$ ]] && (( NICE_LEVEL != 0 )); then
    printf 'nice -n %s %s\n' "$NICE_LEVEL" "$CODEX_BASE_CMD"
  else
    printf '%s\n' "$CODEX_BASE_CMD"
  fi
}

build_codex_command() {
  local prioritized_cmd cache_env
  prioritized_cmd="$(priority_wrapped_codex_command)"
  cache_env="XDG_CACHE_HOME=$(shell_quote "$SUPERVISOR_CACHE_ROOT/xdg") npm_config_cache=$(shell_quote "$SUPERVISOR_CACHE_ROOT/npm") UV_CACHE_DIR=$(shell_quote "$SUPERVISOR_CACHE_ROOT/uv") PIP_CACHE_DIR=$(shell_quote "$SUPERVISOR_CACHE_ROOT/pip") PLAYWRIGHT_BROWSERS_PATH=$(shell_quote "$SUPERVISOR_CACHE_ROOT/playwright") CARGO_HOME=$(shell_quote "$SUPERVISOR_CACHE_ROOT/cargo") TMPDIR=$(shell_quote "$SUPERVISOR_TMP_ROOT")"
  if [[ "$MCP_MODE" == "off" ]]; then
    printf 'CODEX_HOME=%s %s %s\n' "$(shell_quote "$SUPERVISOR_CODEX_HOME")" "$cache_env" "$prioritized_cmd"
  else
    printf '%s %s\n' "$cache_env" "$prioritized_cmd"
  fi
}

ensure_codex_cmd() {
  prepare_codex_home
  CODEX_CMD="$(build_codex_command)"
}

command_name_from_shell_command() {
  local word
  for word in $CODEX_BASE_CMD; do
    case "$word" in
      *=*) continue ;;
      env) continue ;;
      *) printf '%s\n' "$word"; return 0 ;;
    esac
  done
  return 1
}

dashboard_url() {
  printf 'http://127.0.0.1:%s' "$DASHBOARD_PORT"
}

dashboard_http_ok() {
  python3 - "$DASHBOARD_PORT" <<'PY' >/dev/null 2>&1
import json
import sys
import urllib.request

port = sys.argv[1]
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health.json", timeout=1.5) as r:
        payload = json.loads(r.read().decode("utf-8"))
    raise SystemExit(0 if "status" in payload and "panes" in payload else 1)
except Exception:
    raise SystemExit(1)
PY
}

dashboard_status_line() {
  python3 - "$DASHBOARD_PORT" <<'PY'
import json
import sys
import urllib.request

port = sys.argv[1]
url = f"http://127.0.0.1:{port}"
try:
    with urllib.request.urlopen(f"{url}/api/health.json", timeout=1.5) as r:
        h = json.loads(r.read().decode("utf-8"))
    print(
        "dashboard: "
        f"{h.get('status', 'unknown')} · {h.get('projects', 0)} projects · "
        f"{h.get('instances', 0)} instances · {h.get('panes', 0)} panes · "
        f"age {h.get('age_secs', '?')}s · {url}"
    )
except Exception as e:
    print(f"dashboard: not running · {url} · {e}")
PY
}

dashboard_force_refresh() {
  (( DASHBOARD_ENABLED )) || return 0
  python3 - "$DASHBOARD_PORT" <<'PY' >/dev/null 2>&1
import sys
import urllib.request

port = sys.argv[1]
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/refresh.json", timeout=8) as r:
        r.read()
except Exception:
    pass
PY
}

dashboard_matching_pids() {
  python3 - "$DASHBOARD_CMD" "$DASHBOARD_PORT" <<'PY'
import shlex
import subprocess
import sys

cmd = sys.argv[1]
port = sys.argv[2]

try:
    out = subprocess.check_output(["ps", "-axo", "pid=,args="], text=True)
except Exception:
    raise SystemExit(0)

for raw in out.splitlines():
    raw = raw.strip()
    if not raw:
        continue
    bits = raw.split(None, 1)
    if len(bits) != 2:
        continue
    pid, args = bits
    try:
        argv = shlex.split(args)
    except ValueError:
        continue
    if not argv:
        continue

    # Match the actual dashboard process only, not a wrapper shell whose
    # command string happens to mention "csup-dashboard --port 7777".
    dashboard_arg = None
    if argv[0] == cmd:
        dashboard_arg = 0
    elif (
        len(argv) >= 2
        and (argv[0].endswith("/python3") or argv[0] in {"python3", "python"})
        and argv[1] == cmd
    ):
        dashboard_arg = 1
    if dashboard_arg is None:
        continue

    has_port = False
    for i, arg in enumerate(argv):
        if arg == "--port" and i + 1 < len(argv) and argv[i + 1] == port:
            has_port = True
        elif arg == f"--port={port}":
            has_port = True
    if has_port:
        print(pid)
PY
}

replace_unhealthy_dashboard_if_owned() {
  local pids pid killed=0
  pids="$(dashboard_matching_pids | tr '\n' ' ')"
  tmux kill-session -t "$DASHBOARD_SESSION" 2>/dev/null || true
  [[ -n "$pids" ]] || return 0
  log "dashboard on $(dashboard_url) is unhealthy/stale; replacing pid(s): $pids"
  for pid in $pids; do
    kill -TERM "$pid" 2>/dev/null && killed=1 || true
  done
  if (( killed )); then
    sleep 0.75
    for pid in $pids; do
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    done
  fi
}

ensure_dashboard() {
  (( DASHBOARD_ENABLED )) || return 0
  mkdir -p "$(dirname "$DASHBOARD_LOCK_DIR")" "$(dirname "$DASHBOARD_PID_FILE")" "$(dirname "$DASHBOARD_LOG")" 2>/dev/null || true
  if dashboard_http_ok; then
    log "dashboard already running: $(dashboard_url)"
    dashboard_force_refresh
    return 0
  fi
  if [[ ! -x "$DASHBOARD_CMD" ]]; then
    log "dashboard autostart skipped: $DASHBOARD_CMD is not executable"
    return 0
  fi

  local have_lock=0
  if [[ -d "$DASHBOARD_LOCK_DIR" ]]; then
    local lock_age
    lock_age=$(python3 - "$DASHBOARD_LOCK_DIR" <<'PY' 2>/dev/null || echo 9999
import os
import sys
import time
print(int(time.time() - os.stat(sys.argv[1]).st_mtime))
PY
)
    if [[ "${lock_age:-9999}" =~ ^[0-9]+$ ]] && (( lock_age > 30 )); then
      rmdir "$DASHBOARD_LOCK_DIR" 2>/dev/null || true
    fi
  fi
  if mkdir "$DASHBOARD_LOCK_DIR" 2>/dev/null; then
    have_lock=1
  else
    # Another supervisor start may be launching it. Wait briefly instead of
    # racing a duplicate server on the same port.
    local i
    for ((i=0; i<40; i++)); do
      dashboard_http_ok && { log "dashboard became available: $(dashboard_url)"; return 0; }
      sleep 0.25
    done
    log "dashboard autostart skipped: lock held and health never became ready"
    return 0
  fi

  if dashboard_http_ok; then
    (( have_lock )) && rmdir "$DASHBOARD_LOCK_DIR" 2>/dev/null || true
    log "dashboard already running: $(dashboard_url)"
    return 0
  fi
  replace_unhealthy_dashboard_if_owned

  log "launching dashboard: $(dashboard_url) refresh=${DASHBOARD_REFRESH}s"
  if command -v tmux >/dev/null 2>&1; then
    local dash_shell
    printf -v dash_shell 'exec %q --port %q --lines %q --refresh %q >> %q 2>&1' \
      "$DASHBOARD_CMD" "$DASHBOARD_PORT" "$DASHBOARD_LINES" "$DASHBOARD_REFRESH" "$DASHBOARD_LOG"
    tmux kill-session -t "$DASHBOARD_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$DASHBOARD_SESSION" "$dash_shell"
    tmux display-message -p -t "$DASHBOARD_SESSION" '#{pane_pid}' > "$DASHBOARD_PID_FILE" 2>/dev/null || true
  else
    nohup "$DASHBOARD_CMD" \
      --port "$DASHBOARD_PORT" \
      --lines "$DASHBOARD_LINES" \
      --refresh "$DASHBOARD_REFRESH" \
      >> "$DASHBOARD_LOG" 2>&1 &
    local dashboard_pid=$!
    disown "$dashboard_pid" 2>/dev/null || true
    echo "$dashboard_pid" > "$DASHBOARD_PID_FILE" 2>/dev/null || true
  fi

  local i
  for ((i=0; i<80; i++)); do
    if dashboard_http_ok; then
      (( have_lock )) && rmdir "$DASHBOARD_LOCK_DIR" 2>/dev/null || true
      log "dashboard ready: $(dashboard_url)"
      dashboard_force_refresh
      return 0
    fi
    sleep 0.25
  done
  (( have_lock )) && rmdir "$DASHBOARD_LOCK_DIR" 2>/dev/null || true
  log "dashboard launch requested but health did not become ready; see $DASHBOARD_LOG"
  return 0
}

capture_has() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]]
}

capture_has_ci() {
  local haystack="$1" needle="$2" nocase_was_set=0 rc
  if shopt -q nocasematch; then nocase_was_set=1; fi
  shopt -s nocasematch
  [[ "$haystack" == *"$needle"* ]]
  rc=$?
  (( nocase_was_set )) || shopt -u nocasematch
  return "$rc"
}

capture_goal_done() {
  local cap="$1" nocase_was_set=0 rc
  local goal_done_re='Goal[[:space:]]+(achieved|complete|reached)'
  if shopt -q nocasematch; then nocase_was_set=1; fi
  shopt -s nocasematch
  [[ "$cap" =~ $goal_done_re ]]
  rc=$?
  (( nocase_was_set )) || shopt -u nocasematch
  return "$rc"
}

capture_needs_fresh_context() {
  local cap="$1"
  capture_has "$cap" "Error running remote compact task" \
    || capture_has_ci "$cap" "Compacting conversation"
}

classify_capture_state() {
  local cap="$1"
  if capture_has "$cap" "$LIMIT_PATTERN"; then
    printf 'LIMITED\n'
  elif capture_has "$cap" "Starting MCP"; then
    printf 'STARTING\n'
  elif capture_goal_done "$cap"; then
    printf 'DONE\n'
  elif capture_has "$cap" "Pursuing goal" || capture_has "$cap" "Working"; then
    printf 'WORKING\n'
  elif capture_has "$cap" "$READY_PATTERN" || [[ "$cap" =~ gpt-[0-9] ]]; then
    printf 'READY\n'
  else
    printf '?\n'
  fi
}

capture_preview() {
  local cap="$1" limit="${2:-60}" line last="" preview
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] && last="$line"
  done <<< "$cap"

  local IFS=$' \t\n'
  local words=()
  read -r -a words <<< "$last"
  if (( ${#words[@]} )); then
    preview="${words[*]}"
  else
    preview=""
  fi
  printf '%s\n' "${preview:0:limit}"
}

prompt_word_count() {
  local prompt="$1"
  local IFS=$' \t\n'
  local words=()
  read -r -a words <<< "$prompt"
  printf '%d\n' "${#words[@]}"
}

prompt_references_md() {
  local prompt="$1"
  [[ "$prompt" =~ [^[:space:]]+\.md([^[:alnum:]_.-]|$) ]]
}

validate_prompt_line() {
  local line="$1" source_name="${2:-prompts}" line_no="${3:-?}" words

  if ! [[ "$line" =~ ^/goal([[:space:]]|$) ]]; then
    err "$source_name line $line_no: prompt must start with /goal"
    return 1
  fi

  words=$(prompt_word_count "$line")
  if (( PROMPT_MAX_WORDS > 0 && words > PROMPT_MAX_WORDS )); then
    err "$source_name line $line_no: prompt has ${words} words; prompts must be ${PROMPT_MAX_WORDS} words or fewer"
    return 1
  fi

  if ! prompt_references_md "$line"; then
    err "$source_name line $line_no: prompt must reference at least one .md file; put extra instructions in markdown"
    return 1
  fi
}

# Per-session state file remembers the prompts file path the supervisor was
# started with, so subsequent `status` / `send` / `restart` etc. don't have
# to be invoked from the project dir or with the env var set.
STATE_FILE="${CODEX_SUPERVISOR_STATE_FILE:-$HOME/.codex-supervisor-${SESSION}.state}"

refresh_session_paths() {
  if [[ -z "$SUPERVISOR_CODEX_HOME_EXPLICIT" ]]; then
    SUPERVISOR_CODEX_HOME="$SUPERVISOR_ROOT/codex-home/${SESSION}"
  fi
  if [[ -z "$SUPERVISOR_CACHE_ROOT_EXPLICIT" ]]; then
    SUPERVISOR_CACHE_ROOT="$SUPERVISOR_ROOT/cache/${SESSION}"
  fi
  if [[ -z "$SUPERVISOR_TMP_ROOT_EXPLICIT" ]]; then
    SUPERVISOR_TMP_ROOT="$SUPERVISOR_ROOT/tmp/${SESSION}"
  fi
  if [[ -z "$LOG_FILE_EXPLICIT" ]]; then
    LOG_FILE="$SUPERVISOR_ROOT/logs/${SESSION}.log"
  fi
  if [[ -z "$DASHBOARD_LOG_EXPLICIT" ]]; then
    DASHBOARD_LOG="$SUPERVISOR_ROOT/logs/csup-dashboard.log"
  fi
  if [[ -z "$DASHBOARD_PID_FILE_EXPLICIT" ]]; then
    DASHBOARD_PID_FILE="$SUPERVISOR_ROOT/run/csup-dashboard.pid"
  fi
  if [[ -z "$DASHBOARD_LOCK_DIR_EXPLICIT" ]]; then
    DASHBOARD_LOCK_DIR="$SUPERVISOR_ROOT/run/csup-dashboard.lock"
  fi
  if [[ -z "$STATE_FILE_EXPLICIT" ]]; then
    STATE_FILE="$HOME/.codex-supervisor-${SESSION}.state"
  fi
}

absolute_file_path() {
  local p="$1"
  [[ -z "$p" ]] && return 0
  [[ "$p" != /* ]] && p="$PWD/$p"
  local d b
  d=$(dirname "$p")
  b=$(basename "$p")
  if [[ -d "$d" ]]; then
    printf '%s/%s\n' "$(cd "$d" && pwd -P)" "$b"
  else
    printf '%s\n' "$p"
  fi
}

absolute_dir_path() {
  local p="$1"
  [[ -z "$p" ]] && return 0
  [[ "$p" != /* ]] && p="$PWD/$p"
  if [[ -d "$p" ]]; then
    (cd "$p" && pwd -P)
  else
    printf '%s\n' "$p"
  fi
}

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
    local saved root
    saved=$(grep -E '^PROMPTS_FILE=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
    if [[ -n "$saved" && "$saved" != /* ]]; then
      root=$(grep -E '^PROJECT_ROOT=' "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
      [[ -n "$root" && -f "$root/$saved" ]] && saved="$root/$saved"
    fi
    if [[ -n "$saved" && -f "$saved" ]]; then PROMPTS_FILE="$saved"; return 0; fi
  fi
  if [[ -f "$HOME/codex-prompts.txt" ]]; then PROMPTS_FILE="$HOME/codex-prompts.txt"; fi
}

# Persist resolved state so future commands don't need env vars or cwd.
write_state_file() {
  resolve_prompts_file
  resolve_tasks_dir
  PROMPTS_FILE="$(absolute_file_path "$PROMPTS_FILE")"
  [[ -n "$TASKS_DIR" ]] && TASKS_DIR="$(absolute_dir_path "$TASKS_DIR")"
  {
    echo "PROMPTS_FILE=${PROMPTS_FILE}"
    echo "TASKS_DIR=${TASKS_DIR}"
    echo "PROJECT_ROOT=$(pwd -P)"
    echo "STARTED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$STATE_FILE" 2>/dev/null
}

# Load prompts and lane labels from the prompts file.
# Sets PROMPTS array (one prompt per non-blank, non-comment line) and LANE_LABELS
# (best-effort lane name extracted from each prompt for pane border titles).
declare -a PROMPTS=()
declare -a LANE_LABELS=()

prompt_has_planner_lane() {
  local label lc
  for label in "${LANE_LABELS[@]}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "planner" || "$lc" == "lead" || "$lc" == "leader" ]] && return 0
  done
  return 1
}

lane_filter_matches() {
  local label="$1"
  [[ -n "$LANE_FILTER" ]] || return 0
  local label_lc token token_lc
  label_lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
  for token in ${LANE_FILTER//,/ }; do
    [[ -n "$token" ]] || continue
    token_lc=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
    [[ "$token_lc" == "$label_lc" ]] && return 0
  done
  return 1
}

ensure_planner_prompt() {
  (( PLANNER_ENABLED )) || return 0
  prompt_has_planner_lane && return 0
  local planner_idx="${#PROMPTS[@]}"
  local doc="$PLANNER_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/planner.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/planner.md")"
  fi
  local prompt="/goal You are PANE ${planner_idx}, lane PLANNER. Read ${doc}, then review updates and refresh the team plan."
  validate_prompt_line "$prompt" "generated-planner" 1 || exit 1
  PROMPTS+=("$prompt")
  LANE_LABELS+=("PLANNER")
}

load_prompts() {
  resolve_prompts_file
  if [[ -z "$PROMPTS_FILE" || ! -f "$PROMPTS_FILE" ]]; then
    err "prompts file not found"
    err "use --prompts <file>, set CODEX_SUPERVISOR_PROMPTS, or create ./codex-prompts.txt"
    exit 1
  fi
  PROMPTS=(); LANE_LABELS=()
  local line_no=0 matched_count=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    validate_prompt_line "$line" "$PROMPTS_FILE" "$line_no" || exit 1
    # Best-effort lane label: prefer "lane FOO" / "lane: FOO" / "[FOO]".
    local label=""
    if   [[ "$line" =~ [Ll][Aa][Nn][Ee][[:space:]]*:[[:space:]]*([A-Za-z0-9_-]+) ]]; then label="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ [Ll][Aa][Nn][Ee][[:space:]]+([A-Za-z0-9_-]+) ]]; then label="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ \[([^]]+)\] ]]; then label="${BASH_REMATCH[1]}"
    else label="pane$((${#LANE_LABELS[@]}))"
    fi
    if ! lane_filter_matches "$label"; then
      continue
    fi
    PROMPTS+=("$line")
    LANE_LABELS+=("$label")
    matched_count=$((matched_count + 1))
  done < "$PROMPTS_FILE"
  if [[ -n "$LANE_FILTER" && "$matched_count" -eq 0 ]]; then
    err "CODEX_SUPERVISOR_LANES='$LANE_FILTER' matched no prompts in $PROMPTS_FILE"
    exit 1
  fi
  ensure_planner_prompt
  if (( ${#PROMPTS[@]} == 0 )); then
    err "no prompts found in $PROMPTS_FILE"; exit 1
  fi
  if (( MAX_PANES > 0 && ${#PROMPTS[@]} > MAX_PANES )); then
    err "$PROMPTS_FILE has ${#PROMPTS[@]} prompts; run at most ${MAX_PANES} panes per supervisor session"
    err "right-size the lane subset; with csup, keep the total project panes within the same cap across hosts"
    exit 1
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
  tmux capture-pane -t "$1" -p -S "-$CAPTURE_TAIL_LINES" 2>/dev/null
}

pane_target() { printf '%s:0.%d' "$SESSION" "${PANE_IDX[$1]}"; }

# Resolve a user-supplied pane reference (numeric index or lane label) to
# a tmux pane index. Echoes the index on stdout, returns 0 on success.
resolve_pane() {
  local ref="$1" i ref_lc label_lc
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    for i in "${!PANE_IDX[@]}"; do
      [[ "${PANE_IDX[$i]}" == "$ref" ]] && { echo "$i"; return 0; }
    done
    return 1
  fi
  ref_lc=$(printf '%s' "$ref" | tr '[:upper:]' '[:lower:]')
  for i in "${!LANE_LABELS[@]}"; do
    label_lc=$(printf '%s' "${LANE_LABELS[$i]}" | tr '[:upper:]' '[:lower:]')
    if [[ "$label_lc" == "$ref_lc" ]]; then echo "$i"; return 0; fi
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

pane_dead() {
  local target="$1"
  [[ "$(tmux display-message -p -t "$target" '#{pane_dead}' 2>/dev/null)" == "1" ]]
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
    if capture_has "$cap" "$READY_PATTERN" \
       && ! capture_has "$cap" "$NOT_READY_PATTERN"; then
      log "[pane $i ${LANE_LABELS[$i]}] ready candidate after ${s}s, settling for ${READY_SETTLE_SECS}s..."
      sleep "$READY_SETTLE_SECS"
      cap=$(capture_tail "$target")
      if ! capture_has "$cap" "$READY_PATTERN" \
         || capture_has "$cap" "$NOT_READY_PATTERN"; then
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

respawn_pane_and_prompt() {
  local i="$1" prompt="$2" reason="${3:-respawn}" target now
  target=$(pane_target "$i")
  now=$(date +%s)
  log "[pane $i ${LANE_LABELS[$i]}] ${reason}; respawning + resending prompt"
  tmux respawn-pane -k -t "$target" "$CODEX_CMD"
  LAST_RESPAWN[$i]=$now
  LIMIT_STREAK[$i]=0
  LAST_GOAL_DONE[$i]=0
  ITERATION_STARTED[$i]=$now
  ( wait_ready_and_send "$i" "$prompt" ) &
}

# Per-pane health check called by the poll loop.
# Detects: usage-limit hit (with cooldown-bounded respawn) and goal-completion
# (with grace-bounded auto-resend).
check_pane() {
  local i=$1 prompt=$2 target now since_last
  target=$(pane_target "$i")
  now=$(date +%s)

  if (( AUTO_RESPAWN_DEAD_PANES )) && pane_dead "$target"; then
    respawn_pane_and_prompt "$i" "$prompt" "dead pane detected"
    return
  fi

  local cap; cap=$(capture_tail "$target")

  # FAST PATH: Codex context is compacting or already failed compaction.
  # Respawn on first sight so the lane restarts from markdown instructions
  # instead of growing the same conversation until the remote compact task
  # fails under usage limits.
  if capture_needs_fresh_context "$cap"; then
    since_last=$(( now - ${LAST_RESPAWN[$i]:-0} ))
    local fast_cooldown=$RESPAWN_COOLDOWN_SECS
    if capture_has_ci "$cap" "try again at"; then
      fast_cooldown=$((60 * 60))
    fi
    if (( since_last < fast_cooldown )); then
      log "[pane $i ${LANE_LABELS[$i]}] compacting/compact-task state but cooldown active (${since_last}s/${fast_cooldown}s)"
      return
    fi
    respawn_pane_and_prompt "$i" "$prompt" "compacting/compact-task state -- fast"
    return
  fi

  # Usage limit handling
  if capture_has "$cap" "$LIMIT_PATTERN"; then
    LIMIT_STREAK[$i]=$(( ${LIMIT_STREAK[$i]:-0} + 1 ))
    # Codex prints "try again at <date> <time>" on hard limits. When we see
    # this we use a much longer cooldown (1h) since the limit is account-
    # wide and respawning won't help — it'll just hit the same wall.
    local cooldown=$RESPAWN_COOLDOWN_SECS
    if capture_has_ci "$cap" "try again at"; then
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
      respawn_pane_and_prompt "$i" "$prompt" "usage limit recovery"
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
    if capture_goal_done "$cap"; then
      if (( ${LAST_GOAL_DONE[$i]:-0} == 0 )); then
        LAST_GOAL_DONE[$i]=$now
        log "[pane $i ${LANE_LABELS[$i]}] goal achieved; on-complete=$ON_COMPLETE in ${RESEND_GRACE_SECS}s"
      else
        local idle=$(( now - LAST_GOAL_DONE[$i] ))
        if (( idle >= RESEND_GRACE_SECS )); then
          # Reset BEFORE deciding to avoid re-firing if the action takes time
          LAST_GOAL_DONE[$i]=0
          # Skip if pane has gotten busy again in the meantime
          if capture_has "$cap" "Working" \
             || capture_has "$cap" "Pursuing goal"; then
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
      # "Goal achieved" is no longer visible in the capture — either the text
      # scrolled out of view after codex exited, or codex printed an IDLE
      # message before exiting. Do NOT blindly reset the timer: if it was
      # already set, keep it running until it fires. Only clear it when we
      # see the pane is actively working on a new task (the respawn succeeded).
      if (( ${LAST_GOAL_DONE[$i]:-0} > 0 )); then
        # Timer is live — check if it has now expired even though the
        # "Goal achieved" text is gone.
        local idle=$(( now - LAST_GOAL_DONE[$i] ))
        if (( idle >= RESEND_GRACE_SECS )); then
          LAST_GOAL_DONE[$i]=0
          if ! capture_has "$cap" "Working" && ! capture_has "$cap" "Pursuing goal"; then
            local lane="${LANE_LABELS[$i]}" next_task="" sent_label=""
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
                  next_task="${PROMPTS[$i]}"; sent_label="redo (queue empty)"
                fi
                ;;
              redo)
                next_task="${PROMPTS[$i]}"; sent_label="redo"
                ;;
            esac
            if [[ -n "$next_task" ]]; then
              local _ram; _ram=$(free_ram_mb)
              local _disk; _disk=$(free_gb_on_cwd)
              if (( _ram < MIN_FREE_RAM_MB )); then
                log "[pane $i $lane] low RAM (${_ram}MB) — deferring respawn"
                run_periodic_cleanup; ITERATION_STARTED[$i]=$now
              elif (( _disk < MIN_FREE_GB )); then
                log "[pane $i $lane] low disk (${_disk}G) — deferring respawn"
                run_periodic_cleanup; ITERATION_STARTED[$i]=$now
              elif (( RESPAWN_ON_GOAL_DONE )); then
                log "[pane $i $lane] respawning codex before next task ($sent_label) [timer expired, text gone]"
                tmux respawn-pane -k -t "$target" "$CODEX_CMD"
                ( wait_ready_and_send "$i" "$next_task" ) &
                ITERATION_STARTED[$i]=$now
              else
                log "[pane $i $lane] sending $sent_label [timer expired, text gone]: $(printf '%.60s' "$next_task")..."
                send_prompt_to_pane "$target" "$next_task"
                ITERATION_STARTED[$i]=$now
              fi
            else
              log "[pane $i $lane] resting (no queued task)"
            fi
          fi
        fi
        # else: timer still counting — leave LAST_GOAL_DONE[$i] alone
      elif capture_has "$cap" "Working" || capture_has "$cap" "Pursuing goal" \
           || capture_has "$cap" "Starting MCP"; then
        # New task is running — clear any stale timer
        LAST_GOAL_DONE[$i]=0
      fi
      # else: pane is idle/ready with no prior timer — nothing to do
    fi
  fi

  # Hard iteration cap. If a pane has been "Working" past MAX_ITERATION_SECS
  # without showing "Goal achieved", forcibly respawn — assume it's stuck
  # in a long compaction/exploration loop. Bounds context growth too,
  # which helps avoid the remote-compact-task usage-limit failure.
  if (( MAX_ITERATION_SECS > 0 )); then
    local started=${ITERATION_STARTED[$i]:-0}
    if (( started > 0 )) && (( now - started >= MAX_ITERATION_SECS )); then
      respawn_pane_and_prompt "$i" "$prompt" "iteration exceeded ${MAX_ITERATION_SECS}s"
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
free_gb_on_path() {
  local path="${1:-.}"
  df -k "$path" 2>/dev/null | awk 'NR==2 { printf "%d\n", $4/1024/1024; found=1 } END { if (!found) print 0 }' || echo 0
}

free_gb_on_cwd() {
  free_gb_on_path "."
}

free_gb_on_runtime_root() {
  mkdir -p "$SUPERVISOR_ROOT" 2>/dev/null || true
  free_gb_on_path "$SUPERVISOR_ROOT"
}

# Free RAM in MB. Pages are 16 KB on Apple Silicon, 4 KB on Intel.
# vm_stat reports "Pages free", "Pages inactive" — both are reclaimable.
# We use free+inactive because macOS aggressively keeps "inactive" cached
# memory that the kernel will return to processes on demand.
free_ram_mb() {
  if command -v free >/dev/null 2>&1; then
    free -m 2>/dev/null | awk '/^Mem:/ { if ($7 ~ /^[0-9]+$/) print $7; else print $4; found=1 } END { if (!found) print 0 }'
    return
  fi
  local pgsz; pgsz=$(vm_stat 2>/dev/null | awk '/page size of/{print $8}')
  [[ -z "$pgsz" ]] && pgsz=16384
  vm_stat 2>/dev/null | awk -v pg="$pgsz" '
    /Pages free/     { f=$3+0 }
    /Pages inactive/ { i=$3+0 }
    END { printf "%d\n", (f+i)*pg/1024/1024 }
  '
}

ceil_div() {
  local n="$1" d="$2"
  (( d > 0 )) || { echo 0; return; }
  echo $(( (n + d - 1) / d ))
}

effective_start_stagger_secs() {
  local pane_count="${1:-0}"
  if [[ -n "$START_STAGGER_SECS" ]]; then
    echo "$START_STAGGER_SECS"
  elif (( pane_count >= 6 )); then
    echo 2
  elif (( pane_count >= 3 )); then
    echo 1
  else
    echo 0
  fi
}

ensure_start_resource_budget() {
  local pane_count="${1:-${#PROMPTS[@]}}"
  local free_ram free_disk need_ram need_disk_gb extra_disk_gb

  free_ram=$(free_ram_mb)
  free_disk=$(free_gb_on_runtime_root)
  need_ram=$(( MIN_FREE_RAM_MB + pane_count * RAM_MB_PER_PANE ))
  extra_disk_gb=$(ceil_div "$(( pane_count * DISK_MB_PER_PANE ))" 1024)
  need_disk_gb=$(( MIN_FREE_GB + extra_disk_gb ))

  if (( RAM_MB_PER_PANE > 0 && free_ram < need_ram )); then
    err "not enough free RAM to start ${pane_count} pane(s): ${free_ram}MB free, need >= ${need_ram}MB (${RAM_MB_PER_PANE}MB/pane + ${MIN_FREE_RAM_MB}MB reserve)"
    err "start fewer panes, move lanes to a remote host, or raise CODEX_SUPERVISOR_RAM_MB_PER_PANE only if measured"
    return 1
  fi

  if (( DISK_MB_PER_PANE > 0 && free_disk < need_disk_gb )); then
    err "not enough free disk to start ${pane_count} pane(s): ${free_disk}G free, need >= ${need_disk_gb}G (${DISK_MB_PER_PANE}MB/pane + ${MIN_FREE_GB}G reserve)"
    err "run: $0 cleanup"
    return 1
  fi

  if (( pane_count >= 6 )); then
    log "resource budget ok for ${pane_count} panes: ${free_ram}MB RAM free (need ${need_ram}MB), ${free_disk}G disk free (need ${need_disk_gb}G), startup stagger $(effective_start_stagger_secs "$pane_count")s"
  fi
  return 0
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

  # 0) Supervisor-owned runtime/cache dirs (normally on MyDrive).
  prune_supervisor_runtime_dirs "$PERIODIC_WORKTREE_AGE_MIN"

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
  refresh_session_paths

  # Kill-switch: refuse to start if the user has disabled this session
  # (or all sessions). Removing the file re-enables. This prevents stale
  # daemons / launchd jobs / scripts from silently resurrecting a session
  # the user explicitly stopped.
  if [[ -f "$HOME/.codex-supervisor.disabled" ]]; then
    err "refusing to start: $HOME/.codex-supervisor.disabled exists (global kill-switch)"
    err "remove that file to re-enable the supervisor"
    exit 1
  fi
  if [[ -f "$HOME/.codex-supervisor-${SESSION}.disabled" ]]; then
    err "refusing to start session '$SESSION': $HOME/.codex-supervisor-${SESSION}.disabled exists"
    err "remove that file to re-enable this session"
    exit 1
  fi

  # If we're invoked with --daemon, skip the launcher fork and just run.
  # Self-restart loop: if _start_supervisor_main exits with a non-zero code
  # (crash), wait 5 s and try again without killing the live tmux session.
  # A clean stop (INT/TERM) exits 0 and breaks the loop immediately.
  if (( daemon_mode )); then
    local _restart_count=0 _rc=0
    while true; do
      _start_supervisor_main "$_restart_count"
      _rc=$?
      (( _rc == 0 )) && break   # clean stop — don't restart
      _restart_count=$(( _restart_count + 1 ))
      if (( _restart_count > 10 )); then
        log "daemon crashed $_restart_count times consecutively; giving up"
        break
      fi
      log "daemon crashed (exit $_rc); restart #$_restart_count in 5s..."
      sleep 5
    done
    return
  fi

  ensure_codex_cmd
  command -v tmux >/dev/null || { err "tmux not on PATH"; exit 1; }
  local first_word; first_word=$(command_name_from_shell_command)
  command -v "$first_word" >/dev/null || { err "$first_word not on PATH"; exit 1; }

  local session_running=0
  tmux has-session -t "$SESSION" 2>/dev/null && session_running=1
  if (( ! session_running )); then
    load_prompts
    ensure_start_resource_budget || exit 1
    # Disk-space guard. Each pane is a worktree + node_modules + node MCP tree;
    # a fresh start on a near-full disk has historically crashed the daemon
    # mid-spin and orphaned MCP children. Refuse early instead.
    ensure_disk_space || exit 1
  fi

  # Reap any stale daemon processes from prior runs before forking a new one.
  # `stop` doesn't always get called between restarts, and the daemon
  # survives terminal close, so they accumulate.
  reap_stale_daemons

  # Don't double-launch: if a session of this name is already up, just attach.
  if (( session_running )); then
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

  # One dashboard for all supervisor sessions. This keeps csup-dashboard and
  # codex-supervisor combined operationally: starting any supervisor session
  # also ensures the live all-session dashboard exists.
  ensure_dashboard

  if (( ! attach_after )); then
    echo "session '$SESSION' running in background; attach: tmux attach -t $SESSION"
    echo "dashboard: $(dashboard_url)"
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

# Crash handler — called by the ERR trap inside _start_supervisor_main.
# Logs the failing line+command so crashes are visible in the log file
# rather than dying silently (nohup discards stderr).
_daemon_crash_handler() {
  local lineno="${1:-?}" cmd="${2:-?}"
  log "DAEMON CRASH at line $lineno: $cmd"
  log "  session=$SESSION lanes=${LANE_LABELS[*]:-none}"
  exit 2
}

# The actual supervisor body, run by the daemon child.
# $1 = restart count (0 = fresh start, >0 = crash recovery restart)
_start_supervisor_main() {
  local _is_restart="${1:-0}"
  ensure_codex_cmd
  load_prompts
  # INT/TERM = clean stop (kills session, exits 0, self-restart loop breaks).
  # ERR      = set -u unbound-variable crash — log it and exit 2 so the
  #            self-restart loop recovers without tearing down the session.
  # NOTE: do NOT add set -E here. set -E would inherit the ERR trap into
  # every called function, causing false-positive crashes on expected
  # non-zero returns (e.g. pgrep returning 1 = no matches, pop_next_task
  # returning 1 = empty queue). The ERR trap here only covers the direct
  # poll-loop body; set -u errors in called functions still kill the daemon
  # and are logged via the handler since set -u triggers ERR in bash.
  trap 'cleanup_session; exit 0' INT TERM
  trap '_daemon_crash_handler $LINENO "$BASH_COMMAND"' ERR

  if (( _is_restart )); then
    log "daemon restart #$_is_restart: re-attaching to session '$SESSION'"
    populate_pane_idx_from_running
    if ! tmux has-session -t "$SESSION" 2>/dev/null || (( ${#PANE_IDX[@]} == 0 )); then
      log "session gone or empty — rebuilding from scratch"
      ensure_start_resource_budget || exit 1
      write_state_file
      create_tmux_session_panes 1 || exit 1
      prompt_all_panes
    else
      # Session and panes still live — just reset tracking arrays and resume.
      local _i; for _i in "${!PROMPTS[@]}"; do
        LIMIT_STREAK[$_i]=0; LAST_RESPAWN[$_i]=0
        LAST_GOAL_DONE[$_i]=0; ITERATION_STARTED[$_i]=$(date +%s)
      done
      write_state_file
      log "re-attached to ${#PANE_IDX[@]} live pane(s); resuming poll loop"
    fi
  else
    ensure_start_resource_budget || exit 1
    write_state_file
    create_tmux_session_panes 1 || exit 1
    log "session '$SESSION': ${#PROMPTS[@]} panes (lanes: ${LANE_LABELS[*]})"
    log "prompts: $PROMPTS_FILE"
    prompt_all_panes
  fi

  log "all panes prompted; entering poll loop (every ${POLL_INTERVAL}s)"
  local last_periodic_cleanup=$(date +%s)
  while true; do
    sleep "$POLL_INTERVAL"
    # If the tmux session is gone unexpectedly, rebuild it instead of
    # abandoning the team. `cmd_stop` terminates this daemon before/while
    # killing tmux, so explicit stops still stay stopped.
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
      if (( AUTO_RECREATE_SESSION )); then
        recreate_missing_session || true
        continue
      fi
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

create_tmux_session_panes() {
  local kill_existing="${1:-1}"
  (( kill_existing )) && tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -x 240 -y 70 "$CODEX_CMD"
  apply_tmux_config

  local i start_stagger
  start_stagger=$(effective_start_stagger_secs "${#PROMPTS[@]}")
  for ((i=1; i<${#PROMPTS[@]}; i++)); do
    tmux split-window -t "$SESSION:0" "$CODEX_CMD"
    tmux select-layout -t "$SESSION:0" tiled >/dev/null
    if (( start_stagger > 0 && i < ${#PROMPTS[@]} - 1 )); then
      sleep "$start_stagger"
    fi
  done

  populate_pane_idx_from_running
  if (( ${#PANE_IDX[@]} != ${#PROMPTS[@]} )); then
    log "ERROR: pane count ${#PANE_IDX[@]} != prompt count ${#PROMPTS[@]}"
    return 1
  fi

  apply_even_grid
  apply_pane_titles
  return 0
}

prompt_all_panes() {
  local i start_stagger
  start_stagger=$(effective_start_stagger_secs "${#PROMPTS[@]}")
  for i in "${!PROMPTS[@]}"; do
    LIMIT_STREAK[$i]=0; LAST_RESPAWN[$i]=0; LAST_GOAL_DONE[$i]=0; ITERATION_STARTED[$i]=$(date +%s)
    ( wait_ready_and_send "$i" "${PROMPTS[$i]}" ) &
    if (( start_stagger > 0 )); then
      sleep "$start_stagger"
    fi
  done
  wait
}

recreate_missing_session() {
  log "tmux session '$SESSION' disappeared; attempting recreate"
  run_periodic_cleanup
  if ! ensure_start_resource_budget; then
    log "recreate deferred: resource budget check failed"
    return 1
  fi
  if ! create_tmux_session_panes 0; then
    log "recreate failed: could not rebuild tmux panes"
    return 1
  fi
  log "recreated tmux session '$SESSION'; re-sending ${#PROMPTS[@]} prompt(s)"
  prompt_all_panes
}

cmd_stop() {
  local was_running=0 mark_disabled=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-disable) mark_disabled=0; shift ;;
      *) err "stop: unknown arg $1"; return 1 ;;
    esac
  done
  tmux has-session -t "$SESSION" 2>/dev/null && was_running=1
  cleanup_session
  # After tearing down the panes, prune the worktrees they created. Each
  # codex pane spawns its own git worktree + node_modules; without this,
  # they pile up across restarts (we hit 11 GB orphaned in one session).
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git worktree prune 2>/dev/null
  fi
  # Drop a `.disabled` marker so the kill-switch in cmd_start() refuses
  # any silent restart attempt (stale daemon, launchd job, watchdog,
  # external script). Pass --no-disable to skip if you intend to restart
  # immediately.
  if (( mark_disabled )); then
    : > "$HOME/.codex-supervisor-${SESSION}.disabled"
  fi
  if (( was_running )); then
    echo "stopped session '$SESSION', reaped orphan MCP children, pruned worktrees"
  else
    echo "no session '$SESSION' running; reaped any leftover MCP orphans + pruned worktrees"
  fi
  if (( mark_disabled )); then
    echo "marked DISABLED (~/.codex-supervisor-${SESSION}.disabled). Remove that file or pass --no-disable next stop to re-enable."
  fi
}

# Lightweight in-flight cleanup, called periodically from the poll loop.
# Targets the highest-yield, fastest-to-scan culprits only. Skips brew
# cleanup and Time Machine snapshots (expensive); save those for the
# explicit `cleanup` subcommand.
run_periodic_cleanup() {
  local before after removed=0
  before=$(free_gb_on_cwd)

  # 0) Supervisor-owned runtime/cache dirs. By default these live on
  # /Volumes/MyDrive/codex-supervisor, not the root filesystem.
  prune_supervisor_runtime_dirs "$PERIODIC_WORKTREE_AGE_MIN"

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
  # Always assign empty defaults so `set -u` doesn't fire when piping to head/tail.
  local C_RESET="" C_RED="" C_YELLOW="" C_GREEN="" C_CYAN="" C_DIM="" C_BOLD=""
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
    state="$(classify_capture_state "$cap")"
    color="$C_DIM"
    case "$state" in
      LIMITED)  color="$C_RED" ;;
      STARTING) color="$C_CYAN" ;;
      DONE)     color="$C_YELLOW" ;;
      WORKING)  color="$C_GREEN" ;;
      READY)    color="$C_CYAN" ;;
    esac
    # Queue depth: count uncommented /goal lines in the lane queue file (if any).
    queue_count="-"
    lane_lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    if [[ -n "$TASKS_DIR" ]]; then
      queue_file="$TASKS_DIR/${lane_lc}.txt"
      if [[ -f "$queue_file" ]]; then
        queue_count=$(grep -cE '^/goal' "$queue_file" 2>/dev/null); queue_count=${queue_count:-0}
      fi
    fi
    tail=$(capture_preview "$cap" 60)
    printf '%-5s %-12s %s%-9s%s %5s %s\n' \
      "${PANE_IDX[$i]}" "$label" "$color" "$state" "$C_RESET" "$queue_count" "$tail"
  done
  # Footer: a one-line summary so you don't have to count states by eye.
  local total=${#PANE_IDX[@]}
  echo
  printf '%s%d panes · session %s · prompts %s%s\n' "$C_DIM" "$total" "$SESSION" "${PROMPTS_FILE:-?}" "$C_RESET"
  dashboard_status_line
}

# Peek at queued tasks per lane without consuming them.
cmd_queue() {
  load_prompts
  resolve_tasks_dir
  if [[ -z "$TASKS_DIR" || ! -d "$TASKS_DIR" ]]; then
    echo "no tasks dir found (looked for ./codex-tasks then ~/codex-tasks)"; return 1
  fi
  local C_DIM="" C_BOLD="" C_RESET=""
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
  ensure_codex_cmd
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

cmd_validate_prompts() {
  load_prompts
  printf 'ok: %d prompts in %s (/%s, <=%s words, markdown-backed)\n' \
    "${#PROMPTS[@]}" "$PROMPTS_FILE" "goal" "$PROMPT_MAX_WORDS"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  if (( $# == 0 )); then
    cmd_start
    return $?
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
    validate-prompts|validate) shift; cmd_validate_prompts ;;
    cleanup)  shift; cmd_cleanup ;;
    queue|q)  shift; cmd_queue ;;
    -h|--help|help) cmd_help ;;
    # Backwards-compat: legacy flags went straight to start
    --prompts|--session|--no-open|--no-attach) cmd_start "$@" ;;
    *) err "unknown subcommand: $1"; cmd_help; return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
