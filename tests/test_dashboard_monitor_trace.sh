#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess
import sys
import time

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

ps_output = """
111 /bin/bash /repo/codex-supervisor.sh start --daemon --session demo-session
222 /bin/bash /repo/codex-supervisor.sh start --daemon --session other-session
333 /bin/bash /repo/codex-supervisor.sh start --no-attach
"""
status = mod.parse_monitor_status_from_ps(ps_output, "demo-session")
assert status["known"] is True, status
assert status["running"] is True, status
assert status["pids"] == [111], status
subshell_output = """
111 1 /bin/bash /repo/codex-supervisor.sh start --daemon --session demo-session
444 111 /bin/bash /repo/codex-supervisor.sh start --daemon --session demo-session
555 444 /bin/bash /repo/codex-supervisor.sh start --daemon --session demo-session
"""
subshell_status = mod.parse_monitor_status_from_ps(subshell_output, "demo-session")
assert subshell_status["pids"] == [111], subshell_status
missing = mod.parse_monitor_status_from_ps(ps_output, "missing-session")
assert missing["known"] is True and missing["running"] is False, missing

mod.known_hosts = lambda: {"local": {"ssh": "local"}}
mod.this_host_name = lambda hosts: "local"
mod.list_projects = lambda: [{"name": "proj", "path": "/tmp/proj"}]
mod.project_instances = lambda project: [{"host": "local", "session": "demo-session", "prompts": "prompts.txt"}]
mod.parse_lanes = lambda path: {0: "BUGS"}

def fake_host_runner(host, hosts, me, timeout, retries=1, slurm_job_id=""):
    def runner(cmd):
        if cmd[:3] == ["tmux", "list-sessions", "-F"]:
            return subprocess.CompletedProcess(cmd, 0, "demo-session\n", "")
        if cmd[:2] == ["tmux", "list-panes"]:
            return subprocess.CompletedProcess(cmd, 0, "0|0|codex|100|20|BUGS\n", "")
        if cmd[:2] == ["tmux", "capture-pane"]:
            return subprocess.CompletedProcess(cmd, 0, "working\n  gpt-5.5 xhigh fast · /repo Pursuing goal (1m)\n", "")
        if cmd[:2] == ["ps", "-axo"]:
            return subprocess.CompletedProcess(cmd, 0, ps_output, "")
        return subprocess.CompletedProcess(cmd, 1, "", "unexpected")
    return runner

mod.host_runner = fake_host_runner
mod.cached_probe_host = lambda host, hosts, me, now=None: {"reachable": True, "latency_ms": 0, "error": ""}
mod.refresh(3)
projects = mod.CACHE["projects"]
inst = projects[0]["instances"][0]
assert inst["monitor"]["running"] is True, inst
assert inst["monitor"]["pids"] == [111], inst
health = mod.health_payload()
assert not [e for e in health["instance_errors"] if e.get("kind") == "monitor"], health

ps_output = "333 /bin/bash /repo/codex-supervisor.sh start --no-attach\n"
mod.INSTANCE_MONITOR_CACHE.clear()
mod.refresh(3)
inst = mod.CACHE["projects"][0]["instances"][0]
assert inst["monitor"]["known"] is True and inst["monitor"]["running"] is False, inst
health = mod.health_payload()
assert any(e.get("kind") == "monitor" and e.get("session") == "demo-session" for e in health["instance_errors"]), health
assert "monitor missing" in mod.INDEX_HTML, "project UI should expose monitor daemon state"
print("ok: dashboard traces per-session supervisor monitor daemon health")
PY
