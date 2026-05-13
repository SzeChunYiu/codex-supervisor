#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
  bash -c '
    set -e
    source "$1"
    prepare_runtime_dirs
    test -d "$SUPERVISOR_ROOT/logs"
    test -d "$SUPERVISOR_ROOT/run"
    test -d "$SUPERVISOR_CACHE_ROOT/npm"
    test -d "$SUPERVISOR_CACHE_ROOT/uv"
    test -d "$SUPERVISOR_CACHE_ROOT/pip"
    test -d "$SUPERVISOR_TMP_ROOT"

    mkdir -p "$SUPERVISOR_CACHE_ROOT/npm/old" "$SUPERVISOR_CACHE_ROOT/npm/fresh" "$SUPERVISOR_TMP_ROOT/old" "$SUPERVISOR_TMP_ROOT/fresh"
    printf old > "$SUPERVISOR_CACHE_ROOT/npm/old/blob"
    printf fresh > "$SUPERVISOR_CACHE_ROOT/npm/fresh/blob"
    printf old > "$SUPERVISOR_TMP_ROOT/old/blob"
    printf fresh > "$SUPERVISOR_TMP_ROOT/fresh/blob"
    touch -t 202001010000 "$SUPERVISOR_CACHE_ROOT/npm/old" "$SUPERVISOR_CACHE_ROOT/npm/old/blob" "$SUPERVISOR_TMP_ROOT/old" "$SUPERVISOR_TMP_ROOT/old/blob"

    PERIODIC_WORKTREE_AGE_MIN=5
    prune_supervisor_runtime_dirs

    [[ ! -e "$SUPERVISOR_CACHE_ROOT/npm/old" ]]
    [[ ! -e "$SUPERVISOR_TMP_ROOT/old" ]]
    [[ -e "$SUPERVISOR_CACHE_ROOT/npm/fresh/blob" ]]
    [[ -e "$SUPERVISOR_TMP_ROOT/fresh/blob" ]]
  ' _ "$SCRIPT"
