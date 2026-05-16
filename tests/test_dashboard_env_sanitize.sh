#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

CSUP_DASHBOARD_REMOTE_DISK_TIMEOUT_SECS=nan \
CSUP_DASHBOARD_TOKEN_SCAN_MAX_FILES=bad \
CSUP_DASHBOARD_TOKEN_SCAN_MTIME_DAYS=-1 \
CSUP_DASHBOARD_TOKEN_SCAN_MAX_BYTES=bad \
CSUP_DASHBOARD_TOKEN_SCAN_CACHE_SECS=inf \
CSUP_DASHBOARD_TOKEN_HISTORY_MAX_EVENTS=bad \
CSUP_DASHBOARD_TOKEN_HISTORY_EVENTS_PER_FILE=bad \
CSUP_DASHBOARD_TOOL_HISTORY_MAX_EVENTS=bad \
CSUP_DASHBOARD_TOOL_HISTORY_EVENTS_PER_FILE=bad \
CSUP_DASHBOARD_PROCESS_TOP_LIMIT=bad \
CSUP_DASHBOARD_SYSTEM_HISTORY_MAX_POINTS=bad \
CSUP_DASHBOARD_HOST_PROBE_CACHE_SECS=nan \
CSUP_DASHBOARD_HOST_PROBE_DEFER_MAX_STALE_SECS=bad \
CSUP_DASHBOARD_HOST_PROBE_ASYNC=maybe \
CSUP_DASHBOARD_REMOTE_CAPTURE_CACHE_SECS=bad \
CSUP_DASHBOARD_REMOTE_CAPTURE_ERROR_RETRY_SECS=bad \
CSUP_DASHBOARD_REMOTE_CAPTURE_STICKY_SECS=bad \
CSUP_DASHBOARD_REMOTE_INITIAL_CAPTURE_ASYNC=maybe \
CSUP_DASHBOARD_PROMPT_LANE_CACHE_SECS=bad \
CSUP_DASHBOARD_STATE_CAPTURE_MIN_LINES=bad \
CSUP_DASHBOARD_INCLUDE_PROMPTLESS=maybe \
CSUP_DASHBOARD_SYSTEM_HEALTH_CACHE_SECS=bad \
CSUP_DASHBOARD_REFRESH_INSTANCE_TIMEOUT_SECS=bad \
CSUP_DASHBOARD_STREAMING=maybe \
CSUP_DASHBOARD_REMOTE_TOML_CACHE_SECS=bad \
CSUP_DASHBOARD_TMUX_DISCOVERY_TIMEOUT_SECS=bad \
CSUP_DASHBOARD_STATION_GUESS_MAX=bad \
python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_env_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_env_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

assert mod.REMOTE_DISK_TIMEOUT == 4.0
assert mod.TOKEN_SCAN_MAX_FILES == 300
assert mod.TOKEN_SCAN_MTIME_DAYS == 14
assert mod.TOKEN_SCAN_MAX_BYTES == 262144
assert mod.TOKEN_SCAN_CACHE_SECS == 10.0
assert mod.HOST_PROBE_CACHE_SECS == 10.0
assert mod.REMOTE_CAPTURE_CACHE_SECS == 0.5
assert mod.STATE_CAPTURE_MIN_LINES == 80
assert mod.REFRESH_INSTANCE_TIMEOUT_SECS == 3.0
assert mod.REMOTE_PROJECT_TOML_CACHE_SECS == 60.0
assert mod.TMUX_DISCOVERY_TIMEOUT_SECS == 12.0
assert mod.station_candidate_sessions("proj")[-1] == "proj-station-4"
assert mod.bounded_int(-1, 7777, min_value=1, max_value=65535) == 7777
assert mod.bounded_int(70000, 7777, min_value=1, max_value=65535) == 7777
assert mod.bounded_int("24", 12, min_value=1, max_value=200) == 24
assert mod.bounded_float("nan", 0.2, min_value=0.05) == 0.2
assert mod.bounded_float("0.1", 0.2, min_value=0.05) == 0.1
assert "def env_float" in mod._STREAMER_SCRIPT
assert 'CSUP_STREAMER_POLL_FAST", 0.1' in mod._STREAMER_SCRIPT
PY
