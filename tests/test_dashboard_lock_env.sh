#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/root/run"

safe_lock="$TMPDIR/root/run/custom-dashboard.lock"
unsafe_lock="$TMPDIR/../victim"
long_lock="$TMPDIR/$(printf "%05000d" 0 | tr 0 x)"

resolved_paths="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR="$safe_lock" \
    bash -c 'source "$1"; printf "%s\n" "$DASHBOARD_LOCK_DIR"' _ "$SCRIPT"
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR="$unsafe_lock" \
    bash -c 'source "$1"; printf "%s\n" "$DASHBOARD_LOCK_DIR"' _ "$SCRIPT"
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
  CODEX_SUPERVISOR_DASHBOARD_LOCK_DIR="$long_lock" \
    bash -c 'source "$1"; printf "%s\n" "$DASHBOARD_LOCK_DIR"' _ "$SCRIPT"
)"

expected_paths="$safe_lock
$TMPDIR/root/run/csup-dashboard.lock
$TMPDIR/root/run/csup-dashboard.lock"

if [[ "$resolved_paths" != "$expected_paths" ]]; then
  printf 'dashboard lock env should preserve safe run-dir paths and reject traversal/oversized paths, got:\n%s\n' "$resolved_paths" >&2
  exit 1
fi

echo "ok: dashboard lock env is bounded to supervisor run dir"
