#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import os
import pathlib
import sys

dashboard_path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

mod.known_hosts = lambda: {"local": {"ssh": "local"}}
mod.this_host_name = lambda hosts: "local"
mod.parse_lanes = lambda path: {}
mod.probe_host = lambda host, hosts, me: {"reachable": True, "latency_ms": 0, "error": ""}
mod.list_projects = lambda: [
    {
        "name": "empty-project",
        "path": "/tmp/empty-project",
        "hosts": {"local": {"session": "empty-session", "prompts": "prompts.txt"}},
        "instances": [],
    },
    {
        "name": "live-project",
        "path": "/tmp/live-project",
        "hosts": {"local": {"session": "live-session", "prompts": "prompts.txt"}},
        "instances": [],
    },
]

def fake_capture(host, hosts, me, session, lines, lane_map, connection=None):
    if session == "empty-session":
        return None
    return [{"index": 0, "lane": "demo", "state": "working", "tail": ["bottom"], "tail_html": "bottom"}]

mod.capture_session = fake_capture
mod.refresh(28)

projects = mod.CACHE["projects"]
assert [p["name"] for p in projects] == ["live-project"], projects
assert projects[0]["instances"][0]["session"] == "live-session", projects
assert projects[0]["instances"][0]["panes"], projects

old_show_empty = os.environ.get("CSUP_DASHBOARD_SHOW_EMPTY_PROJECTS")
try:
    os.environ["CSUP_DASHBOARD_SHOW_EMPTY_PROJECTS"] = "empty-project"
    mod.refresh(28)
    projects = mod.CACHE["projects"]
    assert [p["name"] for p in projects] == ["empty-project", "live-project"], projects
    assert projects[0]["instances"][0]["session"] == "empty-session", projects
    os.environ["CSUP_DASHBOARD_SHOW_EMPTY_PROJECTS"] = "x" * (mod.MAX_STATION_PROJECT_FILTER_CHARS + 1)
    mod.refresh(28)
    projects = mod.CACHE["projects"]
    assert [p["name"] for p in projects] == ["live-project"], projects
finally:
    if old_show_empty is None:
        os.environ.pop("CSUP_DASHBOARD_SHOW_EMPTY_PROJECTS", None)
    else:
        os.environ["CSUP_DASHBOARD_SHOW_EMPTY_PROJECTS"] = old_show_empty
print("ok: dashboard hides empty non-running sessions")
PY
