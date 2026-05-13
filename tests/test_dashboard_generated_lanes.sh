#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys
import tempfile

dashboard_path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

with tempfile.TemporaryDirectory() as d:
    prompts = pathlib.Path(d) / "prompts.txt"
    prompts.write_text(
        "/goal You are PANE 0, lane bugs. Work.\n"
        "/goal You are PANE 1, lane perf. Work.\n"
    )
    lanes = mod.parse_lanes(prompts)
    assert lanes[0] == "bugs", lanes
    assert lanes[1] == "perf", lanes
    assert lanes[2] == "DEBUG", lanes
    assert lanes[3] == "VALIDATOR", lanes

with tempfile.TemporaryDirectory() as d:
    prompts = pathlib.Path(d) / "prompts.txt"
    prompts.write_text(
        "/goal You are PANE 0, lane bugs. Work.\n"
        "/goal You are PANE 1, lane DEBUG. Work.\n"
        "/goal You are PANE 2, lane VALIDATOR. Work.\n"
    )
    lanes = mod.parse_lanes(prompts)
    assert lanes == {0: "bugs", 1: "DEBUG", 2: "VALIDATOR"}, lanes

print("ok: dashboard labels generated DEBUG/VALIDATOR panes")
PY
