#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CODEX_SUPERVISOR_TEST_SOURCE=1 LAYOUT_LOG="$TMPDIR/layout.log" bash -c '
  source "$1"
  SESSION=demo
  PANE_IDX=(0 1)
  log() { :; }
  command() { if [[ "$1" == "-v" && "$2" == "python3" ]]; then return 0; fi; builtin command "$@"; }
  tmux() {
    if [[ "$1" == "display-message" ]]; then
      printf "%s\n" "wide tall"
      return 0
    fi
    if [[ "$1" == "select-layout" ]]; then
      printf "%s\n" "$*" >> "$LAYOUT_LOG"
      return 0
    fi
    return 0
  }
  apply_even_grid
' _ "$SCRIPT"

layout="$(cat "$TMPDIR/layout.log")"
[[ "$layout" != *" tiled"* ]] || { echo "malformed dimensions should sanitize into a layout, not fall back to tiled" >&2; exit 1; }
[[ "$layout" == *"80x24"* ]] || { echo "sanitized layout should use default dimensions, got: $layout" >&2; exit 1; }

CODEX_SUPERVISOR_TEST_SOURCE=1 LAYOUT_LOG="$TMPDIR/layout-bad-pane.log" bash -c '
  source "$1"
  SESSION=demo
  PANE_IDX=(0 bad 2)
  log() { :; }
  command() { if [[ "$1" == "-v" && "$2" == "python3" ]]; then return 0; fi; builtin command "$@"; }
  tmux() {
    if [[ "$1" == "display-message" ]]; then
      printf "%s\n" "120 40"
      return 0
    fi
    if [[ "$1" == "select-layout" ]]; then
      printf "%s\n" "$*" >> "$LAYOUT_LOG"
      return 0
    fi
    return 0
  }
  apply_even_grid
' _ "$SCRIPT"

layout_bad_pane="$(cat "$TMPDIR/layout-bad-pane.log")"
[[ "$layout_bad_pane" != *"bad"* ]] || { echo "non-numeric pane ids should be excluded from generated layout: $layout_bad_pane" >&2; exit 1; }
[[ "$layout_bad_pane" == *",0}"* || "$layout_bad_pane" == *",0,"* ]] || { echo "layout should still include valid pane 0: $layout_bad_pane" >&2; exit 1; }

echo "ok: even-grid layout sanitizes numeric inputs"
