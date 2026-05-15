#!/usr/bin/env bash
# codex-supervisor -- run multiple codex CLI sessions in parallel tmux panes.
#
# Single tmux session, single window, N tiled panes -- one pane per prompt
# plus a generated CEO lane by default. DEBUG/VALIDATOR compatibility lanes are
# opt-in; team starts can request one MANAGER lane plus dynamic workers.
# Auto-sends each prompt
# once its pane is ready, respawns panes whose codex exits or hits the usage limit,
# recreates a missing tmux session after resource checks, auto-resends prompts
# when a /goal completes, and applies an even MxN grid layout so cells stay
# equal.
#
# Subcommands:
#   start [--no-attach]       launch the session (default if no subcommand)
#                             refuses if free disk < CODEX_SUPERVISOR_MIN_FREE_GB (default 5)
#   stop                      kill session, reap MCP orphans, prune git worktrees
#   cleanup [--global]        project-scoped cleanup by default; --global also
#                             prunes machine-wide caches/snapshots
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
#   CODEX_SUPERVISOR_UV_THREADPOOL_SIZE per-pane libuv worker threads (default: 2)
#   CODEX_SUPERVISOR_NATIVE_NUM_THREADS per-pane BLAS/OpenMP/native threads (default: 1)
#   CODEX_SUPERVISOR_MAX_LOAD_PER_CPU start/rebuild load guard; 0 disables (default: 1.25)
#   CODEX_SUPERVISOR_POLL            seconds between health checks (default: 15)
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
#   CODEX_SUPERVISOR_CEO             1 = append a generated CEO lane if missing (default: 1)
#   CODEX_SUPERVISOR_CEO_DOC         CEO executive markdown path
#   CODEX_SUPERVISOR_GM              backwards-compatible alias for CODEX_SUPERVISOR_CEO
#   CODEX_SUPERVISOR_GM_DOC          backwards-compatible alias for CODEX_SUPERVISOR_CEO_DOC
#   CODEX_SUPERVISOR_MANAGER         1 = append a generated team MANAGER lane if missing (default: 0)
#   CODEX_SUPERVISOR_MANAGER_DOC     team manager markdown path
#   CODEX_SUPERVISOR_REVIEWER        1 = append a generated REVIEWER lane if missing (default: 0)
#   CODEX_SUPERVISOR_REVIEWER_DOC    team reviewer markdown path
#   CODEX_SUPERVISOR_DEBUGGER        1 = append a generated DEBUG lane if missing (default: 0)
#   CODEX_SUPERVISOR_DEBUGGER_DOC    debugger markdown path
#   CODEX_SUPERVISOR_VALIDATOR       1 = append a generated VALIDATOR lane if missing (default: CODEX_SUPERVISOR_PLANNER or 0)
#   CODEX_SUPERVISOR_PLANNER         backwards-compatible alias for CODEX_SUPERVISOR_VALIDATOR
#   CODEX_SUPERVISOR_VALIDATOR_DOC   validator/planner markdown path
#   CODEX_SUPERVISOR_DYNAMIC_WORKERS number of generated dynamic worker panes (default: 0)
#   CODEX_SUPERVISOR_DYNAMIC_WORKER_DOC dynamic-worker markdown path
#   CODEX_SUPERVISOR_LANES           comma/space-separated lane allowlist for right-sized starts
#   CODEX_SUPERVISOR_GENERATED_ONLY  1 = ignore prompt-file lanes; run only generated fixed/dynamic lanes
#   CODEX_SUPERVISOR_RESPAWN_DEAD_PANES 1 = respawn exited codex panes (default: 1)
#   CODEX_SUPERVISOR_AUTO_RECREATE_SESSION 1 = rebuild a vanished tmux session (default: 1)
#   CODEX_SUPERVISOR_MAX_PANES       hard cap on final prompts/panes per session
#                                    incl. fixed roles (default: 8)
#   CODEX_SUPERVISOR_RAM_MB_PER_PANE projected RAM budget per pane for start preflight (default: 600)
#   CODEX_SUPERVISOR_DISK_MB_PER_PANE projected disk budget per pane for start preflight (default: 1024)
#   CODEX_SUPERVISOR_START_STAGGER_SECS startup delay between pane spawns/prompts; unset = auto

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
SUPERVISOR_DOC_ROOT="${CODEX_SUPERVISOR_DOC_ROOT:-$SCRIPT_DIR/docs}"
if [[ ! -d "$SUPERVISOR_DOC_ROOT/parallel-sessions" ]]; then
  for _doc_root_candidate in \
    "/Users/billy/Desktop/projects/codex-supervisor/docs" \
    "/home/billy/Desktop/projects/codex-supervisor/docs" \
    "/projects/hep/fs10/shared/codex-tooling/supervisor/docs"; do
    if [[ -d "$_doc_root_candidate/parallel-sessions" ]]; then
      SUPERVISOR_DOC_ROOT="$_doc_root_candidate"
      break
    fi
  done
fi
unset _doc_root_candidate

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SESSION="${CODEX_SUPERVISOR_SESSION:-codex-supervisor}"
DEFAULT_SUPERVISOR_ROOT="$HOME/.codex-supervisor"
[[ -d "/Volumes/MyDrive" ]] && DEFAULT_SUPERVISOR_ROOT="/Volumes/MyDrive/codex-supervisor"
# CODEX_SUPERVISOR_RUN_DIR is the name used by the shared LUNARC toolchain.
# Keep CODEX_SUPERVISOR_ROOT as the canonical/local name, but honor RUN_DIR so
# one sourced env file can redirect all supervisor state off the small HOME
# filesystem on cluster login/compute nodes.
SUPERVISOR_ROOT="${CODEX_SUPERVISOR_ROOT:-${CODEX_SUPERVISOR_RUN_DIR:-$DEFAULT_SUPERVISOR_ROOT}}"
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
# Per-pane native thread caps. Node, Python, BLAS, tokenizers, and libuv-backed
# tools can otherwise multiply a large pane count into hundreds of runnable
# helper threads. Keep defaults conservative; callers can override the libuv
# pool when a lane truly needs more filesystem/crypto parallelism.
UV_THREADPOOL_SIZE_CAP="${CODEX_SUPERVISOR_UV_THREADPOOL_SIZE:-2}"
NATIVE_NUM_THREADS_CAP="${CODEX_SUPERVISOR_NATIVE_NUM_THREADS:-1}"
TOKENIZERS_PARALLELISM_CAP="${CODEX_SUPERVISOR_TOKENIZERS_PARALLELISM:-false}"
STATE_FILE_EXPLICIT="${CODEX_SUPERVISOR_STATE_FILE+x}"
DAEMON_PID_FILE_EXPLICIT="${CODEX_SUPERVISOR_DAEMON_PID_FILE+x}"
CODEX_CMD=""
POLL_INTERVAL="${CODEX_SUPERVISOR_POLL:-15}"
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
#   queue       - pop next line from codex-tasks/<lane>.txt; if empty, rest.
#   queue-redo  - pop next line from queue; if empty, resend original prompt.
#   redo        - always resend the original prompt.
#   rest        - leave the pane idle.
ON_COMPLETE="${CODEX_SUPERVISOR_ON_COMPLETE:-queue-redo}"
# Lane names that are "continuous" — they have no queue file and should
# always re-run their original prompt when goal achieved (instead of
# resting). Space-separated, lowercased. Match is on the lane label
# parsed from the /goal prompt. Set to literal "*" to mark ALL lanes as
# continuous (operator policy: never let a worker sit idle — the lane's
# /goal should describe fallback work-finding when its queue is empty).
CONTINUOUS_LANES="${CODEX_SUPERVISOR_CONTINUOUS_LANES:-*}"
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
# Fixed project roles. By default direct project starts get one real CEO
# Codex pane. Worker-team starts should explicitly enable MANAGER and disable
# CEO; the team manager owns debug, validation, routing, and worker acceptance.
# DEBUG and VALIDATOR remain opt-in compatibility lanes only.
# Existing prompt-file lanes with matching labels satisfy the fixed slots.
CEO_ENABLED="${CODEX_SUPERVISOR_CEO:-${CODEX_SUPERVISOR_GM:-${CODEX_SUPERVISOR_GENERAL_MANAGER:-1}}}"
CEO_ENABLED_EXPLICIT="${CODEX_SUPERVISOR_CEO+x}${CODEX_SUPERVISOR_GM+x}${CODEX_SUPERVISOR_GENERAL_MANAGER+x}"
CEO_DOC_DEFAULT="$SUPERVISOR_DOC_ROOT/parallel-sessions/ceo-executive.md"
CEO_DOC="${CODEX_SUPERVISOR_CEO_DOC:-${CODEX_SUPERVISOR_GM_DOC:-${CODEX_SUPERVISOR_GENERAL_MANAGER_DOC:-$CEO_DOC_DEFAULT}}}"
MANAGER_ENABLED="${CODEX_SUPERVISOR_MANAGER:-${CODEX_SUPERVISOR_TEAM_MANAGER:-0}}"
MANAGER_ENABLED_EXPLICIT="${CODEX_SUPERVISOR_MANAGER+x}${CODEX_SUPERVISOR_TEAM_MANAGER+x}"
MANAGER_DOC_DEFAULT="$SUPERVISOR_DOC_ROOT/parallel-sessions/general-manager.md"
MANAGER_DOC="${CODEX_SUPERVISOR_MANAGER_DOC:-${CODEX_SUPERVISOR_TEAM_MANAGER_DOC:-$MANAGER_DOC_DEFAULT}}"
REVIEWER_ENABLED="${CODEX_SUPERVISOR_REVIEWER:-0}"
REVIEWER_ENABLED_EXPLICIT="${CODEX_SUPERVISOR_REVIEWER+x}"
REVIEWER_DOC_DEFAULT="$SUPERVISOR_DOC_ROOT/parallel-sessions/reviewer.md"
REVIEWER_DOC="${CODEX_SUPERVISOR_REVIEWER_DOC:-$REVIEWER_DOC_DEFAULT}"
# Backwards-compatible variable names for scripts that still refer to the old
# GM fixed slot.
GM_ENABLED="$CEO_ENABLED"
GM_ENABLED_EXPLICIT="$CEO_ENABLED_EXPLICIT"
GM_DOC="$CEO_DOC"
DEBUGGER_ENABLED="${CODEX_SUPERVISOR_DEBUGGER:-0}"
DEBUGGER_ENABLED_EXPLICIT="${CODEX_SUPERVISOR_DEBUGGER+x}"
DEBUGGER_DOC_DEFAULT="$SUPERVISOR_DOC_ROOT/parallel-sessions/debugger.md"
DEBUGGER_DOC="${CODEX_SUPERVISOR_DEBUGGER_DOC:-$DEBUGGER_DOC_DEFAULT}"
VALIDATOR_ENABLED="${CODEX_SUPERVISOR_VALIDATOR:-${CODEX_SUPERVISOR_PLANNER:-0}}"
VALIDATOR_ENABLED_EXPLICIT="${CODEX_SUPERVISOR_VALIDATOR+x}${CODEX_SUPERVISOR_PLANNER+x}"
# Backwards-compatible variable name for tests/scripts that still refer to the
# old generated planner slot.
PLANNER_ENABLED="$VALIDATOR_ENABLED"
VALIDATOR_DOC_DEFAULT="$SUPERVISOR_DOC_ROOT/parallel-sessions/validator-planner.md"
VALIDATOR_DOC="${CODEX_SUPERVISOR_VALIDATOR_DOC:-${CODEX_SUPERVISOR_PLANNER_DOC:-$VALIDATOR_DOC_DEFAULT}}"
PLANNER_DOC="$VALIDATOR_DOC"
DYNAMIC_WORKERS="${CODEX_SUPERVISOR_DYNAMIC_WORKERS:-0}"
DYNAMIC_WORKERS_EXPLICIT="${CODEX_SUPERVISOR_DYNAMIC_WORKERS+x}"
DYNAMIC_WORKER_DOC_DEFAULT="$SUPERVISOR_DOC_ROOT/parallel-sessions/dynamic-worker.md"
DYNAMIC_WORKER_DOC="${CODEX_SUPERVISOR_DYNAMIC_WORKER_DOC:-$DYNAMIC_WORKER_DOC_DEFAULT}"
# Shared blockers are factory-wide stop-the-line work. Dynamic workers should
# take them before worker-specific or generic open tasks so lane-local progress
# cannot keep moving while common acceptance blockers remain unresolved.
BLOCKER_QUEUE_LANES="${CODEX_SUPERVISOR_BLOCKER_QUEUE_LANES:-blockers blocker}"
DYNAMIC_QUEUE_LANES="${CODEX_SUPERVISOR_DYNAMIC_QUEUE_LANES:-blockers blocker open worker workers dynamic}"
LANE_FILTER="${CODEX_SUPERVISOR_LANES:-}"
LANE_FILTER_EXPLICIT="${CODEX_SUPERVISOR_LANES+x}"
GENERATED_ONLY="${CODEX_SUPERVISOR_GENERATED_ONLY:-0}"
GENERATED_ONLY_EXPLICIT="${CODEX_SUPERVISOR_GENERATED_ONLY+x}"
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
# When 1, prompt files with more lanes than MAX_PANES are *truncated* to the
# first MAX_PANES lanes instead of refusing to start. Useful when a prompt
# file is a superset and a SLURM node only has budget for a subset (the CEO's
# typical workflow on shared compute nodes). Default 0 preserves the historic
# fail-fast behaviour so silent truncation does not surprise dev workstations.
TRUNCATE_PROMPTS="${CODEX_SUPERVISOR_TRUNCATE_PROMPTS:-0}"
# Per-session tmux socket. Each supervisor session runs on its own tmux
# server (different -L socket name). This isolates failure domains: when
# Codex processes crash en-masse on one session and bring down that
# session's tmux server, peer sessions on different servers survive
# untouched. The cascade-error fix that lets the node scale past ~25
# panes without one bad session taking down everything.
# Setting to "shared" reverts to the historical single-server-all-sessions
# behaviour for dev workstations that don't need isolation.
TMUX_SOCKET="${CODEX_SUPERVISOR_TMUX_SOCKET:-}"
# Node-wide cross-session pane cap. Multiple supervisor sessions on the same
# node (LUNARC compute nodes routinely host 4-6 team sessions inside one SLURM
# allocation) share RLIMIT_NPROC (~4096 on LUNARC) and CPU/RAM. Each codex pane
# spawns ~4-8 OS processes (Rust binary + Node.js MCP children + shell), so the
# safe ceiling is well below per-session MAX_PANES * session_count. Defaults to
# 40 panes/node which keeps process count under ~320 even at peak respawn. Set
# to 0 to disable (single-node Mac dev where per-session MAX_PANES is enough).
NODE_MAX_PANES="${CODEX_SUPERVISOR_NODE_MAX_PANES:-40}"
# Cross-session startup lock. When multiple supervisors start simultaneously on
# the same node (e.g. CEO bootstraps 5 teams at once), the parallel pane spawns
# create a process burst that exceeds RLIMIT_NPROC and crashes panes at startup.
# Holding a node-wide lock serialises the "create panes + send prompts" phase
# so each session's stagger applies sequentially. Set to 0 to disable.
NODE_START_LOCK_SECS="${CODEX_SUPERVISOR_NODE_START_LOCK_SECS:-300}"
# Respawn rate limit. If too many panes die in a short window, respawning
# them all immediately re-triggers the same crash cascade (the underlying
# resource pressure that killed them is still present). Below this rate the
# supervisor respawns immediately; above it, it backs off and lets recovery
# settle. RESPAWN_BURST_LIMIT respawns within RESPAWN_BURST_WINDOW_SECS
# triggers RESPAWN_BACKOFF_SECS of cooldown.
RESPAWN_BURST_LIMIT="${CODEX_SUPERVISOR_RESPAWN_BURST_LIMIT:-3}"
RESPAWN_BURST_WINDOW_SECS="${CODEX_SUPERVISOR_RESPAWN_BURST_WINDOW_SECS:-10}"
RESPAWN_BACKOFF_SECS="${CODEX_SUPERVISOR_RESPAWN_BACKOFF_SECS:-30}"
# Tracks recent respawn timestamps. Bash arrays don't support easy time-window
# eviction so we keep epoch seconds and filter on each check.
RESPAWN_TIMES=()
RESPAWN_BACKOFF_UNTIL=0
RAM_MB_PER_PANE="${CODEX_SUPERVISOR_RAM_MB_PER_PANE:-600}"
DISK_MB_PER_PANE="${CODEX_SUPERVISOR_DISK_MB_PER_PANE:-1024}"
START_STAGGER_SECS="${CODEX_SUPERVISOR_START_STAGGER_SECS:-}"
# Detached tmux sessions need an explicit virtual window size. Without this,
# remote/LUNARC sessions can fall back to an 80x24 terminal and Codex wraps at
# ~20-40 columns even though the dashboard card has more horizontal space.
TMUX_WINDOW_X="${CODEX_SUPERVISOR_TMUX_X:-240}"
TMUX_WINDOW_Y="${CODEX_SUPERVISOR_TMUX_Y:-70}"
# CPU/load guard for starts and rebuilds. A value of 1.25 allows short bursts
# above core count while preventing a new pane wave during existing saturation.
# Set to 0 to disable if an external scheduler already manages CPU pressure.
MAX_LOAD_PER_CPU="${CODEX_SUPERVISOR_MAX_LOAD_PER_CPU:-1.25}"
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
# Cleanup is project-scoped by default. Set CODEX_SUPERVISOR_GLOBAL_CLEANUP=1
# (or pass cleanup --global) for old whole-machine sweeps.
GLOBAL_CLEANUP="${CODEX_SUPERVISOR_GLOBAL_CLEANUP:-0}"
PROJECTS_ROOT="${CODEX_SUPERVISOR_PROJECTS_ROOT:-$HOME/Desktop/projects}"
TMP_SWEEP_ROOT="${CODEX_SUPERVISOR_TMP_SWEEP_ROOT:-/private/tmp}"
SUPERPOWERS_WORKTREES_ROOT="${CODEX_SUPERVISOR_SUPERPOWERS_WORKTREES_ROOT:-$HOME/.config/superpowers/worktrees}"
MYDRIVE_SUPERPOWERS_WORKTREES_ROOT="${CODEX_SUPERVISOR_MYDRIVE_SUPERPOWERS_WORKTREES_ROOT:-/Volumes/MyDrive/superpowers/worktrees}"
ACTIONS_RUNNER_WORK_ROOT="${CODEX_SUPERVISOR_ACTIONS_RUNNER_WORK_ROOT:-/Volumes/MyDrive/actions-runner-work}"
DIAGNOSTIC_MESSAGES_ROOT="${CODEX_SUPERVISOR_DIAGNOSTIC_MESSAGES_ROOT:-/private/var/log/DiagnosticMessages}"
# Unified dashboard. `start` launches this once if it is not already healthy.
# Default refresh is 0.2s so the browser sees livestream-like pane output.
DASHBOARD_ENABLED="${CODEX_SUPERVISOR_DASHBOARD:-1}"
SUPERVISOR_SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SUPERVISOR_SCRIPT_PATH" ]]; do
  _supervisor_link_dir="$(cd -P -- "$(dirname -- "$SUPERVISOR_SCRIPT_PATH")" && pwd -P)"
  _supervisor_link_target="$(readlink "$SUPERVISOR_SCRIPT_PATH")"
  if [[ "$_supervisor_link_target" != /* ]]; then
    _supervisor_link_target="$_supervisor_link_dir/$_supervisor_link_target"
  fi
  SUPERVISOR_SCRIPT_PATH="$_supervisor_link_target"
done
SUPERVISOR_SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SUPERVISOR_SCRIPT_PATH")" && pwd -P)"
unset _supervisor_link_dir _supervisor_link_target
DEFAULT_DASHBOARD_CMD="$SUPERVISOR_SCRIPT_DIR/csup-dashboard"
if [[ ! -x "$DEFAULT_DASHBOARD_CMD" ]]; then
  if [[ -x "$HOME/bin/csup-dashboard" ]]; then
    DEFAULT_DASHBOARD_CMD="$HOME/bin/csup-dashboard"
  else
    _csup_dashboard_on_path="$(command -v csup-dashboard 2>/dev/null || true)"
    [[ -n "$_csup_dashboard_on_path" ]] && DEFAULT_DASHBOARD_CMD="$_csup_dashboard_on_path"
    unset _csup_dashboard_on_path
  fi
fi
DASHBOARD_CMD="${CODEX_SUPERVISOR_DASHBOARD_CMD:-$DEFAULT_DASHBOARD_CMD}"
DASHBOARD_PORT="${CODEX_SUPERVISOR_DASHBOARD_PORT:-7777}"
DASHBOARD_LINES="${CODEX_SUPERVISOR_DASHBOARD_LINES:-12}"
DASHBOARD_REFRESH="${CODEX_SUPERVISOR_DASHBOARD_REFRESH:-0.2}"
DASHBOARD_LOG="${CODEX_SUPERVISOR_DASHBOARD_LOG:-$SUPERVISOR_ROOT/logs/csup-dashboard.log}"
DASHBOARD_LOG_EXPLICIT="${CODEX_SUPERVISOR_DASHBOARD_LOG+x}"
case "$(uname -s 2>/dev/null || true)" in
  Darwin) DASHBOARD_USE_TMUX_DEFAULT=0 ;;
  *)      DASHBOARD_USE_TMUX_DEFAULT=1 ;;
esac
DASHBOARD_USE_TMUX="${CODEX_SUPERVISOR_DASHBOARD_TMUX:-$DASHBOARD_USE_TMUX_DEFAULT}"
DASHBOARD_PID_FILE="${CODEX_SUPERVISOR_DASHBOARD_PID_FILE:-$SUPERVISOR_ROOT/run/csup-dashboard.pid}"
DASHBOARD_PID_FILE_EXPLICIT="${CODEX_SUPERVISOR_DASHBOARD_PID_FILE+x}"
DASHBOARD_LOCK_DIR="${CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR:-$SUPERVISOR_ROOT/run/csup-dashboard.lock}"
DASHBOARD_LOCK_DIR_EXPLICIT="${CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR+x}"
DASHBOARD_SESSION="${CODEX_SUPERVISOR_DASHBOARD_SESSION:-csup-dashboard}"
SESSION_START_LOCK_HELD=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Resolve the tmux socket name for this supervisor invocation.
# - Empty TMUX_SOCKET → default to the session name (per-session isolation).
# - TMUX_SOCKET=shared → use tmux's "default" socket (legacy single-server mode).
# - Any other value → use that socket name verbatim (advanced sharing setups).
_resolve_tmux_socket() {
  if [[ -z "$TMUX_SOCKET" ]]; then
    # Use the session name as the socket name. Sanitise to tmux-safe chars.
    TMUX_SOCKET=$(printf '%s' "$SESSION" | tr -c '[:alnum:]_-' '_')
    [[ -z "$TMUX_SOCKET" ]] && TMUX_SOCKET="csup_default"
  fi
}

# tmux wrapper: every tmux invocation in this script transparently picks up
# the per-session socket via -L. The dashboard's streamer enumerates all
# csup_* sockets in the user's tmux tmpdir so multi-server discovery works.
# Setting TMUX_SOCKET=shared collapses everything to one server (legacy).
tmux() {
  # Lazy resolution: if TMUX_SOCKET hasn't been set yet but SESSION is known,
  # derive it now so subcommands like `stop` and `attach` (which don't go
  # through the full cmd_start setup) still use the right socket.
  if [[ -z "$TMUX_SOCKET" && -n "$SESSION" ]]; then
    _resolve_tmux_socket
  fi
  if [[ "$TMUX_SOCKET" == "shared" || -z "$TMUX_SOCKET" ]]; then
    command tmux "$@"
  else
    command tmux -L "$TMUX_SOCKET" "$@"
  fi
}

log() {
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" \
    | tee -a "$LOG_FILE" >&2
}

err() {
  # Write to BOTH stderr (for interactive use) AND $LOG_FILE (so daemonized
  # supervisors that have stderr redirected to /dev/null still leave a trail
  # of why they refused to start). Before 2026-05-15 this only went to stderr,
  # causing every guard-rejection (resource budget, pane budget, load gate,
  # disk quota, etc.) to vanish silently when the daemon was forked with
  # `nohup ... 2>&1` — surfaced as "dashboard already running then nothing".
  if [[ -n "${LOG_FILE:-}" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    printf '[%s] error: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG_FILE" >&2
  else
    echo "error: $*" >&2
  fi
}

session_start_lock_dir() {
  local safe
  safe=$(printf '%s' "$SESSION" | tr -c 'A-Za-z0-9_.-' '_')
  printf '%s/run/%s.start.lock' "$SUPERVISOR_ROOT" "$safe"
}

acquire_session_start_lock() {
  local dir i pid
  dir=$(session_start_lock_dir)
  mkdir -p "$(dirname "$dir")" 2>/dev/null || true
  for ((i=0; i<120; i++)); do
    if mkdir "$dir" 2>/dev/null; then
      printf '%s\n' "$$" > "$dir/pid" 2>/dev/null || true
      SESSION_START_LOCK_HELD=1
      return 0
    fi
    pid=$(cat "$dir/pid" 2>/dev/null || true)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$dir" 2>/dev/null || true
      continue
    fi
    sleep 0.25
  done
  log "start lock still held for session '$SESSION' after 30s: $dir"
  return 1
}

release_session_start_lock() {
  local dir pid
  (( SESSION_START_LOCK_HELD )) || return 0
  dir=$(session_start_lock_dir)
  pid=$(cat "$dir/pid" 2>/dev/null || true)
  if [[ "$pid" == "$$" ]]; then
    rm -rf "$dir" 2>/dev/null || true
  fi
  SESSION_START_LOCK_HELD=0
}

shell_quote() {
  # POSIX-safe single-quote escaping for tmux shell commands.
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

positive_int_or_default() {
  local raw="${1:-}" default="${2:-0}"
  if [[ "$raw" =~ ^[0-9]+$ ]] && (( raw > 0 )); then
    printf '%s\n' "$raw"
  else
    printf '%s\n' "$default"
  fi
}

tmux_window_x() { positive_int_or_default "$TMUX_WINDOW_X" 240; }
tmux_window_y() { positive_int_or_default "$TMUX_WINDOW_Y" 70; }

cleanup_global_enabled() {
  truthy "$GLOBAL_CLEANUP" || truthy "${CODEX_SUPERVISOR_GLOBAL_CLEANUP:-}"
}

current_project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd -P
}

project_config_name() {
  local root cfg line value
  root="$(current_project_root)"
  cfg="$root/.codex-supervisor.toml"
  [[ -f "$cfg" ]] || return 0
  while IFS= read -r line; do
    case "$line" in
      name\ *=*|name=*)
        value="${line#*=}"
        value="${value%%#*}"
        value="${value#\"}"; value="${value%\"}"
        value="$(printf '%s' "$value" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        [[ -n "$value" ]] && printf '%s\n' "$value"
        return 0
        ;;
    esac
  done < "$cfg"
}

cleanup_scope_names() {
  local root base name variant seen=" "
  root="$(current_project_root)"
  for name in "$(basename "$root")" "$(basename "$PWD")" "$SESSION" "$(project_config_name)"; do
    [[ -n "$name" ]] || continue
    for variant in "$name" "${name//-/_}" "${name//_/-}"; do
      [[ ${#variant} -ge 3 ]] || continue
      case "$seen" in *" $variant "*) continue ;; esac
      seen="${seen}${variant} "
      printf '%s\n' "$variant"
    done
  done
}

cleanup_path_in_project_scope() {
  local path="$1" base scope
  cleanup_global_enabled && return 0
  base="$(basename "$path")"
  while IFS= read -r scope; do
    [[ -n "$scope" ]] || continue
    case "$base" in
      "$scope"|"$scope"-*|"$scope"_*|"$scope".*) return 0 ;;
    esac
  done < <(cleanup_scope_names)
  return 1
}

cleanup_path_under_current_project() {
  local path="$1" root
  cleanup_global_enabled && return 0
  root="$(current_project_root)"
  case "$path" in "$root"|"$root"/*) return 0 ;; esac
  return 1
}

cleanup_git_worktree_in_current_repo() {
  local path="$1" current_common wt_common
  cleanup_global_enabled && return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  [[ -e "$path/.git" ]] || return 1
  current_common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  wt_common="$(git -C "$path" rev-parse --git-common-dir 2>/dev/null)" || return 1
  current_common="$(cd "$current_common" 2>/dev/null && pwd -P)" || return 1
  wt_common="$(cd "$wt_common" 2>/dev/null && pwd -P)" || return 1
  [[ "$wt_common" == "$current_common" ]]
}

cleanup_process_in_project_scope() {
  local pid="$1" cmd root scope
  cleanup_global_enabled && return 0
  cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
  [[ -n "$cmd" ]] || return 1
  root="$(current_project_root)"
  [[ "$cmd" == *"$root"* ]] && return 0
  while IFS= read -r scope; do
    [[ -n "$scope" ]] || continue
    [[ "$cmd" == *"$scope"* ]] && return 0
  done < <(cleanup_scope_names)
  return 1
}

find_project_scoped_children() {
  local root="$1" min_depth="${2:-1}" max_depth="${3:-1}" age_min="${4:-$PERIODIC_WORKTREE_AGE_MIN}" scope target
  [[ -d "$root" ]] || return 0
  if cleanup_global_enabled; then
    find -L "$root" -mindepth "$min_depth" -maxdepth "$max_depth" -type d -mmin +"$age_min" 2>/dev/null
    return 0
  fi
  while IFS= read -r scope; do
    [[ -n "$scope" ]] || continue
    target="$root/$scope"
    [[ -d "$target" ]] || continue
    if (( min_depth <= 1 )); then
      find -L "$target" -maxdepth "$((max_depth - 1))" -type d -mmin +"$age_min" 2>/dev/null
    else
      find -L "$target" -mindepth "$((min_depth - 1))" -maxdepth "$((max_depth - 1))" -type d -mmin +"$age_min" 2>/dev/null
    fi
  done < <(cleanup_scope_names)
}

process_tree_descendants() {
  python3 - "$@" <<'PY'
import collections
import subprocess
import sys

roots = []
for raw in sys.argv[1:]:
    try:
        pid = int(raw)
    except (TypeError, ValueError):
        continue
    if pid > 1:
        roots.append(pid)

try:
    out = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
except Exception:
    raise SystemExit(0)

children = collections.defaultdict(list)
for line in out.splitlines():
    parts = line.split()
    if len(parts) < 2:
        continue
    try:
        pid = int(parts[0])
        ppid = int(parts[1])
    except ValueError:
        continue
    children[ppid].append(pid)

seen = set()
ordered = []

def walk(pid):
    for child in children.get(pid, []):
        if child in seen:
            continue
        seen.add(child)
        walk(child)
        ordered.append(child)

for root in roots:
    walk(root)

for pid in ordered:
    print(pid)
PY
}

terminate_process_tree() {
  local root_pid="${1:-}" label="${2:-process tree}" descendants pid killed=0
  [[ "$root_pid" =~ ^[0-9]+$ ]] || return 0
  (( root_pid > 1 )) || return 0
  kill -0 "$root_pid" 2>/dev/null || return 0

  descendants="$(process_tree_descendants "$root_pid" 2>/dev/null || true)"
  # Kill descendants first. If we kill the pane/root process first, its
  # children can be reparented to launchd/init and become much harder to tie
  # back to the Codex session that spawned them.
  for pid in $descendants "$root_pid"; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    (( pid > 1 && pid != $$ )) || continue
    kill -TERM "$pid" 2>/dev/null && killed=$((killed + 1)) || true
  done

  if (( killed > 0 )); then
    sleep 0.25
    for pid in $descendants "$root_pid"; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      (( pid > 1 && pid != $$ )) || continue
      kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
    done
    { wait "$root_pid"; } >/dev/null 2>&1 || true
    log "terminated $label (root pid $root_pid, descendants $(printf '%s' "$descendants" | wc -w | tr -d ' '))"
  fi
}

pane_root_pid() {
  local target="$1"
  tmux display-message -p -t "$target" '#{pane_pid}' 2>/dev/null | tr -d ' '
}

terminate_pane_process_tree() {
  local target="$1" reason="${2:-pane}" root_pid
  root_pid="$(pane_root_pid "$target")"
  [[ -n "$root_pid" ]] || return 0
  terminate_process_tree "$root_pid" "$reason"
}

terminate_session_process_trees() {
  tmux has-session -t "=$SESSION" 2>/dev/null || return 0
  local root_pid
  while IFS= read -r root_pid; do
    [[ -n "$root_pid" ]] || continue
    terminate_process_tree "$root_pid" "session '$SESSION' pane"
  done < <(tmux list-panes -t "$SESSION:0" -F '#{pane_pid}' 2>/dev/null)
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

trust_project_in_codex_config() {
  local cfg="$1" project_dir="$2"
  [[ -n "$cfg" && -n "$project_dir" ]] || return 0
  python3 - "$cfg" "$project_dir" <<'PY'
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
project_dir = sys.argv[2]
text = cfg.read_text(encoding="utf-8", errors="replace") if cfg.exists() else ""
lines = text.splitlines()
escaped = project_dir.replace("\\", "\\\\").replace('"', '\\"')
header = f'[projects."{escaped}"]'

start = None
for i, line in enumerate(lines):
    if line.strip() == header:
        start = i
        break

if start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.extend([header, 'trust_level = "trusted"'])
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        stripped = lines[j].strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            end = j
            break
    for k in range(start + 1, end):
        if lines[k].lstrip().startswith("trust_level"):
            indent = lines[k][: len(lines[k]) - len(lines[k].lstrip())]
            lines[k] = indent + 'trust_level = "trusted"'
            break
    else:
        lines.insert(start + 1, 'trust_level = "trusted"')

cfg.parent.mkdir(parents=True, exist_ok=True)
cfg.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

link_codex_home_item() {
  local src="$1" dst="$2"
  [[ -e "$src" || -L "$src" ]] || return 0
  rm -rf "$dst"
  ln -s "$src" "$dst" 2>/dev/null || cp -R "$src" "$dst"
}

prepare_codex_home_for() {
  local dst_home="${1:-$SUPERVISOR_CODEX_HOME}"
  prepare_runtime_dirs || return 1
  [[ "$MCP_MODE" == "off" ]] || return 0

  local src_home item
  src_home="$(source_codex_home)"
  if [[ "$dst_home" == "$src_home" ]]; then
    err "CODEX_SUPERVISOR_CODEX_HOME must differ from source CODEX_HOME ($src_home)"
    return 1
  fi
  mkdir -p "$dst_home" "$dst_home/log" "$dst_home/sessions" "$dst_home/tmp"

  strip_mcp_config "$src_home/config.toml" "$dst_home/config.toml"
  # Worker Codex homes are isolated per supervisor session, so parent-machine
  # trusted-project entries often do not include the mounted/remote project
  # path (for example LUNARC /projects/...). Mark the exact cwd trusted in the
  # copied MCP-free config to avoid every pane blocking on the folder-trust UI.
  trust_project_in_codex_config "$dst_home/config.toml" "$(pwd -P)"

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

prepare_codex_home() {
  prepare_codex_home_for "$SUPERVISOR_CODEX_HOME"
}

priority_wrapped_codex_command() {
  if [[ "$NICE_LEVEL" =~ ^-?[0-9]+$ ]] && (( NICE_LEVEL != 0 )); then
    printf 'nice -n %s %s\n' "$NICE_LEVEL" "$CODEX_BASE_CMD"
  else
    printf '%s\n' "$CODEX_BASE_CMD"
  fi
}

build_codex_command_for_home() {
  local codex_home="${1:-$SUPERVISOR_CODEX_HOME}" tmp_root="${2:-$SUPERVISOR_TMP_ROOT}"
  local prioritized_cmd cache_env thread_env
  prioritized_cmd="$(priority_wrapped_codex_command)"
  cache_env="XDG_CACHE_HOME=$(shell_quote "$SUPERVISOR_CACHE_ROOT/xdg") npm_config_cache=$(shell_quote "$SUPERVISOR_CACHE_ROOT/npm") UV_CACHE_DIR=$(shell_quote "$SUPERVISOR_CACHE_ROOT/uv") PIP_CACHE_DIR=$(shell_quote "$SUPERVISOR_CACHE_ROOT/pip") PLAYWRIGHT_BROWSERS_PATH=$(shell_quote "$SUPERVISOR_CACHE_ROOT/playwright") CARGO_HOME=$(shell_quote "$SUPERVISOR_CACHE_ROOT/cargo") TMPDIR=$(shell_quote "$tmp_root")"
  thread_env="UV_THREADPOOL_SIZE=$(shell_quote "$UV_THREADPOOL_SIZE_CAP") OMP_NUM_THREADS=$(shell_quote "$NATIVE_NUM_THREADS_CAP") OPENBLAS_NUM_THREADS=$(shell_quote "$NATIVE_NUM_THREADS_CAP") MKL_NUM_THREADS=$(shell_quote "$NATIVE_NUM_THREADS_CAP") NUMEXPR_NUM_THREADS=$(shell_quote "$NATIVE_NUM_THREADS_CAP") VECLIB_MAXIMUM_THREADS=$(shell_quote "$NATIVE_NUM_THREADS_CAP") TOKENIZERS_PARALLELISM=$(shell_quote "$TOKENIZERS_PARALLELISM_CAP")"
  if [[ "$MCP_MODE" == "off" ]]; then
    printf 'CODEX_HOME=%s %s %s %s\n' "$(shell_quote "$codex_home")" "$thread_env" "$cache_env" "$prioritized_cmd"
  else
    printf '%s %s %s\n' "$thread_env" "$cache_env" "$prioritized_cmd"
  fi
}

build_codex_command() {
  build_codex_command_for_home "$SUPERVISOR_CODEX_HOME" "$SUPERVISOR_TMP_ROOT"
}

pane_codex_home() {
  local pane="$1"
  printf '%s/pane-%s\n' "$SUPERVISOR_CODEX_HOME" "$pane"
}

pane_tmp_root() {
  local pane="$1"
  printf '%s/pane-%s\n' "$SUPERVISOR_TMP_ROOT" "$pane"
}

codex_command_for_pane() {
  local pane="$1" home tmp
  home=$(pane_codex_home "$pane")
  tmp=$(pane_tmp_root "$pane")
  mkdir -p "$tmp" 2>/dev/null || return 1
  prepare_codex_home_for "$home" || return 1
  build_codex_command_for_home "$home" "$tmp"
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
  python3 - "$DASHBOARD_PORT" "$DASHBOARD_REFRESH" "$DASHBOARD_CMD" <<'PY' >/dev/null 2>&1
import json
import hashlib
import os
import sys
import urllib.request

port = sys.argv[1]
desired = float(sys.argv[2])
expected_cmd = os.path.realpath(sys.argv[3])
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health.json", timeout=1.5) as r:
        payload = json.loads(r.read().decode("utf-8"))
    if "status" not in payload or "panes" not in payload:
        raise SystemExit(1)
    # 2026-05-15: NEVER replace a dashboard that is actively serving projects.
    # The old sha256/path strictness below killed a healthy, project-serving
    # dashboard whenever the checkout changed (constant during development) and
    # relaunched a replacement that — on macOS — lacked Full Disk Access and
    # then showed zero projects. A dashboard that can see projects is by
    # definition healthy and FDA-capable; keep it regardless of binary identity.
    try:
        serving = int(payload.get("projects") or 0) > 0
    except (TypeError, ValueError):
        serving = False
    if serving:
        raise SystemExit(0)
    source = payload.get("source") if isinstance(payload.get("source"), dict) else {}
    source_path = str(source.get("path") or "")
    # Not serving any project — only now apply the strict upgrade checks so a
    # genuinely broken/stale/foreign instance can be replaced.
    if not source_path or os.path.realpath(source_path) != expected_cmd:
        raise SystemExit(1)
    expected_sha = hashlib.sha256(open(expected_cmd, "rb").read()).hexdigest()[:16]
    if str(source.get("sha256") or "") != expected_sha:
        raise SystemExit(1)
    actual = float(payload.get("refresh_interval_secs"))
    # A dashboard with a much slower server refresh loop looks "healthy" but
    # serves stale panes. Treat old/slow instances as replaceable so `start`
    # upgrades localhost:7777 to the requested real-time cadence.
    allowed = max(desired * 1.5, desired + 0.05)
    raise SystemExit(0 if actual > 0 and actual <= allowed else 1)
except Exception:
    raise SystemExit(1)
PY
}

dashboard_health_source_path() {
  python3 - "$DASHBOARD_PORT" <<'PY'
import json
import sys
import urllib.request

port = sys.argv[1]
try:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health.json", timeout=1.5) as r:
        payload = json.loads(r.read().decode("utf-8"))
    source = payload.get("source") if isinstance(payload.get("source"), dict) else {}
    path = str(source.get("path") or "")
    if path:
        print(path)
except Exception:
    pass
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

dashboard_matching_pids_for_cmd() {
  local match_cmd="${1:-$DASHBOARD_CMD}"
  python3 - "$match_cmd" "$DASHBOARD_PORT" <<'PY'
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
    launcher_name = argv[0].rsplit("/", 1)[-1]
    if argv[0] == cmd:
        dashboard_arg = 0
    elif (
        len(argv) >= 2
        and (
            launcher_name in {"python3", "python", "Python"}
            or argv[0].endswith("/Python")
        )
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

dashboard_matching_pids() {
  dashboard_matching_pids_for_cmd "$DASHBOARD_CMD"
}

replace_unhealthy_dashboard_if_owned() {
  local pids pid killed=0 source_path legacy_cmd
  pids="$(dashboard_matching_pids | tr '\n' ' ')"
  source_path="$(dashboard_health_source_path || true)"
  if [[ -n "$source_path" ]] && [[ "$(basename -- "$source_path")" == "csup-dashboard" ]] && [[ "$source_path" != "$DASHBOARD_CMD" ]]; then
    pids="$pids $(dashboard_matching_pids_for_cmd "$source_path" | tr '\n' ' ')"
  fi
  legacy_cmd="$HOME/bin/csup-dashboard"
  if [[ -x "$legacy_cmd" ]] && [[ "$legacy_cmd" != "$DASHBOARD_CMD" ]]; then
    pids="$pids $(dashboard_matching_pids_for_cmd "$legacy_cmd" | tr '\n' ' ')"
  fi
  pids="$(printf '%s\n' $pids | awk '!seen[$0]++' | tr '\n' ' ')"
  if [[ "$DASHBOARD_USE_TMUX" == "1" ]]; then
    tmux kill-session -t "$DASHBOARD_SESSION" 2>/dev/null || true
  fi
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
  if [[ "$DASHBOARD_USE_TMUX" == "1" ]] && command -v tmux >/dev/null 2>&1; then
    local dash_shell
    printf -v dash_shell 'exec %q --port %q --lines %q --refresh %q >> %q 2>&1' \
      "$DASHBOARD_CMD" "$DASHBOARD_PORT" "$DASHBOARD_LINES" "$DASHBOARD_REFRESH" "$DASHBOARD_LOG"
    tmux kill-session -t "$DASHBOARD_SESSION" 2>/dev/null || true
    # Close fd 9 (node start lock) for the dashboard tmux session — see
    # create_tmux_session_panes for the rationale (tmux server inheritance).
    tmux new-session -d -s "$DASHBOARD_SESSION" "$dash_shell" 9<&-
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
  [[ "$haystack" == *"$needle"* ]] && return 0
  local compact_haystack compact_needle
  compact_haystack=$(capture_compact_ws "$haystack")
  compact_needle=$(capture_compact_ws "$needle")
  [[ "$compact_haystack" == *"$compact_needle"* ]]
}

capture_has_ci() {
  local haystack="$1" needle="$2" nocase_was_set=0 rc
  if shopt -q nocasematch; then nocase_was_set=1; fi
  shopt -s nocasematch
  [[ "$haystack" == *"$needle"* ]]
  rc=$?
  if (( rc != 0 )); then
    local compact_haystack compact_needle
    compact_haystack=$(capture_compact_ws "$haystack")
    compact_needle=$(capture_compact_ws "$needle")
    [[ "$compact_haystack" == *"$compact_needle"* ]]
    rc=$?
  fi
  (( nocase_was_set )) || shopt -u nocasematch
  return "$rc"
}

capture_compact_ws() {
  local s="$1"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  while [[ "$s" == *"  "* ]]; do
    s="${s//  / }"
  done
  printf '%s' "$s"
}

pane_title_indicates_activity() {
  local title="${1:-}"
  # Codex updates the tmux pane title with a Braille spinner while it is
  # starting or streaming. Some TUIs leave the visible capture blank during
  # that window, so use the title as a liveness signal too.
  case "$title" in
    "⠋"*|"⠙"*|"⠹"*|"⠸"*|"⠼"*|"⠴"*|"⠦"*|"⠧"*|"⠇"*|"⠏"*)
      return 0
      ;;
  esac
  return 1
}

pane_has_title_activity() {
  local target="$1" title
  title=$(tmux display-message -p -t "$target" '#{pane_title}' 2>/dev/null || true)
  pane_title_indicates_activity "$title"
}

pane_capture_active() {
  local target="$1" cap="$2"
  # Goal-done takes priority: old scrollback may still contain "Pursuing goal"
  # or "Working" from a prior iteration after the goal completes.
  capture_goal_done "$cap" && return 1
  capture_has "$cap" "Pursuing goal" \
    || capture_has "$cap" "Working" \
    || capture_has "$cap" "Goal active" \
    || pane_has_title_activity "$target"
}

capture_activity_marker_count() {
  local cap="$1"
  printf '%s\n' "$cap" | grep -Eo 'Pursuing goal|Goal active|Working' 2>/dev/null | wc -l | tr -d ' '
}

prompt_submission_confirmed() {
  local target="$1" before="$2" after="$3" before_count after_count
  # A live spinner in the pane title is the freshest signal: it changes with
  # the current Codex run, while scrollback can contain stale "Goal active"
  # text from a previous iteration.
  pane_has_title_activity "$target" && return 0

  before_count=$(capture_activity_marker_count "$before")
  after_count=$(capture_activity_marker_count "$after")
  before_count=${before_count:-0}
  after_count=${after_count:-0}
  if (( after_count > before_count )); then
    return 0
  fi
  if (( before_count == 0 )) && (( after_count > 0 )); then
    return 0
  fi
  return 1
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
STATE_FILE="${CODEX_SUPERVISOR_STATE_FILE:-$SUPERVISOR_ROOT/run/${SESSION}.state}"
DAEMON_PID_FILE="${CODEX_SUPERVISOR_DAEMON_PID_FILE:-$SUPERVISOR_ROOT/run/${SESSION}.daemon.pid}"

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
    STATE_FILE="$SUPERVISOR_ROOT/run/${SESSION}.state"
  fi
  if [[ -z "$DAEMON_PID_FILE_EXPLICIT" ]]; then
    DAEMON_PID_FILE="$SUPERVISOR_ROOT/run/${SESSION}.daemon.pid"
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
  # Avoid `[[ -n ... ]] && ...` here: the daemon installs an ERR trap for
  # crash logging, and on some cluster bash builds the false left-hand side was
  # still reported through the trap, aborting startup when no task queue was
  # configured.
  if [[ -n "$TASKS_DIR" ]]; then
    TASKS_DIR="$(absolute_dir_path "$TASKS_DIR")"
  fi
  {
    echo "PROMPTS_FILE=${PROMPTS_FILE}"
    echo "TASKS_DIR=${TASKS_DIR}"
    echo "LANE_FILTER=${LANE_FILTER}"
    echo "GENERATED_ONLY=${GENERATED_ONLY}"
    echo "CEO_ENABLED=${CEO_ENABLED}"
    echo "GM_ENABLED=${CEO_ENABLED}"
    echo "MANAGER_ENABLED=${MANAGER_ENABLED}"
    echo "REVIEWER_ENABLED=${REVIEWER_ENABLED}"
    echo "DEBUGGER_ENABLED=${DEBUGGER_ENABLED}"
    echo "VALIDATOR_ENABLED=${VALIDATOR_ENABLED}"
    echo "DYNAMIC_WORKERS=${DYNAMIC_WORKERS}"
    echo "PROJECT_ROOT=$(pwd -P)"
    echo "STARTED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$STATE_FILE" 2>/dev/null
}

state_value() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 0
  grep -E "^${key}=" "$STATE_FILE" 2>/dev/null | head -1 | cut -d= -f2-
}

apply_prompt_runtime_state() {
  local v
  if [[ -z "$LANE_FILTER_EXPLICIT" ]]; then
    v=$(state_value "LANE_FILTER")
    [[ -n "$v" ]] && LANE_FILTER="$v"
  fi
  if [[ -z "$GENERATED_ONLY_EXPLICIT" ]]; then
    v=$(state_value "GENERATED_ONLY")
    [[ -n "$v" ]] && GENERATED_ONLY="$v"
  fi
  if [[ -z "$GM_ENABLED_EXPLICIT" ]]; then
    v=$(state_value "GM_ENABLED")
    [[ -z "$v" ]] && v=$(state_value "CEO_ENABLED")
    if [[ -n "$v" ]]; then
      GM_ENABLED="$v"
      CEO_ENABLED="$v"
    fi
  fi
  if [[ -z "$MANAGER_ENABLED_EXPLICIT" ]]; then
    v=$(state_value "MANAGER_ENABLED")
    [[ -n "$v" ]] && MANAGER_ENABLED="$v"
  fi
  if [[ -z "$REVIEWER_ENABLED_EXPLICIT" ]]; then
    v=$(state_value "REVIEWER_ENABLED")
    [[ -n "$v" ]] && REVIEWER_ENABLED="$v"
  fi
  if [[ -z "$DEBUGGER_ENABLED_EXPLICIT" ]]; then
    v=$(state_value "DEBUGGER_ENABLED")
    [[ -n "$v" ]] && DEBUGGER_ENABLED="$v"
  fi
  if [[ -z "$VALIDATOR_ENABLED_EXPLICIT" ]]; then
    v=$(state_value "VALIDATOR_ENABLED")
    [[ -n "$v" ]] && VALIDATOR_ENABLED="$v"
    PLANNER_ENABLED="$VALIDATOR_ENABLED"
  fi
  if [[ -z "$DYNAMIC_WORKERS_EXPLICIT" ]]; then
    v=$(state_value "DYNAMIC_WORKERS")
    [[ -n "$v" ]] && DYNAMIC_WORKERS="$v"
  fi
}

# Load prompts and lane labels from the prompts file.
# Sets PROMPTS array (one prompt per non-blank, non-comment line) and LANE_LABELS
# (best-effort lane name extracted from each prompt for pane border titles).
declare -a PROMPTS=()
declare -a LANE_LABELS=()

prompt_has_gm_lane() {
  local label lc
  for label in "${LANE_LABELS[@]:-}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "gm" || "$lc" == "general-manager" || "$lc" == "generalmanager" || "$lc" == "general_manager" || "$lc" == "ceo" || "$lc" == "executive" || "$lc" == "exec" || "$lc" == "portfolio" ]] && return 0
  done
  return 1
}

prompt_has_ceo_lane() {
  local label lc
  for label in "${LANE_LABELS[@]:-}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "ceo" || "$lc" == "chief" || "$lc" == "executive" || "$lc" == "gm" || "$lc" == "general-manager" || "$lc" == "generalmanager" || "$lc" == "general_manager" ]] && return 0
  done
  return 1
}

prompt_has_manager_lane() {
  local label lc
  for label in "${LANE_LABELS[@]:-}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "manager" || "$lc" == "team-manager" || "$lc" == "lead" || "$lc" == "leader" ]] && return 0
  done
  return 1
}

prompt_has_reviewer_lane() {
  local label lc
  for label in "${LANE_LABELS[@]:-}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "reviewer" || "$lc" == reviewer-* || "$lc" == *-reviewer ]] && return 0
  done
  return 1
}

prompt_has_planner_lane() {
  local label lc
  for label in "${LANE_LABELS[@]:-}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "validator" || "$lc" == "validate" || "$lc" == "planner" || "$lc" == "lead" || "$lc" == "leader" ]] && return 0
  done
  return 1
}

prompt_has_debugger_lane() {
  local label lc
  for label in "${LANE_LABELS[@]:-}"; do
    lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
    [[ "$lc" == "debug" || "$lc" == "debugger" || "$lc" == "optimize" || "$lc" == "optimizer" ]] && return 0
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

lane_is_dynamic_worker() {
  local label lc token token_lc
  label="$1"
  lc=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
  [[ "$lc" == "worker" || "$lc" == worker-* || "$lc" == worker[0-9]* || "$lc" == "dynamic" || "$lc" == dynamic-* ]] && return 0
  for token in ${CODEX_SUPERVISOR_DYNAMIC_LANES:-}; do
    [[ -n "$token" ]] || continue
    token_lc=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
    [[ "$token_lc" == "$lc" ]] && return 0
  done
  return 1
}

ensure_ceo_prompt() {
  (( CEO_ENABLED )) || return 0
  prompt_has_ceo_lane && return 0
  local idx="${#PROMPTS[@]}"
  local doc="$CEO_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/ceo-executive.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/ceo-executive.md")"
  elif [[ ! -f "$doc" && -f "docs/parallel-sessions/general-manager.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/general-manager.md")"
  fi
  local prompt="/goal You are PANE ${idx}, lane CEO. Read ${doc}, docs/company-operating-model.md, docs/ai-factory.md, docs/ceo-staffing.md, docs/parallel-sessions/TEAM_PLAN.md. decide teams, priorities, staffing, escalations; run csup staff; queue decisions in codex-tasks/ceo.txt; send manager updates."
  validate_prompt_line "$prompt" "generated-ceo" 1 || exit 1
  PROMPTS+=("$prompt")
  LANE_LABELS+=("CEO")
}

ensure_gm_prompt() { ensure_ceo_prompt; }

ensure_manager_prompt() {
  (( MANAGER_ENABLED )) || return 0
  prompt_has_manager_lane && return 0
  local idx="${#PROMPTS[@]}"
  local doc="$MANAGER_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/general-manager.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/general-manager.md")"
  fi
  local prompt="/goal You are PANE ${idx}, lane MANAGER. Read ${doc}; manage this team, debug, validate, route worker handoffs."
  validate_prompt_line "$prompt" "generated-manager" 1 || exit 1
  PROMPTS+=("$prompt")
  LANE_LABELS+=("MANAGER")
}

ensure_reviewer_prompt() {
  (( REVIEWER_ENABLED )) || return 0
  prompt_has_reviewer_lane && return 0
  local idx="${#PROMPTS[@]}"
  local doc="$REVIEWER_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/reviewer.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/reviewer.md")"
  fi
  local prompt="/goal You are PANE ${idx}, lane REVIEWER. Read ${doc}; test one user path, file defects, and verify workspace-contract compliance."
  validate_prompt_line "$prompt" "generated-reviewer" 1 || exit 1
  PROMPTS+=("$prompt")
  LANE_LABELS+=("REVIEWER")
}

ensure_debugger_prompt() {
  (( DEBUGGER_ENABLED )) || return 0
  prompt_has_debugger_lane && return 0
  local idx="${#PROMPTS[@]}"
  local doc="$DEBUGGER_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/debugger.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/debugger.md")"
  fi
  local prompt="/goal You are PANE ${idx}, lane DEBUG. Read ${doc}, then debug and optimize one compact-safe slice."
  validate_prompt_line "$prompt" "generated-debugger" 1 || exit 1
  PROMPTS+=("$prompt")
  LANE_LABELS+=("DEBUG")
}

ensure_planner_prompt() {
  (( VALIDATOR_ENABLED )) || return 0
  prompt_has_planner_lane && return 0
  local idx="${#PROMPTS[@]}"
  local doc="$VALIDATOR_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/validator-planner.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/validator-planner.md")"
  elif [[ ! -f "$doc" && -f "docs/parallel-sessions/planner.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/planner.md")"
  fi
  local prompt="/goal You are PANE ${idx}, lane VALIDATOR. Read ${doc}, then validate results, refresh the plan, and queue follow-up prompts."
  validate_prompt_line "$prompt" "generated-validator" 1 || exit 1
  PROMPTS+=("$prompt")
  LANE_LABELS+=("VALIDATOR")
}

ensure_dynamic_worker_prompts() {
  local n count label idx doc prompt
  count="${DYNAMIC_WORKERS:-0}"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  (( count > 0 )) || return 0
  doc="$DYNAMIC_WORKER_DOC"
  if [[ ! -f "$doc" && -f "docs/parallel-sessions/dynamic-worker.md" ]]; then
    doc="$(absolute_file_path "docs/parallel-sessions/dynamic-worker.md")"
  fi
  for ((n=1; n<=count; n++)); do
    label="WORKER-${n}"
    idx="${#PROMPTS[@]}"
    prompt="/goal You are PANE ${idx}, lane ${label}. Read ${doc}, then take one open task and complete one compact-safe iteration."
    validate_prompt_line "$prompt" "generated-worker" "$n" || exit 1
    PROMPTS+=("$prompt")
    LANE_LABELS+=("$label")
  done
}

load_prompts() {
  resolve_prompts_file
  apply_prompt_runtime_state
  if [[ -z "$PROMPTS_FILE" || ! -f "$PROMPTS_FILE" ]]; then
    if truthy "$GENERATED_ONLY"; then
      PROMPTS=(); LANE_LABELS=()
      ensure_ceo_prompt
      ensure_manager_prompt
      ensure_reviewer_prompt
      ensure_debugger_prompt
      ensure_planner_prompt
      ensure_dynamic_worker_prompts
      if (( ${#PROMPTS[@]} == 0 )); then
        err "no generated prompts requested"; exit 1
      fi
      if (( MAX_PANES > 0 && ${#PROMPTS[@]} > MAX_PANES )); then
        if truthy "$TRUNCATE_PROMPTS"; then
          log "WARNING: generated prompt set has ${#PROMPTS[@]} prompts; truncating to first ${MAX_PANES} (TRUNCATE_PROMPTS=1)"
          PROMPTS=("${PROMPTS[@]:0:$MAX_PANES}")
          LANE_LABELS=("${LANE_LABELS[@]:0:$MAX_PANES}")
        else
        err "generated prompt set has ${#PROMPTS[@]} prompts; run at most ${MAX_PANES} panes per supervisor session"
        exit 1
        fi
      fi
      return 0
    fi
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
    truthy "$GENERATED_ONLY" && continue
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
  if [[ -n "$LANE_FILTER" && "$matched_count" -eq 0 ]] && ! truthy "$GENERATED_ONLY"; then
    err "CODEX_SUPERVISOR_LANES='$LANE_FILTER' matched no prompts in $PROMPTS_FILE"
    exit 1
  fi
  ensure_ceo_prompt
  ensure_manager_prompt
  ensure_reviewer_prompt
  ensure_debugger_prompt
  ensure_planner_prompt
  ensure_dynamic_worker_prompts
  if (( ${#PROMPTS[@]} == 0 )); then
    err "no prompts found in $PROMPTS_FILE"; exit 1
  fi
  if (( MAX_PANES > 0 && ${#PROMPTS[@]} > MAX_PANES )); then
    if truthy "$TRUNCATE_PROMPTS"; then
      local _dropped=$(( ${#PROMPTS[@]} - MAX_PANES ))
      log "WARNING: $PROMPTS_FILE has ${#PROMPTS[@]} prompts; CODEX_SUPERVISOR_TRUNCATE_PROMPTS=1 — truncating to first ${MAX_PANES} (${_dropped} dropped)"
      PROMPTS=("${PROMPTS[@]:0:$MAX_PANES}")
      LANE_LABELS=("${LANE_LABELS[@]:0:$MAX_PANES}")
    else
      err "$PROMPTS_FILE has ${#PROMPTS[@]} prompts; run at most ${MAX_PANES} panes per supervisor session"
      err "right-size the lane subset; with csup, keep the total project panes within the same cap across hosts"
      err "or set CODEX_SUPERVISOR_TRUNCATE_PROMPTS=1 to auto-truncate to the first ${MAX_PANES} lanes"
      exit 1
    fi
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
  # Prevent the user-level tmux server from auto-exiting when all sessions
  # transiently die (which happens under resource pressure during recreate
  # cycles). Without exit-empty=off, the supervisor's recreate path races
  # the server shutdown: it tries to tmux split-window after the server has
  # already exited, fails, exits 1, and the crash-restart loop never finds
  # the server in a usable state.
  #
  # exit-empty is a SERVER option, so it resets when the server dies. We
  # also create a hidden sentinel session that holds the server up across
  # transient empty states — see ensure_sentinel_session below.
  tmux set-option -s exit-empty off >/dev/null 2>&1 || true
  ensure_sentinel_session
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

# Keep a hidden, do-nothing tmux session alive at all times so the tmux
# server cannot transiently exit when all real sessions die under load.
# Without this, the server's `exit-empty off` setting is moot — the option
# resets when the server dies, and the next `tmux new-session` starts a
# fresh server with defaults that may then exit again. The sentinel is a
# tiny shell sleeping forever, costing nothing but holding the server up.
ensure_sentinel_session() {
  local sentinel="_csup_sentinel_"
  tmux has-session -t "=$sentinel" 2>/dev/null && return 0
  # `sleep infinity` is widely portable; keeps a pane open without consuming CPU.
  tmux new-session -d -s "$sentinel" "sleep infinity" 9<&- 2>/dev/null || true
  # Re-assert exit-empty off whenever we (re)create the sentinel — covers the
  # case where the server died and was just restarted with default options.
  tmux set-option -s exit-empty off >/dev/null 2>&1 || true
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
  local target="$1" prompt="$2" attempt cap before_cap buffer_name prompt_probe
  prompt_probe="$(printf '%s' "$prompt" | cut -c1-80)"
  for attempt in 1 2 3; do
    # Cancel any open popup / partial state. NEVER send C-c -- that exits
    # codex (which kills the pane). Esc closes its slash-command popup.
    # Do not send C-a/C-k here: Codex TUIs on some terminals insert those
    # controls literally as "^A^K", wedging the input box. C-u is the
    # portable line-clear path we have verified across local and LUNARC panes.
    tmux send-keys -t "$target" Escape 2>/dev/null
    tmux send-keys -t "$target" C-u 2>/dev/null
    tmux send-keys -t "$target" C-u 2>/dev/null
    sleep 0.2
    before_cap=$(tmux capture-pane -t "$target" -p 2>/dev/null | tail -n 40)
    # Long /goal prompts with spaces, slashes, and absolute paths are much
    # more reliable through a tmux paste buffer than thousands of synthetic
    # key events. This also avoids wedge loops where the TUI keeps a partial
    # "Implement {feature}" input and repeated sends never submit.
    buffer_name="csup-prompt-$$-$attempt"
    tmux set-buffer -b "$buffer_name" "$prompt" 2>/dev/null \
      && tmux paste-buffer -d -b "$buffer_name" -t "$target" 2>/dev/null \
      || tmux send-keys -t "$target" "$prompt"
    sleep 0.5
    tmux send-keys -t "$target" Enter   # /-command popup eats this one
    sleep 0.4
    tmux send-keys -t "$target" Enter   # actual submit
    # Verify within ~10s that codex started processing
    local s
    for ((s=1; s<=10; s++)); do
      sleep 1
      cap=$(tmux capture-pane -t "$target" -p 2>/dev/null | tail -n 30)
      if prompt_submission_confirmed "$target" "$before_cap" "$cap"; then
        return 0
      fi
    done
    # Sometimes Codex accepts the pasted /goal into the composer but the
    # synthetic Enter lands before the slash-command UI is ready. In that
    # state, blindly clearing and re-pasting every retry stacks duplicate
    # prompts in the input box. If the intended prompt is already visible,
    # nudge submit a few more times before attempting a fresh paste.
    if [[ -n "$prompt_probe" ]] && printf '%s' "$cap" | grep -Fq "$prompt_probe"; then
      local n
      for ((n=1; n<=3; n++)); do
        tmux send-keys -t "$target" Enter 2>/dev/null || true
        sleep 2
        cap=$(tmux capture-pane -t "$target" -p 2>/dev/null | tail -n 40)
        if prompt_submission_confirmed "$target" "$before_cap" "$cap"; then
          return 0
        fi
      done
    fi
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
        # UNCONFIRMED means Codex received the keystrokes but the supervisor
        # could not detect Working/Pursuing within ~30s. Historically we left
        # the pane in this limbo state; this hung research/polish supervisors
        # when many panes hit UNCONFIRMED at once and never recovered. Force a
        # fresh respawn so the pane returns to a known state rather than
        # silently stalling.
        log "[pane $i ${LANE_LABELS[$i]}] sent but UNCONFIRMED (retries exhausted) — respawning: $(printf '%.60s' "$prompt")..."
        respawn_pane_and_prompt "$i" "$prompt" "send unconfirmed"
      fi
      return 0
    fi
    sleep 2
  done
  log "[pane $i ${LANE_LABELS[$i]}] ERROR: ready timeout (${READY_TIMEOUT}s)"
  return 1
}

# Returns 0 if respawn is allowed now, 1 if the rate limiter says wait.
# The cascade-prevention logic: under resource pressure many panes die in
# quick succession; respawning them all immediately re-triggers the same
# resource exhaustion (kernel-level Codex/Node crashes) that killed them.
# Bursting >RESPAWN_BURST_LIMIT respawns inside RESPAWN_BURST_WINDOW_SECS
# trips a cooldown so the next death wave doesn't compound.
respawn_rate_limit_check() {
  local now; now=$(date +%s)
  if (( RESPAWN_BACKOFF_UNTIL > now )); then
    return 1
  fi
  # Drop timestamps older than the window.
  local cutoff=$(( now - RESPAWN_BURST_WINDOW_SECS ))
  local kept=() ts
  for ts in "${RESPAWN_TIMES[@]}"; do
    (( ts >= cutoff )) && kept+=("$ts")
  done
  RESPAWN_TIMES=("${kept[@]}")
  if (( ${#RESPAWN_TIMES[@]} >= RESPAWN_BURST_LIMIT )); then
    RESPAWN_BACKOFF_UNTIL=$(( now + RESPAWN_BACKOFF_SECS ))
    log "respawn burst limit hit (${#RESPAWN_TIMES[@]}/${RESPAWN_BURST_LIMIT} in ${RESPAWN_BURST_WINDOW_SECS}s); backing off for ${RESPAWN_BACKOFF_SECS}s to avoid cascade"
    return 1
  fi
  RESPAWN_TIMES+=("$now")
  return 0
}

respawn_pane_and_prompt() {
  local i="$1" prompt="$2" reason="${3:-respawn}" target now pane_cmd
  target=$(pane_target "$i")
  now=$(date +%s)
  if ! respawn_rate_limit_check; then
    log "[pane $i ${LANE_LABELS[$i]}] ${reason}; respawn DEFERRED (rate limit / cascade backoff)"
    return 0
  fi
  log "[pane $i ${LANE_LABELS[$i]}] ${reason}; respawning + resending prompt"
  terminate_pane_process_tree "$target" "pane $i ${LANE_LABELS[$i]} before respawn"
  pane_cmd=$(codex_command_for_pane "$i") || return 1
  tmux respawn-pane -k -t "$target" "$pane_cmd"
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
      fast_cooldown=60
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
      cooldown=60
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
          if pane_capture_active "$target" "$cap"; then
            return
          fi
          local lane="${LANE_LABELS[$i]}" next_task="" sent_label=""
          # Per-lane override: continuous lanes (bugs, optimize) always redo
          # when queue is empty regardless of global ON_COMPLETE policy.
          local lane_lc effective="$ON_COMPLETE"
          lane_lc=$(printf '%s' "$lane" | tr '[:upper:]' '[:lower:]')
          if [[ "$CONTINUOUS_LANES" == "*" || " $CONTINUOUS_LANES " == *" $lane_lc "* ]]; then
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
              terminate_pane_process_tree "$target" "pane $i $lane before next task"
              local _pane_cmd; _pane_cmd=$(codex_command_for_pane "$i") || return
              tmux respawn-pane -k -t "$target" "$_pane_cmd"
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
          if ! pane_capture_active "$target" "$cap"; then
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
                terminate_pane_process_tree "$target" "pane $i $lane before next task"
                local _pane_cmd; _pane_cmd=$(codex_command_for_pane "$i") || return
                tmux respawn-pane -k -t "$target" "$_pane_cmd"
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
      elif pane_capture_active "$target" "$cap" \
           || capture_has "$cap" "Starting MCP"; then
        # New task is running — clear any stale timer
        LAST_GOAL_DONE[$i]=0
      else
        local _idle_state=""
        _idle_state=$(classify_capture_state "$cap")
        if { capture_has "$cap" "$READY_PATTERN" \
             && ! capture_has "$cap" "$NOT_READY_PATTERN"; } \
           || [[ "$_idle_state" == "READY" || "$_idle_state" == "?" ]]; then
          local _ready_started=${ITERATION_STARTED[$i]:-0}
          if (( _ready_started > 0 )) && (( now - _ready_started >= RESEND_GRACE_SECS )); then
            local _rlane="${LANE_LABELS[$i]}" _rnext="" _rlabel=""
            local _rlane_lc _reffective="$ON_COMPLETE"
            _rlane_lc=$(printf '%s' "$_rlane" | tr '[:upper:]' '[:lower:]')
            if [[ "$CONTINUOUS_LANES" == "*" || " $CONTINUOUS_LANES " == *" $_rlane_lc "* ]]; then
              _reffective="queue-redo"
            fi
            case "$_reffective" in
              queue|queue-redo)
                if _rnext=$(pop_next_task "$_rlane") && [[ -n "$_rnext" ]]; then
                  _rlabel="next from queue"
                elif [[ "$_reffective" == "queue-redo" ]]; then
                  _rnext="${PROMPTS[$i]}"; _rlabel="redo (ready idle)"
                fi
                ;;
              redo)
                _rnext="${PROMPTS[$i]}"; _rlabel="redo (ready idle)"
                ;;
            esac
            if [[ -n "$_rnext" ]]; then
              log "[pane $i $_rlane] ready/idle for $(( now - _ready_started ))s; sending $_rlabel"
              if send_prompt_to_pane "$target" "$_rnext"; then
                ITERATION_STARTED[$i]=$now
              else
                log "[pane $i $_rlane] ready/idle retry UNCONFIRMED"
                if (( RESPAWN_ON_GOAL_DONE )); then
                  respawn_pane_and_prompt "$i" "$_rnext" "ready/idle retry unconfirmed"
                else
                  ITERATION_STARTED[$i]=$now
                fi
              fi
            fi
          fi
        fi
        # Pane has no active timer and no visible "Goal achieved" text.
        # For CONTINUOUS_LANES panes in ? state (codex exited, bash prompt):
        # codex may have completed quietly (fast IDLE) without the poll ever
        # seeing "Goal achieved". Respawn after grace period.
        local _clc; _clc=$(printf '%s' "${LANE_LABELS[$i]}" | tr '[:upper:]' '[:lower:]')
        if [[ "$CONTINUOUS_LANES" == "*" || " $CONTINUOUS_LANES " == *" $_clc "* ]]; then
          local _cstate; _cstate="${_idle_state:-$(classify_capture_state "$cap")}"
          local _cstarted=${ITERATION_STARTED[$i]:-0}
          if [[ "$_cstate" == "?" ]] && (( _cstarted > 0 )) \
             && (( now - _cstarted >= RESEND_GRACE_SECS )); then
            local _cnext; _cnext=$(pop_next_task "${LANE_LABELS[$i]}") || true
            [[ -z "$_cnext" ]] && _cnext="${PROMPTS[$i]}"
            local _cram; _cram=$(free_ram_mb)
            local _cdisk; _cdisk=$(free_gb_on_cwd)
            if (( _cram >= MIN_FREE_RAM_MB )) && (( _cdisk >= MIN_FREE_GB )); then
              log "[pane $i ${LANE_LABELS[$i]}] continuous lane in ? state (quiet exit); respawning"
              terminate_pane_process_tree "$target" "pane $i ${LANE_LABELS[$i]} before continuous respawn"
              local _pane_cmd; _pane_cmd=$(codex_command_for_pane "$i") || return
              tmux respawn-pane -k -t "$target" "$_pane_cmd"
              ( wait_ready_and_send "$i" "$_cnext" ) &
              ITERATION_STARTED[$i]=$now
            fi
          fi
        fi
      fi
      # end: auto-resend block
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

reconcile_live_panes_with_prompts() {
  local want="${#PROMPTS[@]}" have="${#PANE_IDX[@]}" j target
  if (( have == want )); then
    return 0
  fi

  if (( have > want )); then
    log "live pane count ${have} exceeds prompt count ${want}; removing $((have - want)) stale extra pane(s)"
    for ((j=have - 1; j>=want; j--)); do
      target="$SESSION:0.${PANE_IDX[$j]}"
      terminate_pane_process_tree "$target" "stale extra pane ${PANE_IDX[$j]} beyond prompt count"
      tmux kill-pane -t "$target" 2>/dev/null || true
    done
    populate_pane_idx_from_running
    apply_even_grid
    apply_pane_titles
    (( ${#PANE_IDX[@]} == want )) && return 0
  fi

  log "live pane count ${#PANE_IDX[@]} does not match prompt count ${want}; rebuild required"
  return 1
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

# Pop the first non-blank, non-comment line from one queue file.
pop_next_task_file() {
  local file="$1"
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

# Pop the next task for a lane. Fixed/specified lanes read codex-tasks/<lane>.txt.
# Dynamic worker lanes first honor a worker-specific queue, then shared open
# queues such as codex-tasks/open.txt. This keeps lane-specific work scoped
# while letting the N worker pool take any unassigned open task.
pop_next_task() {
  local lane="$1" lane_lc file token token_lc
  resolve_tasks_dir
  [[ -n "$TASKS_DIR" && -d "$TASKS_DIR" ]] || return 1
  lane_lc=$(printf '%s' "$lane" | tr '[:upper:]' '[:lower:]')

  if lane_is_dynamic_worker "$lane"; then
    for token in $BLOCKER_QUEUE_LANES; do
      [[ -n "$token" ]] || continue
      token_lc=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
      if pop_next_task_file "$TASKS_DIR/${token_lc}.txt"; then return 0; fi
    done
    for file in "$TASKS_DIR/${lane_lc}.txt" "$TASKS_DIR/${lane}.txt"; do
      if pop_next_task_file "$file"; then return 0; fi
    done
    for token in $DYNAMIC_QUEUE_LANES; do
      [[ -n "$token" ]] || continue
      token_lc=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
      for blocker_token in $BLOCKER_QUEUE_LANES; do
        [[ "$token_lc" == "$(printf '%s' "$blocker_token" | tr '[:upper:]' '[:lower:]')" ]] && continue 2
      done
      if pop_next_task_file "$TASKS_DIR/${token_lc}.txt"; then return 0; fi
    done
    return 1
  fi

  file="$TASKS_DIR/${lane_lc}.txt"
  [[ -f "$file" ]] || file="$TASKS_DIR/${lane}.txt"
  pop_next_task_file "$file"
}

cleanup_session() {
  log "shutting down session '$SESSION'"
  terminate_session_process_trees
  tmux kill-session -t "$SESSION" 2>/dev/null || true
  reap_orphan_mcps
  # Also kill any stale supervisor daemons (other than ourselves). Each
  # `start` forks a daemon; without this they accumulate across restarts
  # and fight over the same panes.
  reap_stale_daemons
  # Drop the per-session state file so a fresh `start` can rediscover.
  rm -f "$STATE_FILE" "$DAEMON_PID_FILE" 2>/dev/null
}

daemon_cmd_matches_session() {
  local cmd="$1"
  printf '%s' "$cmd" | grep -q -- "--daemon" || return 1
  if printf '%s' "$cmd" | grep -qE "[-]-session[[:space:]]+${SESSION}([[:space:]]|\$)"; then
    return 0
  fi
  if [[ "$SESSION" == "codex-supervisor" ]] \
     && ! printf '%s' "$cmd" | grep -qE "[-]-session"; then
    return 0
  fi
  return 1
}

supervisor_daemon_pids() {
  local self="$$" parent pid saved cmd
  parent=$(ps -o ppid= -p "$self" 2>/dev/null | tr -d ' ')
  saved=$(cat "$DAEMON_PID_FILE" 2>/dev/null || true)
  if [[ -n "$saved" && "$saved" =~ ^[0-9]+$ \
        && "$saved" != "$self" && "$saved" != "$parent" ]] \
     && kill -0 "$saved" 2>/dev/null; then
    cmd=$(ps -p "$saved" -o command= 2>/dev/null || true)
    if daemon_cmd_matches_session "$cmd"; then
      printf '%s\n' "$saved"
      return 0
    fi
  fi

  local found=1
  local pids=() ppids=() line ppid root has_parent idx j
  while read -r pid ppid cmd; do
    [[ -n "${pid:-}" && -n "${ppid:-}" && -n "${cmd:-}" ]] || continue
    [[ "$pid" == "$self" || "$pid" == "$parent" ]] && continue
    [[ "$cmd" == *"codex-supervisor.sh"* ]] || continue
    daemon_cmd_matches_session "$cmd" || continue
    pids+=("$pid")
    ppids+=("$ppid")
  done < <(ps -axo pid=,ppid=,command= 2>/dev/null || true)

  # Bash background subshells inherit the original script command line, so
  # `ps` makes prompt-sender helper jobs look exactly like daemons. Keep only
  # root daemon processes by dropping any candidate whose parent is another
  # matching candidate.
  for idx in "${!pids[@]}"; do
    root=1
    for j in "${!pids[@]}"; do
      if [[ "${ppids[$idx]}" == "${pids[$j]}" ]]; then
        root=0
        break
      fi
    done
    (( root )) || continue
    printf '%s\n' "${pids[$idx]}"
    found=0
  done
  return "$found"
}

# Kill any other codex-supervisor daemon processes for this session,
# excluding the current process tree.
reap_stale_daemons() {
  local n=0 killed_pids=()
  for pid in $(supervisor_daemon_pids); do
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

fork_supervisor_daemon() {
  local mode="${1:-fresh}"
  local fork_args=("start" "--daemon" "--session" "$SESSION")
  [[ "$mode" == "reattach" ]] && fork_args+=("--reattach")
  [[ -n "$PROMPTS_FILE" ]] && fork_args+=("--prompts" "$PROMPTS_FILE")
  log "forking supervisor daemon${mode:+ ($mode)}..."
  # 2026-05-15: daemon stderr was previously redirected to /dev/null, hiding
  # silent `exit 1` paths (resource-budget refusals, tmux failures, syntax
  # errors). Send stderr to a sibling .stderr.log alongside the main log so
  # post-mortems are possible.
  local _stderr_log="${LOG_FILE%.log}.stderr.log"
  mkdir -p "$(dirname "$_stderr_log")" 2>/dev/null || true
  nohup bash "$0" "${fork_args[@]}" >/dev/null 2>>"$_stderr_log" &
  local daemon_pid=$!
  mkdir -p "$(dirname "$DAEMON_PID_FILE")" 2>/dev/null || true
  printf '%s\n' "$daemon_pid" > "$DAEMON_PID_FILE" 2>/dev/null || true
  disown "$daemon_pid" 2>/dev/null || true
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

cpu_count() {
  sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}

load1() {
  python3 - <<'PY' 2>/dev/null || uptime | sed -E 's/.*load averages?: ([0-9.]+).*/\1/'
import os
try:
    print(os.getloadavg()[0])
except (AttributeError, OSError):
    print(0)
PY
}

cpu_load_headroom_panes() {
  python3 - "$1" "$2" "$MAX_LOAD_PER_CPU" <<'PY'
import math
import sys

try:
    cpus = max(1, int(float(sys.argv[1])))
    load = max(0.0, float(sys.argv[2]))
    limit = float(sys.argv[3])
except Exception:
    print(0)
    raise SystemExit(0)

if limit <= 0:
    print(999999)
else:
    print(max(0, int(math.floor(cpus * limit - load))))
PY
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
  local free_ram free_disk need_ram need_disk_gb extra_disk_gb cpus load load_room

  free_ram=$(free_ram_mb)
  free_disk=$(free_gb_on_runtime_root)
  cpus=$(cpu_count)
  load=$(load1)
  load_room=$(cpu_load_headroom_panes "$cpus" "$load")
  need_ram=$(( MIN_FREE_RAM_MB + pane_count * RAM_MB_PER_PANE ))
  extra_disk_gb=$(ceil_div "$(( pane_count * DISK_MB_PER_PANE ))" 1024)
  need_disk_gb=$(( MIN_FREE_GB + extra_disk_gb ))

  if [[ "$MAX_LOAD_PER_CPU" != "0" && "$MAX_LOAD_PER_CPU" != "0.0" ]] && (( pane_count > load_room )); then
    err "not enough CPU/load headroom to start ${pane_count} pane(s): load=${load} on ${cpus} CPU(s), capacity for ${load_room} new pane(s) at ${MAX_LOAD_PER_CPU} load/CPU"
    err "start fewer panes, let current jobs settle, move lanes to a remote host, or set CODEX_SUPERVISOR_MAX_LOAD_PER_CPU=0 if another scheduler owns CPU"
    return 1
  fi

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
    log "resource budget ok for ${pane_count} panes: load=${load}/${cpus} CPU(s) (room ${load_room}), ${free_ram}MB RAM free (need ${need_ram}MB), ${free_disk}G disk free (need ${need_disk_gb}G), startup stagger $(effective_start_stagger_secs "$pane_count")s"
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

# Count panes across ALL tmux servers (sockets) for the current user
# (excluding the current session, since its prior tmux instance will be
# replaced). With per-session sockets each session has its own server, so
# `tmux ls` on our own socket can't see peer sessions — we must enumerate
# every csup-managed socket and ask each.
count_node_panes_excluding_self() {
  local total=0 self_socket="$TMUX_SOCKET" sock_dir sock panes sess
  # tmux puts sockets in $TMUX_TMPDIR/tmux-$UID/ (default $TMUX_TMPDIR=/tmp)
  sock_dir="${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)"
  [[ -d "$sock_dir" ]] || { echo 0; return; }
  for sock in "$sock_dir"/*; do
    [[ -S "$sock" ]] || continue
    local sname; sname=$(basename "$sock")
    # Skip our own socket: this session's prior tmux instance is about to be
    # replaced by the start. In shared mode the self_socket is empty so we
    # fall through to filtering by session name below.
    if [[ -n "$self_socket" && "$sname" == "$self_socket" ]]; then
      continue
    fi
    while IFS= read -r sess_panes; do
      local s_name; s_name="${sess_panes%%:*}"
      local s_count; s_count="${sess_panes#*:}"
      # In shared mode (or unsharded sockets) also filter the self session by name.
      if [[ -z "$self_socket" || "$self_socket" == "shared" ]] \
         && [[ "$s_name" == "$SESSION" ]]; then
        continue
      fi
      total=$(( total + s_count ))
    done < <(command tmux -L "$sname" list-sessions -F '#{session_name}:#{session_attached_or_zero}' 2>/dev/null \
             | while IFS= read -r line; do
                 local nm; nm="${line%%:*}"
                 local n; n=$(command tmux -L "$sname" list-panes -t "$nm" 2>/dev/null | wc -l | tr -d ' ')
                 echo "$nm:${n:-0}"
               done)
  done
  echo "$total"
}

# Refuse to add a new session if the node-wide pane count would exceed the
# safe ceiling. RLIMIT_NPROC on LUNARC is 4096 and each pane spawns ~4-8
# processes, so 40 panes/node keeps headroom even under peak respawn.
ensure_node_pane_budget() {
  local incoming="${1:-${#PROMPTS[@]}}"
  (( NODE_MAX_PANES <= 0 )) && return 0
  local existing; existing=$(count_node_panes_excluding_self)
  local total=$(( existing + incoming ))
  if (( total > NODE_MAX_PANES )); then
    err "node pane budget exceeded: ${existing} existing pane(s) + ${incoming} new = ${total} > ${NODE_MAX_PANES} (CODEX_SUPERVISOR_NODE_MAX_PANES)"
    err "reduce panes per session, stop an idle session, or raise CODEX_SUPERVISOR_NODE_MAX_PANES only if RLIMIT_NPROC allows"
    return 1
  fi
  if (( incoming >= 4 )); then
    log "node pane budget ok: ${existing} existing + ${incoming} new = ${total}/${NODE_MAX_PANES}"
  fi
  return 0
}

# Path to the node-wide startup lock. One per host so each compute node has
# its own serialization point.  Use shared scratch on LUNARC (where /tmp may
# be node-local but the supervisor may be invoked from any node), else /tmp.
node_start_lock_path() {
  local node base
  node=$(hostname -s 2>/dev/null || hostname)
  if [[ -d "/local" && -w "/local" ]]; then
    base="/local/codex-supervisor-${USER:-unknown}"
  else
    base="${TMPDIR:-/tmp}/codex-supervisor-${USER:-unknown}"
  fi
  mkdir -p "$base" 2>/dev/null || true
  echo "$base/start-lock.${node}"
}

# Acquire a node-wide startup lock so only one supervisor at a time runs the
# create-panes+send-prompts phase. Prevents the parallel-bootstrap fork burst
# that today crashed 24 panes at startup with "pthread_create: Resource
# temporarily unavailable". flock with NODE_START_LOCK_SECS timeout; if the
# lock can't be acquired in that window the caller proceeds anyway (better
# overlapping startup than a deadlock).
acquire_node_start_lock() {
  (( NODE_START_LOCK_SECS <= 0 )) && return 0
  command -v flock >/dev/null 2>&1 || return 0
  local lock; lock=$(node_start_lock_path)
  exec 9>"$lock" 2>/dev/null || return 0
  if flock -w "$NODE_START_LOCK_SECS" 9; then
    log "node start lock acquired: $lock"
    return 0
  fi
  log "WARNING: could not acquire node start lock within ${NODE_START_LOCK_SECS}s; proceeding without serialisation"
  return 0
}

release_node_start_lock() {
  exec 9>&- 2>/dev/null || true
}

# Prune git worktrees not actively in use, plus npm caches, plus old
# Claude Code session tmp dirs. Idempotent. Safe to run while supervisor
# is running (only touches state outside the live tmux session).
cmd_cleanup() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --global) GLOBAL_CLEANUP=1; shift ;;
      *) err "cleanup: unknown arg $1"; return 1 ;;
    esac
  done
  local before after freed
  before=$(free_gb_on_cwd)
  log "cleanup: starting ($before G free on $(pwd); scope=$(cleanup_global_enabled && echo global || echo project))"

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

  # 2) npm cache. Safe; re-downloads on demand, but global to all projects.
  if cleanup_global_enabled; then
    rm -rf "$HOME/.npm/_cacache" 2>/dev/null
  fi

  # 3) Old Claude Code session tmp dirs (>24h). The harness writes per-tool
  #    output here; old session UUIDs sit forever otherwise.
  if cleanup_global_enabled && [[ -d "$TMP_SWEEP_ROOT/claude-501" ]]; then
    find "$TMP_SWEEP_ROOT/claude-501" -mindepth 2 -maxdepth 2 -type d -mmin +1440 \
      -exec rm -rf {} + 2>/dev/null
  fi

  # 4) Codex worktree leftovers in /private/tmp. Codex creates per-task
  #    worktrees here that aren't always cleaned up. We've seen 60+
  #    accumulate. Skip /private/tmp/<repo>-saved-before by convention
  #    (those are user-saved snapshots).
  find "$TMP_SWEEP_ROOT" -maxdepth 1 -type d -name '*-*' -mmin +60 2>/dev/null | while read -r wt; do
    case "$(basename "$wt")" in
      *-saved-before|claude-501) continue ;;
    esac
    cleanup_path_in_project_scope "$wt" || cleanup_git_worktree_in_current_repo "$wt" || continue
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
  if [[ -d "$SUPERPOWERS_WORKTREES_ROOT" ]]; then
    find_project_scoped_children "$SUPERPOWERS_WORKTREES_ROOT" 2 2 1440 | while read -r wt; do
      log "cleanup: removing stale superpowers worktree $wt"
      rm -rf "$wt"
    done
  fi

  # 6) Sibling per-pane clones in ~/Desktop/projects/<repo>-* that aren't
  #    git worktrees (orphaned codex per-pane copies).
  find "$PROJECTS_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*-*' -mmin +1440 2>/dev/null | while read -r d; do
    cleanup_path_in_project_scope "$d" || continue
    # Skip if it's the main repo or a registered worktree
    [[ -e "$d/.git" ]] || continue
    if [[ -d "$d/.git" ]]; then continue; fi   # main checkout has .git/ as dir
    log "cleanup: removing orphan sibling clone $d"
    rm -rf "$d"
  done

  # 7) Build caches. Project-scoped by default; --global scans all projects.
  local cache_root
  if cleanup_global_enabled; then cache_root="$PROJECTS_ROOT"; else cache_root="$(current_project_root)"; fi
  if [[ -d "$cache_root" ]]; then
    for cachedir in $(find "$cache_root" -maxdepth 3 -type d \( -name '.next' -o -name '.turbo' -o -name 'dist' \) -mmin +720 2>/dev/null); do
      cleanup_global_enabled || cleanup_path_under_current_project "$cachedir" || continue
      rm -rf "$cachedir" 2>/dev/null
    done
  fi

  # 8) Homebrew cache + downloads.
  if cleanup_global_enabled && command -v brew >/dev/null 2>&1; then
    brew cleanup --prune=all >/dev/null 2>&1 || true
  fi

  # 9) Time Machine local snapshots. Often the silent killer on macOS.
  #    Try without sudo first; if it fails the user can rerun by hand.
  if cleanup_global_enabled && command -v tmutil >/dev/null 2>&1; then
    tmutil deletelocalsnapshots / >/dev/null 2>&1 || true
  fi

  # 10) Codex CLI log directory. THIS IS THE #1 DISK EATER. Observed at 34 GB
  #     on a single Mac mini after ~24h of 8-pane operation. Codex writes
  #     verbose per-turn JSONL here; safe to wipe — codex regenerates as it
  #     runs. We empty the directory but keep the dir itself so codex's
  #     in-flight handle stays valid.
  if cleanup_global_enabled && [[ -d "$HOME/.codex/log" ]]; then
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
  if cleanup_global_enabled && (( CODEX_SESSIONS_RETAIN_DAYS > 0 )) && [[ -d "$HOME/.codex/sessions" ]]; then
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
  cleanup_global_enabled && command -v uv >/dev/null 2>&1 && uv cache prune --ci >/dev/null 2>&1 || true

  # 14) npm _npx cache. Codex spawns `npx` heavily; npx caches whole node
  #     project trees here. Safe to wipe.
  cleanup_global_enabled && rm -rf "$HOME/.npm/_npx" 2>/dev/null

  # 15) macOS-specific app caches that codex/playwright/claude write.
  if cleanup_global_enabled && [[ -d "$HOME/Library/Caches/com.openai.codex" ]]; then
    find "$HOME/Library/Caches/com.openai.codex" -mindepth 1 -delete 2>/dev/null
  fi

  after=$(free_gb_on_cwd)
  freed=$((after - before))
  log "cleanup: done ($after G free on $(pwd); ${freed}G recovered)"
  echo "cleanup: ${after}G free (${freed}G recovered)"
}

cmd_start() {
  local attach_after=1 daemon_mode=0 reattach_mode=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-attach) attach_after=0; shift ;;
      --prompts)   PROMPTS_FILE="$2"; shift 2 ;;
      --session)   SESSION="$2"; shift 2 ;;
      --daemon)    daemon_mode=1; shift ;;   # internal: do the actual work
      --reattach)  reattach_mode=1; shift ;; # internal: daemon adopts existing tmux panes
      *) err "start: unknown arg $1"; return 1 ;;
    esac
  done
  refresh_session_paths
  _resolve_tmux_socket

  # Kill-switch: refuse to start if the user has disabled this session
  # (or all sessions). Removing the file re-enables. This prevents stale
  # daemons / launchd jobs / scripts from silently resurrecting a session
  # the user explicitly stopped.
  if [[ -f "$HOME/.codex-supervisor.disabled" ]]; then
    err "refusing to start: $HOME/.codex-supervisor.disabled exists (global kill-switch)"
    err "remove that file to re-enable the supervisor"
    exit 1
  fi
  # Pre-2026-05-15 this flag lived in $HOME which is quota-tight on LUNARC.
  # Now lives in SUPERVISOR_ROOT/run/ (under fs10 on lunarc, ~/.codex-supervisor
  # on Mac). The old path is checked for back-compat.
  local _disabled_new="$SUPERVISOR_ROOT/run/${SESSION}.disabled"
  local _disabled_old="$HOME/.codex-supervisor-${SESSION}.disabled"
  if [[ -f "$_disabled_new" ]] || [[ -f "$_disabled_old" ]]; then
    err "refusing to start session '$SESSION': $_disabled_new exists (or legacy $_disabled_old)"
    err "remove that file to re-enable this session"
    exit 1
  fi

  # If we're invoked with --daemon, skip the launcher fork and just run.
  # Self-restart loop: if _start_supervisor_main exits with a non-zero code
  # (crash), wait 5 s and try again without killing the live tmux session.
  # A clean stop (INT/TERM) exits 0 and breaks the loop immediately.
  #
  # IMPORTANT: _start_supervisor_main calls `exit 1` for transient resource
  # failures (lock acquisition, budget checks, tmux pane creation) and
  # `exit 2` from the ERR trap on a crash. `exit` in bash terminates the
  # entire process, which would kill THIS while loop. Run it in a subshell
  # so the exit is scoped — the subshell dies, the outer loop survives.
  if (( daemon_mode )); then
    local _restart_count=0 _rc=0
    (( reattach_mode )) && _restart_count=1
    while true; do
      ( _start_supervisor_main "$_restart_count" )
      _rc=$?
      (( _rc == 0 )) && break   # clean stop — don't restart
      _restart_count=$(( _restart_count + 1 ))
      if (( _restart_count > 20 )); then
        log "daemon crashed $_restart_count times consecutively; giving up"
        break
      fi
      # Exponential backoff: transient resource issues clear on their own,
      # but persistent failure shouldn't burn fork() at 5s intervals.
      local _backoff=$(( 5 * (_restart_count < 6 ? 1 : (_restart_count < 12 ? 3 : 6)) ))
      log "daemon crashed (exit $_rc); restart #$_restart_count in ${_backoff}s..."
      sleep "$_backoff"
    done
    return
  fi

  ensure_codex_cmd
  command -v tmux >/dev/null || { err "tmux not on PATH"; exit 1; }
  local first_word; first_word=$(command_name_from_shell_command)
  command -v "$first_word" >/dev/null || { err "$first_word not on PATH"; exit 1; }

  if ! acquire_session_start_lock; then
    err "could not acquire start lock for session '$SESSION'"
    exit 1
  fi

  local session_running=0
  tmux has-session -t "=$SESSION" 2>/dev/null && session_running=1
  if (( ! session_running )); then
    load_prompts
    if ! ensure_start_resource_budget; then
      release_session_start_lock
      exit 1
    fi
    # Cross-session pane budget. Multiple supervisors on the same node share
    # RLIMIT_NPROC; this check refuses a new session when the total pane count
    # would push the node into the territory where panes crash with
    # "pthread_create: Resource temporarily unavailable" at startup.
    if ! ensure_node_pane_budget; then
      release_session_start_lock
      exit 1
    fi
    # Disk-space guard. Each pane is a worktree + node_modules + node MCP tree;
    # a fresh start on a near-full disk has historically crashed the daemon
    # mid-spin and orphaned MCP children. Refuse early instead.
    if ! ensure_disk_space; then
      release_session_start_lock
      exit 1
    fi
  fi

  # Don't double-launch: if a session of this name is already up, ensure it
  # still has a monitor daemon. Older `start` calls reaped the daemon and then
  # only attached, leaving panes frozen at Ready/Done forever. The start lock
  # covers the re-check + fork so concurrent `csup start` calls cannot all see
  # "missing daemon" and fork competing monitors for the same tmux panes.
  if (( session_running )); then
    if supervisor_daemon_pids >/dev/null; then
      log "session '$SESSION' already running with monitor daemon; attaching"
    else
      log "session '$SESSION' already running but monitor daemon is missing; re-attaching daemon"
      fork_supervisor_daemon "reattach"
    fi
  else
    # Reap stale daemon processes from prior runs only when replacing a missing
    # tmux session. Reaping during an idempotent `start` would kill the healthy
    # monitor for an existing session.
    reap_stale_daemons
    # Fork ourselves as a background daemon. nohup + &  + disown means the
    # daemon survives even when the launcher window closes. Pass --daemon so
    # the forked invocation skips this branch and runs _start_supervisor_main.
    fork_supervisor_daemon "fresh"

    # Wait for the daemon to spin the tmux session up.
    local i
    for ((i=0; i<60; i++)); do
      tmux has-session -t "=$SESSION" 2>/dev/null && break
      sleep 1
    done
    if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
      release_session_start_lock
      err "daemon did not bring up session within 60s; check $LOG_FILE"
      exit 1
    fi
  fi
  release_session_start_lock

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
  mkdir -p "$(dirname "$DAEMON_PID_FILE")" 2>/dev/null || true
  printf '%s\n' "$$" > "$DAEMON_PID_FILE" 2>/dev/null || true

  if (( _is_restart )); then
    log "daemon restart #$_is_restart: re-attaching to session '$SESSION'"
    populate_pane_idx_from_running
    if tmux has-session -t "=$SESSION" 2>/dev/null && (( ${#PANE_IDX[@]} > 0 )); then
      reconcile_live_panes_with_prompts || PANE_IDX=()
    fi
    if ! tmux has-session -t "=$SESSION" 2>/dev/null || (( ${#PANE_IDX[@]} == 0 )); then
      log "session gone or empty — rebuilding from scratch"
      ensure_start_resource_budget || exit 1
      ensure_node_pane_budget || exit 1
      write_state_file
      acquire_node_start_lock
      create_tmux_session_panes 1 || { release_node_start_lock; exit 1; }
      # Release the lock BEFORE prompt_all_panes spawns background subshells.
      # Those subshells would inherit fd 9 and hold the node-wide lock for the
      # full ready-wait window (up to READY_TIMEOUT per pane), blocking peer
      # sessions far longer than the pane-creation phase actually needs.
      release_node_start_lock
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
    ensure_node_pane_budget || exit 1
    write_state_file
    acquire_node_start_lock
    create_tmux_session_panes 1 || { release_node_start_lock; exit 1; }
    log "session '$SESSION': ${#PROMPTS[@]} panes (lanes: ${LANE_LABELS[*]})"
    log "prompts: $PROMPTS_FILE"
    # Release before prompt_all_panes — see comment above on subshell inheritance.
    release_node_start_lock
    prompt_all_panes
  fi

  log "all panes prompted; entering poll loop (every ${POLL_INTERVAL}s)"
  local last_periodic_cleanup=$(date +%s)
  while true; do
    sleep "$POLL_INTERVAL"
    # If the tmux session is gone unexpectedly, rebuild it instead of
    # abandoning the team. `cmd_stop` terminates this daemon before/while
    # killing tmux, so explicit stops still stay stopped.
    if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
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
  if (( kill_existing )); then
    terminate_session_process_trees
    tmux kill-session -t "$SESSION" 2>/dev/null || true
  fi
  local pane_cmd
  pane_cmd=$(codex_command_for_pane 0) || return 1
  # Ensure a tmux server is up with the right options BEFORE creating our
  # session. Without this, a freshly-started server has exit-empty=on
  # (default) which racy-exits if our new session dies during the spawn
  # window. ensure_sentinel_session also creates a permanent placeholder
  # session that holds the server up across transient empty states.
  ensure_sentinel_session
  # CRITICAL: close fd 9 (node start lock) for this command. tmux new-session
  # forks the tmux server, which would otherwise inherit fd 9 and hold the
  # node-wide lock for the entire server lifetime — blocking every other
  # supervisor session on the node indefinitely. The bash process still owns
  # fd 9; only the forked tmux server is denied inheritance.
  tmux new-session -d -s "$SESSION" -x "$(tmux_window_x)" -y "$(tmux_window_y)" "$pane_cmd" 9<&-
  # Some cluster/login environments set tmux base-index=1. The supervisor and
  # dashboard intentionally use window 0 as the stable session window, so move
  # the newly created window to 0 before any split/capture operations.
  local first_window
  first_window=$(tmux display-message -p -t "$SESSION" '#{window_index}' 2>/dev/null || printf '0')
  if [[ "$first_window" != "0" ]]; then
    tmux move-window -s "$SESSION:$first_window" -t "$SESSION:0" 2>/dev/null || true
  fi
  apply_tmux_config

  local i start_stagger
  start_stagger=$(effective_start_stagger_secs "${#PROMPTS[@]}")
  for ((i=1; i<${#PROMPTS[@]}; i++)); do
    pane_cmd=$(codex_command_for_pane "$i") || return 1
    tmux split-window -t "$SESSION:0" "$pane_cmd"
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
  # Cross-session pane budget gate: if the node is still saturated from peer
  # sessions (the most likely reason this session crashed in the first place),
  # defer the recreate so we don't trigger another fork-burst cascade.
  if ! ensure_node_pane_budget; then
    log "recreate deferred: node pane budget exceeded; will retry next poll"
    return 1
  fi
  acquire_node_start_lock
  if ! create_tmux_session_panes 0; then
    release_node_start_lock
    log "recreate failed: could not rebuild tmux panes"
    return 1
  fi
  log "recreated tmux session '$SESSION'; re-sending ${#PROMPTS[@]} prompt(s)"
  # Release before prompt_all_panes — see comment in cmd_start re. subshell
  # inheritance of fd 9 holding the lock across the full ready-wait window.
  release_node_start_lock
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
  tmux has-session -t "=$SESSION" 2>/dev/null && was_running=1
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
  # 2026-05-15: moved this flag from $HOME (quota-tight on LUNARC) into
  # SUPERVISOR_ROOT/run/ which is operator-configurable to fs10 share.
  if (( mark_disabled )); then
    mkdir -p "$SUPERVISOR_ROOT/run" 2>/dev/null || true
    : > "$SUPERVISOR_ROOT/run/${SESSION}.disabled"
  fi
  if (( was_running )); then
    echo "stopped session '$SESSION', reaped orphan MCP children, pruned worktrees"
  else
    echo "no session '$SESSION' running; reaped any leftover MCP orphans + pruned worktrees"
  fi
  if (( mark_disabled )); then
    echo "marked DISABLED ($SUPERVISOR_ROOT/run/${SESSION}.disabled). Remove that file or pass --no-disable next stop to re-enable."
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
  find "$TMP_SWEEP_ROOT" -maxdepth 1 -type d -name '*-*' -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" 2>/dev/null | while read -r d; do
    case "$(basename "$d")" in
      *-saved-before|claude-501) continue ;;
    esac
    cleanup_path_in_project_scope "$d" || cleanup_git_worktree_in_current_repo "$d" || continue
    rm -rf "$d" 2>/dev/null
  done

  # 3) Stale superpowers worktree dirs not registered (mmin +PERIODIC).
  # `~/.config/superpowers/worktrees` may be a symlink to MyDrive — find -L
  # follows symlinks so MyDrive contents get swept just like local would.
  if [[ -e "$SUPERPOWERS_WORKTREES_ROOT" ]]; then
    find_project_scoped_children "$SUPERPOWERS_WORKTREES_ROOT" 2 2 "$PERIODIC_WORKTREE_AGE_MIN" | while read -r d; do
      rm -rf "$d" 2>/dev/null
    done
  fi

  # 3b) Direct MyDrive paths. Scoped by project unless global cleanup is opted in.
  for d in "$MYDRIVE_SUPERPOWERS_WORKTREES_ROOT" "$ACTIONS_RUNNER_WORK_ROOT"; do
    [[ -d "$d" ]] || continue
    find_project_scoped_children "$d" 2 2 "$PERIODIC_WORKTREE_AGE_MIN" | while read -r scoped; do
      rm -rf "$scoped" 2>/dev/null
    done
  done

  # 4) Orphan sibling clones in ~/Desktop/projects/<repo>-*.
  find "$PROJECTS_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*-*' -mmin +"${PERIODIC_WORKTREE_AGE_MIN}" 2>/dev/null | while read -r d; do
    cleanup_path_in_project_scope "$d" || continue
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
      [[ "$ppid" == "1" ]] && cleanup_process_in_project_scope "$p" && kill -TERM "$p" 2>/dev/null && kc=$((kc+1))
    done < <(pgrep -f "$pat" 2>/dev/null)
  done
  # npm-exec / npm-cli orphans (parent gone). pgrep -f matches the long
  # node /path/to/npm-cli.js form codex spawns.
  while read -r p; do
    [[ -z "$p" ]] && continue
    ppid=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [[ "$ppid" == "1" ]] && cleanup_process_in_project_scope "$p" && kill -TERM "$p" 2>/dev/null && kc=$((kc+1))
  done < <(pgrep -f "npm-cli.js\|npm exec" 2>/dev/null)
  (( kc > 0 )) && log "periodic cleanup: killed $kc orphan dev/test procs"

  # 6) HIBEAM/babbloo/weather-market scratch dirs in /private/tmp older
  #    than 1 day. These came from physics + research scratchpads and
  #    never get reclaimed otherwise.
  find "$TMP_SWEEP_ROOT" -maxdepth 1 -type d \
    \( -name 'HIBEAM_*' -o -name 'babbloo-*' -o -name 'wm-*' \) \
    -mtime +1 2>/dev/null | while read -r d; do
      cleanup_path_in_project_scope "$d" || continue
      rm -rf "$d" 2>/dev/null
    done

  # 7) uv cache prune (Python tool). 6 GB+ accumulates from agent venvs.
  #    --ci keeps recently used wheels but drops stale ones. Cheap enough
  #    to run every cleanup tick.
  cleanup_global_enabled && command -v uv >/dev/null 2>&1 && uv cache prune --ci >/dev/null 2>&1 &

  # 8) APFS local snapshots. macOS keeps Time Machine local snapshots
  #    indefinitely when the destination is offline; they hold space
  #    that df shows as "used" but is reclaimable.
  cleanup_global_enabled && command -v tmutil >/dev/null 2>&1 && \
    tmutil listlocalsnapshots / 2>/dev/null \
      | awk -F. '/com.apple.TimeMachine/{print $NF}' \
      | while read -r s; do
          [[ -z "$s" ]] && continue
          tmutil deletelocalsnapshots "$s" >/dev/null 2>&1 || true
        done

  # 9) Truncate macOS DiagnosticMessages older than 7 days. They grow
  #    silently to hundreds of MB.
  cleanup_global_enabled && find "$DIAGNOSTIC_MESSAGES_ROOT" -name '*.asl' -mtime +7 \
    -exec rm -f {} + 2>/dev/null

  # 10) Codex CLI log directory — capped at CODEX_LOG_MAX_GB. This is the
  #     single biggest disk eater for long-running supervisor sessions.
  #     Triggered ONLY when oversized; cheap when within bounds (one du call).
  if cleanup_global_enabled && (( CODEX_LOG_MAX_GB > 0 )) && [[ -d "$HOME/.codex/log" ]]; then
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
  if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
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
  if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
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
  if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
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
  if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
    err "no session '$SESSION' running"; return 1
  fi
  ensure_codex_cmd
  load_prompts
  populate_pane_idx_from_running
  local idx; idx=$(resolve_pane "$ref") || { err "no pane matches '$ref'"; return 1; }
  log "[pane ${PANE_IDX[$idx]} ${LANE_LABELS[$idx]:-?}] manual restart"
  local target pane_cmd; target="$(pane_target "$idx")"
  terminate_pane_process_tree "$target" "manual restart pane ${PANE_IDX[$idx]}"
  pane_cmd=$(codex_command_for_pane "$idx") || return 1
  tmux respawn-pane -k -t "$target" "$pane_cmd"
  ( wait_ready_and_send "$idx" "${PROMPTS[$idx]}" ) &
  echo "restarted pane ${PANE_IDX[$idx]}; prompt will be re-sent when ready"
}

cmd_relayout() {
  if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
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
