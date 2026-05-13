#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

kill_file="$TMPDIR/killed"
term_file="$TMPDIR/terminated"
layout_file="$TMPDIR/layout"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
KILL_FILE="$kill_file" \
TERM_FILE="$term_file" \
LAYOUT_FILE="$layout_file" \
bash -c '
  source "$1"
  SESSION=demo
  PROMPTS=(p0 p1 p2 p3 p4)
  PANE_IDX=(1 2 3 4 5 6)
  panes="1 2 3 4 5 6"
  log() { :; }
  terminate_pane_process_tree() { printf "%s\n" "$1" >> "$TERM_FILE"; }
  apply_even_grid() { printf "grid\n" >> "$LAYOUT_FILE"; }
  apply_pane_titles() { printf "titles\n" >> "$LAYOUT_FILE"; }
  tmux() {
    case "$1" in
      list-panes)
        for p in $panes; do printf "%s\n" "$p"; done
        ;;
      kill-pane)
        printf "%s\n" "$3" >> "$KILL_FILE"
        panes="1 2 3 4 5"
        ;;
      *) return 0 ;;
    esac
  }
  reconcile_live_panes_with_prompts
  printf "%s\n" "${PANE_IDX[*]}" > "$2"
' _ "$SCRIPT" "$TMPDIR/panes"

if [[ "$(cat "$kill_file" 2>/dev/null || true)" != "demo:0.6" ]]; then
  echo "reattach should kill stale extra pane beyond prompt count" >&2
  cat "$kill_file" >&2 || true
  exit 1
fi
if [[ "$(cat "$term_file" 2>/dev/null || true)" != "demo:0.6" ]]; then
  echo "reattach should terminate stale extra pane process tree before killing pane" >&2
  cat "$term_file" >&2 || true
  exit 1
fi
if [[ "$(cat "$TMPDIR/panes")" != "1 2 3 4 5" ]]; then
  echo "reattach should repopulate pane indexes after removing extras" >&2
  cat "$TMPDIR/panes" >&2
  exit 1
fi
if ! grep -q '^grid$' "$layout_file" || ! grep -q '^titles$' "$layout_file"; then
  echo "reattach should relayout and retitle after pane reconciliation" >&2
  cat "$layout_file" >&2 || true
  exit 1
fi

echo "ok: reattach removes stale extra panes after prompt count shrinks"
