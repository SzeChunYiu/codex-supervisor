#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
CODEX_SUPERVISOR_POLL=bad \
CODEX_SUPERVISOR_PERIODIC_CLEANUP_SECS=bad \
MONITOR_LOG="$TMPDIR/monitor.log" \
TEST_TMPDIR="$TMPDIR" \
  bash -c '
    set -euo pipefail
    source "$1"

    ensure_codex_cmd() { :; }
    load_prompts() {
      PROMPTS=("/goal test")
      LANE_LABELS=("TEST")
    }
    ensure_start_resource_budget() { return 0; }
    ensure_node_pane_budget() { return 0; }
    write_state_file() { :; }
    acquire_node_start_lock() { :; }
    release_node_start_lock() { :; }
    create_tmux_session_panes() { PANE_IDX=(0); return 0; }
    prompt_all_panes() { :; }
    cleanup_session() { :; }
    check_pane() { :; }
    tmux() { [[ "${1:-}" == "has-session" ]]; }
    date() {
      if [[ "${1:-}" == "+%s" ]]; then
        local counter value
        counter="$TEST_TMPDIR/date-counter"
        if [[ -e "$counter" ]]; then
          value=120
        else
          value=0
          : > "$counter"
        fi
        printf "%s\n" "$value"
        return 0
      fi
      command date "$@"
    }
    run_periodic_cleanup() {
      : > "$TEST_TMPDIR/periodic-cleanup.called"
      exit 0
    }
    log() { printf "%s\n" "$*" >> "$MONITOR_LOG"; }
    sleep() {
      if [[ "$1" != "15" ]]; then
        echo "expected sanitized poll interval 15, got $1" >&2
        exit 1
      fi
      return 0
    }

    _start_supervisor_main 0
  ' _ "$SCRIPT"

test -e "$TMPDIR/periodic-cleanup.called"

TMPDIR_HUGE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR" "$TMPDIR_HUGE"' EXIT
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR_HUGE/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR_HUGE/supervisor.log" \
CODEX_SUPERVISOR_POLL=999999 \
CODEX_SUPERVISOR_PERIODIC_CLEANUP_SECS=999999 \
MONITOR_LOG="$TMPDIR_HUGE/monitor.log" \
TEST_TMPDIR="$TMPDIR_HUGE" \
  bash -c '
    set -euo pipefail
    source "$1"

    ensure_codex_cmd() { :; }
    load_prompts() { PROMPTS=("/goal test"); LANE_LABELS=("TEST"); }
    ensure_start_resource_budget() { return 0; }
    ensure_node_pane_budget() { return 0; }
    write_state_file() { :; }
    acquire_node_start_lock() { :; }
    release_node_start_lock() { :; }
    create_tmux_session_panes() { PANE_IDX=(0); return 0; }
    prompt_all_panes() { :; }
    cleanup_session() { :; }
    check_pane() { :; }
    tmux() { [[ "${1:-}" == "has-session" ]]; }
    date() {
      if [[ "${1:-}" == "+%s" ]]; then
        local counter value
        counter="$TEST_TMPDIR/date-counter"
        if [[ -e "$counter" ]]; then value=120; else value=0; : > "$counter"; fi
        printf "%s\n" "$value"
        return 0
      fi
      command date "$@"
    }
    run_periodic_cleanup() { : > "$TEST_TMPDIR/periodic-cleanup.called"; exit 0; }
    log() { printf "%s\n" "$*" >> "$MONITOR_LOG"; }
    sleep() {
      if [[ "$1" != "15" ]]; then
        echo "expected oversized poll interval to sanitize to 15, got $1" >&2
        exit 1
      fi
      return 0
    }

    _start_supervisor_main 0
  ' _ "$SCRIPT"

test -e "$TMPDIR_HUGE/periodic-cleanup.called"
