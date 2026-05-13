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
assert "requestAnimationFrame(flushRender)" in html, "dashboard renders should be coalesced into one animation frame"
assert "rootSignature(state, selectedSlug, selectedProject)" in html, "dashboard should compute a scoped render signature"
assert "if (signature === lastRootSignature) return" in html, "unchanged state must not rebuild the project DOM"
assert "let tickInFlight = null" in html, "polling should guard against overlapping fetch/render cycles"
assert "setInterval(() => { if (!document.hidden) tick(false); }, UI_REFRESH_MS)" in html, "background polling should pause while hidden"
assert "document.addEventListener('visibilitychange'" in html, "dashboard should refresh immediately when visible again"
assert "scheduleBottomScroll(terminal)" in html, "pane bottom sticking should be batched instead of one frame per pane"
assert "currentPaneCache = nextPaneCache" in html, "pane click metadata should be rebuilt only with the current DOM"
assert "currentPaneElementCache = nextPaneElementCache" in html, "pane DOM nodes should be cached after full project render"
assert "currentInstanceElementCache = nextInstanceElementCache" in html, "instance header DOM nodes should be cached after full project render"
assert "new IntersectionObserver" in html, "offscreen pane terminals should not be patched every poll"
assert "shouldRenderPaneTerminal(key)" in html, "terminal HTML writes should be gated to visible panes"
assert "observePaneCard(card)" in html, "pane cards should register with visibility tracking"
assert "function renderSelectedProject" in html, "selected project pages should update pane output in place"
assert "function updateVisiblePane" in html, "pane tail changes should patch only the visible terminal pre"
assert "function updatePaneChrome" in html, "pane state/lane/model chrome should patch in place"
assert "function updateInstanceHeader" in html, "connection/monitor header changes should patch in place"
assert "pre.__tailSignature" in html, "pane content signatures should avoid redundant terminal HTML writes"
assert "wasNearBottom" in html, "pane auto-scroll should respect users who scrolled upward"
assert "data-pane-key" in html, "pane clicks should use delegated stable keys instead of per-render handlers"
assert "contain: layout paint style" in html, "expensive cards should use CSS containment"
assert "scrollbar-gutter: stable both-edges" in html, "terminal scrollbars should not shift layout"
assert "prefers-reduced-motion: reduce" in html, "motion-sensitive users should not get hover animation jitter"
assert "new Intl.NumberFormat()" in html, "number formatter should be cached instead of recreated per value"
assert "new URLSearchParams()" in html, "selected project polling should request a scoped state payload"
assert "params.set('project', selectedSlug)" in html, "selected project polling should avoid fetching every project payload"
assert 'id="compact-toggle"' in html, "compact cards should remain an optional fallback"
assert "if (compactToggle.checked)" in html, "full live pane cards should be the default, not compact mode"
assert "params.set('compact', '1')" in html, "optional compact mode should still request compact pane payloads"
assert "params.set('tail', '6')" in html, "optional compact mode should request a short smooth tail"

structure = html.split("function selectedProjectStructure(project)", 1)[1].split("function connectionDisplay", 1)[0]
for volatile in ["connection:", "monitor:", "state:", "lane:", "model:", "reachable:", "error:"]:
    assert volatile not in structure, f"volatile {volatile} must not force full selected-project DOM rebuilds"
print("ok: dashboard frontend has smooth incremental render, polling, scroll, and CSS containment guards")
PY
