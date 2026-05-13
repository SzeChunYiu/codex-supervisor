#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"

run_classifier() {
  local capture="$1"
  CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
    'source "$1"; classify_capture_state "$2"' \
    _ "$SCRIPT" "$capture"
}

assert_state() {
  local expected="$1" capture="$2" actual
  actual="$(run_classifier "$capture")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected state %s, got %s for capture: %s\n' "$expected" "$actual" "$capture" >&2
    return 1
  fi
}

# Sourcing the script must be side-effect free so helper behavior can be tested
# without launching/stopping tmux sessions.
CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c 'source "$1"; type classify_capture_state >/dev/null' _ "$SCRIPT"

assert_state "LIMITED"  "You've hit your usage limit. Try again later."
assert_state "LIMITED"  $'You\'ve hit your usage\nlimit. Try again later.'
assert_state "STARTING" "Starting MCP servers (12/15)"
assert_state "DONE"     "goal Complete after verification"
assert_state "WORKING"  "Pursuing goal: optimize the supervisor"
assert_state "WORKING"  "Working"
assert_state "READY"    "Tip: press ? for help"
assert_state "READY"    "gpt-5.5 xhigh fast"
assert_state "?"        "idle shell prompt"

if ! CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
  'source "$1"; capture_needs_fresh_context "$2"' \
  _ "$SCRIPT" "Compacting conversation"; then
  echo "compacting marker should request a fresh context" >&2
  exit 1
fi

if ! CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
  'source "$1"; capture_needs_fresh_context "$2"' \
  _ "$SCRIPT" "Error running remote compact task"; then
  echo "remote compact failure should request a fresh context" >&2
  exit 1
fi

if ! CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
  'source "$1"; capture_needs_fresh_context "$2"' \
  _ "$SCRIPT" $'Error running remote compact\ntask'; then
  echo "wrapped remote compact failure should request a fresh context" >&2
  exit 1
fi

preview="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
  'source "$1"; capture_preview "$2" 60' \
  _ "$SCRIPT" $'\n first\t line\nlast\tline with    spaces\n')"
if [[ "$preview" != "last line with spaces" ]]; then
  printf 'expected normalized last-line preview, got: %s\n' "$preview" >&2
  exit 1
fi

preview="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
  'source "$1"; capture_preview "$2" 4' \
  _ "$SCRIPT" $'abcdef\n')"
if [[ "$preview" != "abcd" ]]; then
  printf 'expected preview limit to be applied, got: %s\n' "$preview" >&2
  exit 1
fi
