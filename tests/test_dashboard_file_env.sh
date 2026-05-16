#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/root/run" "$TMPDIR/root/logs"

safe_log="$TMPDIR/root/logs/custom-dashboard.log"
safe_pid="$TMPDIR/root/run/custom-dashboard.pid"
unsafe_log="$TMPDIR/outside-dashboard.log"
unsafe_pid="$TMPDIR/outside-dashboard.pid"
long_log="$TMPDIR/$(printf "%05000d" 0 | tr 0 x).log"
long_pid="$TMPDIR/$(printf "%05000d" 0 | tr 0 x).pid"

resolved_paths="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_DASHBOARD_LOG="$safe_log" \
  CODEX_SUPERVISOR_DASHBOARD_PID_FILE="$safe_pid" \
    bash -c 'source "$1"; printf "%s\n%s\n" "$DASHBOARD_LOG" "$DASHBOARD_PID_FILE"' _ "$SCRIPT"
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_DASHBOARD_LOG="$unsafe_log" \
  CODEX_SUPERVISOR_DASHBOARD_PID_FILE="$unsafe_pid" \
    bash -c 'source "$1"; printf "%s\n%s\n" "$DASHBOARD_LOG" "$DASHBOARD_PID_FILE"' _ "$SCRIPT"
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_DASHBOARD_LOG="$long_log" \
  CODEX_SUPERVISOR_DASHBOARD_PID_FILE="$long_pid" \
    bash -c 'source "$1"; printf "%s\n%s\n" "$DASHBOARD_LOG" "$DASHBOARD_PID_FILE"' _ "$SCRIPT"
)"

expected_paths="$safe_log
$safe_pid
$TMPDIR/root/logs/csup-dashboard.log
$TMPDIR/root/run/csup-dashboard.pid
$TMPDIR/root/logs/csup-dashboard.log
$TMPDIR/root/run/csup-dashboard.pid"

if [[ "$resolved_paths" != "$expected_paths" ]]; then
  printf 'dashboard file env should preserve safe root paths and reject outside/oversized paths, got:\n%s\n' "$resolved_paths" >&2
  exit 1
fi

echo "ok: dashboard pid/log env paths are bounded to supervisor runtime dirs"
