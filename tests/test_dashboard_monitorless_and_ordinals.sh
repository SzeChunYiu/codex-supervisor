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

# tmux pane indexes can start at 1 on clusters; prompt PANE numbers are
# ordinals. The dashboard must prefer ordinal labels, not raw tmux indexes.
lanes = {0: "WORKER-D", 1: "WORKER-E", 2: "WORKER-F", 3: "BACKLOG-A", 4: "BACKLOG-B", 5: "DEBUG", 6: "VALIDATOR"}
assert mod.lane_label_for_capture({"index": 6, "ordinal": 5, "title": "babbloo-codex", "cmd": "node"}, lanes) == "DEBUG"
assert mod.lane_label_for_capture({"index": 1, "ordinal": 0, "title": "⠋ babbloo", "cmd": "node"}, lanes) == "WORKER-D"

project = {"name": "demo", "hosts": {"lunarc-ci": {"session": "demo-ci", "prompts": "runners.txt", "role": "ci-runners"}}, "instances": []}
instances = mod.project_instances(project)
assert instances[0]["role"] == "ci-runners", instances

class Result:
    returncode = 0
    stdout = "/goal You are PANE 0, lane REMOTE-A. Work.\n/goal You are PANE 1, lane REMOTE-B. Work.\n"
    stderr = ""

def fake_runner(cmd):
    assert cmd[-1] == "/remote/prompts.txt", cmd
    return Result()

mod.PROMPT_LANE_CACHE.clear()
mod.host_runner = lambda host, hosts, me, timeout=5, retries=0, slurm_job_id="": fake_runner
remote_lanes = mod.parse_remote_lanes_cached("lunarc", {"lunarc": {"ssh": "lunarc"}}, "local", "/remote/prompts.txt", {"job_id": "123"})
assert remote_lanes[0] == "REMOTE-A" and remote_lanes[1] == "REMOTE-B", remote_lanes

now = time.time()
mod.CACHE.update({
    "updated_at": now,
    "last_refresh_error": "",
    "refresh_interval_secs": 0.2,
    "projects": [{
        "name": "demo",
        "path": "/tmp/demo",
        "instances": [{
            "host": "lunarc-ci",
            "session": "demo-ci",
            "monitor_expected": False,
            "monitor": {"known": True, "running": False, "pids": []},
            "reachable": True,
            "panes": [{"index": 1, "lane": "runner-1", "state": "idle", "tail": ["Waiting for job"]}],
        }],
    }],
})
health = mod.health_payload()
assert health["ok"], health
assert not health["instance_errors"], health

mod.CACHE["projects"][0]["instances"][0].update({
    "host": "remote",
    "session": "demo-remote",
    "monitor_expected": True,
    "monitor": {"known": True, "running": True, "pids": [123]},
    "panes": [{"index": 1, "lane": "worker", "state": "rate-limited", "tail": ["You've hit your usage limit"]}],
})
health = mod.health_payload()
assert health["ok"], health
assert health["state_counts"].get("rate-limited") == 1, health

mod.CACHE["projects"][0]["instances"][0].update({
    "host": "remote",
    "session": "demo-remote",
    "monitor_expected": True,
    "monitor": {"known": True, "running": True, "pids": [123]},
    "panes": [{"index": 1, "lane": "worker", "state": "goal-done", "tail": ["Goal achieved"]}],
})
health = mod.health_payload()
assert health["ok"], health
assert health["state_counts"].get("goal-done") == 1, health

print("ok: dashboard handles monitorless CI runners, rate-limit cooldowns, and ordinal lane labels")
PY
