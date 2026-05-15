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

mod.known_hosts = lambda: {"local": {"ssh": "local"}}
mod.this_host_name = lambda hosts: "local"
mod.parse_lanes = lambda path: {}
mod.cached_probe_host = lambda host, hosts, me, started_at: {"reachable": True, "latency_ms": 0, "error": ""}
mod.collect_token_usage_snapshot = lambda now: mod.empty_token_usage()
mod.collect_tool_call_usage_snapshot = lambda now: mod.empty_tool_call_usage()
mod.collect_system_health_snapshot = lambda hosts, me, host_probe_cache, now: mod.empty_system_health()
mod.list_projects = lambda: [
    {
        "name": "neural_grow",
        "path": "/tmp/neural_grow",
        "hosts": {"local": {"session": "ng-main", "prompts": "prompts.txt"}},
        "instances": [],
    },
    {
        "name": "neural_grow",
        "path": "/tmp/neural_grow-pr-runtime-blockers",
        "hosts": {"local": {"session": "ng-runtime", "prompts": "prompts.txt"}},
        "instances": [],
    },
    {
        "name": "neural_grow",
        "path": "/tmp/neural_grow-shadow-copy",
        "hosts": {"local": {"session": "ng-main", "prompts": "prompts.txt"}},
        "instances": [],
    },
    {
        "name": "nnbar",
        "path": "/tmp/nnbar",
        "hosts": {"local": {"session": "nnbar-live", "prompts": "prompts.txt"}},
        "instances": [],
    },
]

def fake_capture(host, hosts, me, session, lines, lane_map, connection=None):
    if session == "ng-main":
        return [{"index": 0, "lane": "main", "state": "working", "tail": ["main"], "tail_html": "main"}]
    if session == "ng-runtime":
        return [{"index": 0, "lane": "runtime", "state": "working", "tail": ["runtime"], "tail_html": "runtime"}]
    if session == "nnbar-live":
        return [{"index": 0, "lane": "worker", "state": "working", "tail": ["nnbar"], "tail_html": "nnbar"}]
    return None

mod.capture_session = fake_capture
mod.refresh(8)

state = mod.state_payload()
projects = state["projects"]
assert len(projects) == 3, projects
by_path = {p["path"]: p for p in projects}
assert by_path["/tmp/neural_grow"]["instances"][0]["session"] == "ng-main", projects
assert by_path["/tmp/neural_grow-pr-runtime-blockers"]["instances"][0]["session"] == "ng-runtime", projects
assert "/tmp/neural_grow-shadow-copy" not in by_path, projects
assert by_path["/tmp/nnbar"]["instances"][0]["session"] == "nnbar-live", projects

slugs = [p["slug"] for p in projects]
assert len(slugs) == len(set(slugs)), slugs
assert "nnbar" in slugs, slugs

for project in projects:
    filtered = mod.state_payload(project["slug"])["projects"]
    assert [p["path"] for p in filtered] == [project["path"]], (project, filtered)

print("ok: duplicate project names keep separate unique instances, avoid double-counted sessions, and nnbar remains addressable")
PY
