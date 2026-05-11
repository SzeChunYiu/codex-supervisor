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
assert "function scrollPaneToBottom" in html, "dashboard should define bottom-stick helper"
assert "terminal.scrollTop = terminal.scrollHeight" in html, "pane terminal should scroll to newest bottom output"
assert "modalScroll.scrollTop = modalScroll.scrollHeight" in html, "full scrollback modal should open at the bottom"
print("ok: dashboard pane UI is bottom-anchored")
PY
