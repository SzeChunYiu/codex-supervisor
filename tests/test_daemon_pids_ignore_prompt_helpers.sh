#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
CODEX_SUPERVISOR_SESSION=demo-session \
bash -c '
  source "$1"
  refresh_session_paths
  ps() {
    if [[ "$*" == "-o ppid= -p "* ]]; then
      echo 999
      return 0
    fi
    if [[ "$*" == "-axo pid=,ppid=,command=" ]]; then
      cat <<'"'"'PSOUT'"'"'
100 1 bash /repo/codex-supervisor.sh start --daemon --session demo-session --prompts /tmp/p
200 100 bash /repo/codex-supervisor.sh start --daemon --session demo-session --prompts /tmp/p
300 200 bash /repo/codex-supervisor.sh start --daemon --session demo-session --prompts /tmp/p
400 1 bash /repo/codex-supervisor.sh start --daemon --session other-session --prompts /tmp/p
PSOUT
      return 0
    fi
    command ps "$@"
  }
  supervisor_daemon_pids
' _ "$SCRIPT" > "$TMPDIR/pids"

actual="$(cat "$TMPDIR/pids")"
if [[ "$actual" != "100" ]]; then
  echo "supervisor_daemon_pids should ignore background prompt-helper subshells" >&2
  echo "actual: $actual" >&2
  exit 1
fi

echo "ok: daemon pid detection ignores prompt-helper subshells"
