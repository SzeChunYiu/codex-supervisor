#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"

cmd="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  MCP_MODE=off
  SUPERVISOR_CODEX_HOME="/tmp/csup-home"
  SUPERVISOR_CACHE_ROOT="/tmp/csup-cache"
  SUPERVISOR_TMP_ROOT="/tmp/csup-tmp"
  CODEX_BASE_CMD="codex"
  NICE_LEVEL=5
  build_codex_command
' _ "$SCRIPT")"

for expected in \
  "UV_THREADPOOL_SIZE='2'" \
  "OMP_NUM_THREADS='1'" \
  "OPENBLAS_NUM_THREADS='1'" \
  "MKL_NUM_THREADS='1'" \
  "NUMEXPR_NUM_THREADS='1'" \
  "VECLIB_MAXIMUM_THREADS='1'" \
  "TOKENIZERS_PARALLELISM='false'"; do
  if [[ "$cmd" != *"$expected"* ]]; then
    printf 'worker command should include resource cap %s\ncommand: %s\n' "$expected" "$cmd" >&2
    exit 1
  fi
done

cmd_override="$(CODEX_SUPERVISOR_TEST_SOURCE=1 CODEX_SUPERVISOR_UV_THREADPOOL_SIZE=1 bash -c '
  source "$1"
  MCP_MODE=off
  SUPERVISOR_CODEX_HOME="/tmp/csup-home"
  SUPERVISOR_CACHE_ROOT="/tmp/csup-cache"
  SUPERVISOR_TMP_ROOT="/tmp/csup-tmp"
  CODEX_BASE_CMD="codex"
  NICE_LEVEL=0
  build_codex_command
' _ "$SCRIPT")"
[[ "$cmd_override" == *"UV_THREADPOOL_SIZE='1'"* ]] || {
  printf 'UV threadpool override was not honored: %s\n' "$cmd_override" >&2
  exit 1
}

echo "ok: worker codex command caps native/thread-pool fanout per pane"
