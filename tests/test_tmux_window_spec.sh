#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"

default_spec="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  printf "%sx%s\n" "$(tmux_window_x)" "$(tmux_window_y)"
' _ "$SCRIPT")"

if [[ "$default_spec" != "240x70" ]]; then
  printf 'expected default tmux detached window spec 240x70, got: %s\n' "$default_spec" >&2
  exit 1
fi

custom_spec="$(CODEX_SUPERVISOR_TEST_SOURCE=1 CODEX_SUPERVISOR_TMUX_X=480 CODEX_SUPERVISOR_TMUX_Y=140 bash -c '
  source "$1"
  printf "%sx%s\n" "$(tmux_window_x)" "$(tmux_window_y)"
' _ "$SCRIPT")"

if [[ "$custom_spec" != "480x140" ]]; then
  printf 'expected custom tmux detached window spec 480x140, got: %s\n' "$custom_spec" >&2
  exit 1
fi

fallback_spec="$(CODEX_SUPERVISOR_TEST_SOURCE=1 CODEX_SUPERVISOR_TMUX_X=0 CODEX_SUPERVISOR_TMUX_Y=wide bash -c '
  source "$1"
  printf "%sx%s\n" "$(tmux_window_x)" "$(tmux_window_y)"
' _ "$SCRIPT")"

if [[ "$fallback_spec" != "240x70" ]]; then
  printf 'expected invalid tmux detached window spec to fall back to 240x70, got: %s\n' "$fallback_spec" >&2
  exit 1
fi

if ! grep -q 'tmux new-session -d -s "$SESSION" -x "$(tmux_window_x)" -y "$(tmux_window_y)"' "$SCRIPT"; then
  echo "create_tmux_session_panes must use the normalized tmux window spec helpers" >&2
  exit 1
fi

echo "ok: tmux detached window spec is normalized and configurable"
