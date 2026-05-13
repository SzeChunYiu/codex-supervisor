#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

REAL_CODEX_HOME="$TMPDIR/real-codex"
mkdir -p "$REAL_CODEX_HOME"
cat > "$REAL_CODEX_HOME/config.toml" <<'CONFIG'
model = "gpt-5.5"

[features]
goals = true
CONFIG
printf '{"token":"redacted"}\n' > "$REAL_CODEX_HOME/auth.json"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_HOME="$REAL_CODEX_HOME" \
CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
CODEX_SUPERVISOR_SESSION=demo-session \
bash -c '
  cd "$2"
  source "$1"
  CODEX_BASE_CMD=codex
  cmd0=$(codex_command_for_pane 0)
  cmd1=$(codex_command_for_pane 1)
  printf "cmd0=%s\ncmd1=%s\n" "$cmd0" "$cmd1"
  test -f "$SUPERVISOR_CODEX_HOME/pane-0/config.toml"
  test -f "$SUPERVISOR_CODEX_HOME/pane-1/config.toml"
  test -d "$SUPERVISOR_TMP_ROOT/pane-0"
  test -d "$SUPERVISOR_TMP_ROOT/pane-1"
' _ "$SCRIPT" "$ROOT" > "$TMPDIR/out"

cmd0="$(grep '^cmd0=' "$TMPDIR/out" | cut -d= -f2-)"
cmd1="$(grep '^cmd1=' "$TMPDIR/out" | cut -d= -f2-)"

if [[ "$cmd0" != *"CODEX_HOME='$TMPDIR/root/codex-home/demo-session/pane-0'"* ]]; then
  echo "pane 0 command should use isolated CODEX_HOME" >&2
  cat "$TMPDIR/out" >&2
  exit 1
fi
if [[ "$cmd1" != *"CODEX_HOME='$TMPDIR/root/codex-home/demo-session/pane-1'"* ]]; then
  echo "pane 1 command should use isolated CODEX_HOME" >&2
  cat "$TMPDIR/out" >&2
  exit 1
fi
if [[ "$cmd0" == "$cmd1" ]]; then
  echo "per-pane codex commands should differ by CODEX_HOME/TMPDIR" >&2
  cat "$TMPDIR/out" >&2
  exit 1
fi

echo "ok: each pane gets an isolated Codex home/state runtime"
