#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"

resolved="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; PANE_IDX=(0 1); resolve_pane bugs' \
  _ "$SCRIPT")"

if [[ "$resolved" != "0" ]]; then
  printf 'expected lowercase lane alias "bugs" to resolve to pane 0, got: %s\n' "$resolved" >&2
  exit 1
fi

resolved="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; PANE_IDX=(0 1); resolve_pane PERF' \
  _ "$SCRIPT")"

if [[ "$resolved" != "1" ]]; then
  printf 'expected uppercase lane alias "PERF" to resolve to pane 1, got: %s\n' "$resolved" >&2
  exit 1
fi
