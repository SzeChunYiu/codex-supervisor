#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="$ROOT/csup-dashboard"

python3 - "$DASHBOARD" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert "signal.signal(signal.SIGHUP, signal.SIG_IGN)" in text, "dashboard must not exit on SIGHUP; nohup/background launch depends on this"
assert "signal.signal(signal.SIGHUP, _sigterm_handler)" not in text, "SIGHUP must not share SIGTERM shutdown handler"
print("ok: dashboard ignores SIGHUP for durable localhost service mode")
PY
