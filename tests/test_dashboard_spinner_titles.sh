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

assert mod.pane_title_indicates_activity("⠙ babbloo-codex")
assert mod.pane_title_indicates_activity(" ⠏ NNBAR_Detector_sim")
assert not mod.pane_title_indicates_activity("babbloo-codex")
assert not mod.pane_title_indicates_activity("")

print("ok: dashboard treats tmux spinner titles as active panes")
PY
