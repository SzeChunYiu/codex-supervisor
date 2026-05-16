#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/root/logs"

safe_log="$TMPDIR/supervisor.log"
unsafe_log="$TMPDIR/../supervisor.log"
long_log="$TMPDIR/$(printf "%05000d" 0 | tr 0 x).log"

resolved_paths="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_LOG="$safe_log" \
    bash -c 'source "$1"; printf "%s\n" "$LOG_FILE"' _ "$SCRIPT"
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_LOG="$unsafe_log" \
    bash -c 'source "$1"; printf "%s\n" "$LOG_FILE"' _ "$SCRIPT"
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_LOG="$long_log" \
    bash -c 'source "$1"; printf "%s\n" "$LOG_FILE"' _ "$SCRIPT"
)"

expected_paths="$safe_log
$TMPDIR/root/logs/codex-supervisor.log
$TMPDIR/root/logs/codex-supervisor.log"

if [[ "$resolved_paths" != "$expected_paths" ]]; then
  printf 'supervisor log env should preserve safe paths and reject traversal/oversized paths, got:\n%s\n' "$resolved_paths" >&2
  exit 1
fi

echo "ok: supervisor log env rejects traversal and oversized paths"
