#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="$ROOT/csup-dashboard"

python3 - "$DASHBOARD" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert "cleaning up orphaned streamers asynchronously" in text, "startup cleanup should not block localhost 7777 serving"
assert "target=_cleanup_orphaned_streamers" in text, "orphaned streamer cleanup should run in a background thread"
print("ok: dashboard startup does not block on remote streamer cleanup")
PY
