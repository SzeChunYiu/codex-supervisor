#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

fork_file="$TMPDIR/forked"
reap_file="$TMPDIR/reaped"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_SESSION=demo-session \
FORK_FILE="$fork_file" \
REAP_FILE="$reap_file" \
bash -c '
  source "$1"
  command_name_from_shell_command() { echo true; }
  ensure_codex_cmd() { :; }
  refresh_session_paths() { :; }
  load_prompts() { :; }
  ensure_start_resource_budget() { :; }
  ensure_disk_space() { :; }
  ensure_dashboard() { :; }
  dashboard_url() { echo http://127.0.0.1:7777; }
  log() { :; }
  tmux() {
    case "$1" in
      has-session) return 0 ;;
      *) return 0 ;;
    esac
  }
  supervisor_daemon_pids() { return 1; }
  reap_stale_daemons() { echo reaped > "$REAP_FILE"; }
  fork_supervisor_daemon() { echo "$1" > "$FORK_FILE"; }
  cmd_start --no-attach >/dev/null
' _ "$SCRIPT"

if [[ "$(cat "$fork_file" 2>/dev/null || true)" != "reattach" ]]; then
  echo "start should fork a reattaching daemon when tmux session exists but monitor daemon is missing" >&2
  exit 1
fi
if [[ -e "$reap_file" ]]; then
  echo "start should not reap/kill daemons before deciding an existing session is unmonitored" >&2
  exit 1
fi

echo "ok: start recovers existing unmonitored sessions without killing active daemon"
