#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/tmux" <<'MOCK_TMUX'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TMUX_ARGS_FILE"
printf 'line1\nline2\nline3\n'
MOCK_TMUX
chmod +x "$TMPDIR/bin/tmux"

PATH="$TMPDIR/bin:$PATH" \
TMUX_ARGS_FILE="$TMPDIR/tmux.args" \
CODEX_SUPERVISOR_TEST_SOURCE=1 \
  bash -c 'source "$1"; CAPTURE_TAIL_LINES=2; capture_tail "codex-supervisor:0.1" >/dev/null' \
  _ "$SCRIPT"

args="$(cat "$TMPDIR/tmux.args")"
if [[ "$args" != *"capture-pane -t codex-supervisor:0.1 -p -S -2"* ]]; then
  printf 'capture_tail should ask tmux for only the bounded tail; got args: %s\n' "$args" >&2
  exit 1
fi
