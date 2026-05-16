#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fork_file="$TMPDIR/forks"
session_file="$TMPDIR/session"
daemon_file="$TMPDIR/daemon"

run_start() {
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_SESSION=demo-session \
  FORK_FILE="$fork_file" \
  SESSION_FILE="$session_file" \
  DAEMON_FILE="$daemon_file" \
  bash -c '
    source "$1"
    command_name_from_shell_command() { echo true; }
    ensure_codex_cmd() { :; }
    load_prompts() { :; }
    ensure_start_resource_budget() { :; }
    ensure_disk_space() { :; }
    ensure_dashboard() { :; }
    dashboard_url() { echo http://127.0.0.1:7777; }
    log() { :; }
    tmux() {
      case "$1" in
        has-session)
          test -e "$SESSION_FILE"
          ;;
        *)
          return 0
          ;;
      esac
    }
    supervisor_daemon_pids() { [[ -e "$DAEMON_FILE" ]]; }
    reap_stale_daemons() { :; }
    fork_supervisor_daemon() {
      printf "%s\n" "$1" >> "$FORK_FILE"
      # Keep the first launcher inside the critical section long enough that
      # an unlocked implementation lets the second launcher race and fork too.
      sleep 0.4
      : > "$DAEMON_FILE"
      : > "$SESSION_FILE"
    }
    cmd_start --no-attach >/dev/null
  ' _ "$SCRIPT"
}

run_start &
p1=$!
run_start &
p2=$!
wait "$p1"
wait "$p2"

forks=$(wc -l < "$fork_file" | tr -d ' ')
if [[ "$forks" != "1" ]]; then
  echo "concurrent starts should fork exactly one daemon, saw $forks" >&2
  cat "$fork_file" >&2 || true
  exit 1
fi

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/root-lock" \
CODEX_SUPERVISOR_NODE_START_LOCK_SECS=bad \
bash -c '
  source "$1"
  log() { :; }
  acquire_node_start_lock
  release_node_start_lock
' _ "$SCRIPT"

echo "ok: concurrent start calls serialize daemon fork"
