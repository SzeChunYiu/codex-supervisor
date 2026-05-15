#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys
import time

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

now = time.time()
base_project = {
    "name": "demo",
    "path": "/tmp/demo",
    "instances": [
        {
            "host": "local",
            "session": "demo-main",
            "reachable": True,
            "monitor_expected": True,
            "monitor": {"known": True, "running": False},
            "panes": [
                {"index": 0, "state": "working", "lane": "MANAGER", "tail": ["working"]},
                {"index": 1, "state": "idle", "lane": "worker", "tail": ["Ready"]},
                {"index": 2, "state": "goal-done", "lane": "worker2", "tail": ["Goal achieved"]},
            ],
            "error": "",
        }
    ],
}
with mod.CACHE_LOCK:
    mod.CACHE.clear()
    mod.CACHE.update({
        "updated_at": now,
        "refresh_interval_secs": 0.2,
        "last_refresh_error": "",
        "last_refresh_duration_ms": 1,
        "refresh_count": 1,
        "projects": [base_project],
    })

state = mod.state_payload(compact=True, tail_lines=2)
health = mod.health_payload()
project = state["projects"][0]
assert project["pane_issue_count"] == 2, project
assert project["issue_count"] == 2, project
assert state["project_index"][0]["errors"] == health["pane_issue_count"] == 2, (state["project_index"], health)
assert mod.count_project_payload(project)["errors"] == health["pane_issue_count"], project
print("ok: dashboard state/project issue badges match health pane issues")
PY
