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
