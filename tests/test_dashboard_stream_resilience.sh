#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys


dashboard_path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)
html = mod.INDEX_HTML

# Regression: a hung /api/state.json fetch used to leave tickInFlight set
# forever, so every later setInterval tick returned the stale promise and the
# display looked frozen until a page reload.
assert "const FETCH_TIMEOUT_MS" in html, "state polling must have an explicit timeout budget"
assert "new AbortController()" in html, "state polling must be abortable"
assert "stateFetchController.abort()" in html, "manual refresh / recovery must be able to abort a stuck poll"
assert "setTimeout(() => controller.abort()" in html, "hung fetches must self-abort"
assert "clearTimeout(timeoutId)" in html, "fetch timeout timers must be cleaned up"
assert "stateFetchSeq" in html, "late responses must be fenced by a monotonic request sequence"
assert "consecutiveRefreshFailures" in html, "transport failures should be tracked instead of silently freezing"
assert "renderTransportStatus" in html, "the UI should show refresh/stream health, not just old data"

# Regression: overview graphics rebuilt the entire root every refresh because
# refresh_count/system_history changed every second. That janked charts and
# sometimes made streaming panes appear frozen. Keep stable overview slots and
# update only the section whose model changed.
assert "overviewSectionSignatures" in html, "overview graphics need per-section render signatures"
assert "function ensureOverviewSlots" in html, "overview graphics should have stable DOM slots"
assert "function updateOverviewSlot" in html, "overview sections should patch independently"
assert "function overviewLayoutSignature" in html, "overview layout should be separated from metric content"
assert "function renderOverview(state)" in html, "overview should use a dedicated incremental renderer"
assert "renderOverview(state);" in html, "flushRender should update overview incrementally"
assert "refresh_count: state.refresh_count" not in html, "root signature must not force full overview rebuilds every poll"
assert "system_history: state.system_history" not in html, "root signature must not force full overview rebuilds every poll"
print("ok: dashboard polling has abort/recovery guards and graphics render incrementally")
PY

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_stream_overlay", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_stream_overlay", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

mod.known_hosts = lambda: {"ng-content-lunarc": {"ssh": "lunarc", "scheduler": "slurm"}}
stream_key = mod.streaming_connection_key("lunarc", "3061936")
with mod.CACHE_LOCK:
    mod.CACHE["projects"] = [{
        "name": "neural_grow",
        "path": "/tmp/neural_grow",
        "instances": [{
            "host": "ng-content-lunarc",
            "session": "ng-content-lunarc-station-1",
            "connection": {"job_id": "3061936"},
            "panes": [{"index": 1, "lane": "planner-content", "tail": ["old"], "tail_html": "old"}],
            "error": "",
        }],
    }]
with mod.STREAMING_CACHE_LOCK:
    mod.STREAMING_CACHE[(stream_key, "ng-content-lunarc-station-1")] = {
        "ts": "not-a-time",
        "panes": [{
            "index": 1,
            "dead": False,
            "cmd": "codex",
            "width": 120,
            "height": 40,
            "title": "",
            "ansi": "old\nnew live line",
        }, {
            "index": "bad",
            "dead": False,
            "cmd": "codex",
            "width": "wide",
            "height": "tall",
            "title": "",
            "ansi": "malformed live line",
        }],
    }

state = mod.state_payload(compact=True, tail_lines=1)
panes = state["projects"][0]["instances"][0]["panes"]
pane = panes[0]
assert pane["tail"] == ["new live line"], pane
assert pane["lane"] == "planner-content", pane
assert "tail_html" not in pane, pane
assert panes[1]["index"] == 0, panes[1]
assert panes[1]["width"] == 0 and panes[1]["height"] == 0, panes[1]
assert state["projects"][0]["instances"][0]["stream_updated_at"] == 0.0, state["projects"][0]["instances"][0]
assert mod.capture_cache_key("h", "s", "bad", {"bad": "lane"}) == ("h", "s", mod.DEFAULT_TAIL, ((-1, "lane"),))
assert mod.render_captured_item_simple({"index": "bad", "ansi": "a\nb"}, tail_lines="bad")["tail"] == ["a", "b"]
assert mod.capture_cache_problem("h", "s", "bad") == {}
print("ok: state payload overlays fresh streaming pane text between full refreshes")
PY
