#!/usr/bin/env bash
set -euo pipefail

DASHBOARD="${CSUP_DASHBOARD:-$HOME/bin/csup-dashboard}"

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
assert "function renderSelectedProject" in html, "selected project pages should update pane output in place"
assert "function updateVisiblePane" in html, "pane tail changes should patch only the visible terminal pre"
assert "pre.__tailSignature" in html, "pane content signatures should avoid redundant terminal HTML writes"
assert "wasNearBottom" in html, "pane auto-scroll should respect users who scrolled upward"
assert "data-pane-key" in html, "pane clicks should use delegated stable keys instead of per-render handlers"
assert "contain: layout paint style" in html, "expensive cards should use CSS containment"
assert "scrollbar-gutter: stable both-edges" in html, "terminal scrollbars should not shift layout"
assert "prefers-reduced-motion: reduce" in html, "motion-sensitive users should not get hover animation jitter"
assert "new Intl.NumberFormat()" in html, "number formatter should be cached instead of recreated per value"
print("ok: dashboard frontend has smooth incremental render, polling, scroll, and CSS containment guards")
PY
