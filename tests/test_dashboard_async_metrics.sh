#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import sys
import threading
import time

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

mod.known_hosts = lambda: {}
mod.this_host_name = lambda hosts: "local"
mod.list_projects = lambda: []
mod.project_instances = lambda proj: []
mod.TOKEN_SCAN_CACHE_SECS = 0.1
mod.SYSTEM_HEALTH_CACHE_SECS = 0.1
mod.TOKEN_USAGE_CACHE = {"key": None, "updated_at": 0, "value": None}
mod.TOOL_CALL_USAGE_CACHE = {"key": None, "updated_at": 0, "value": None}
mod.SYSTEM_HEALTH_CACHE = {"key": None, "updated_at": 0, "value": None}

started = {"token": threading.Event(), "tool": threading.Event(), "system": threading.Event()}
finished = {"token": threading.Event(), "tool": threading.Event(), "system": threading.Event()}

def slow_token(now=None, force=False):
    started["token"].set()
    time.sleep(0.35)
    value = mod.empty_token_usage(session_files_scanned=123)
    with mod.TOKEN_USAGE_CACHE_LOCK:
        mod.TOKEN_USAGE_CACHE["key"] = mod.token_usage_cache_key()
        mod.TOKEN_USAGE_CACHE["updated_at"] = time.time()
        mod.TOKEN_USAGE_CACHE["value"] = json.loads(json.dumps(value))
    finished["token"].set()
    return value

def slow_tool(now=None, force=False):
    started["tool"].set()
    time.sleep(0.35)
    value = mod.empty_tool_call_usage(session_files_scanned=456)
    with mod.TOOL_CALL_USAGE_CACHE_LOCK:
        mod.TOOL_CALL_USAGE_CACHE["key"] = mod.tool_call_usage_cache_key()
        mod.TOOL_CALL_USAGE_CACHE["updated_at"] = time.time()
        mod.TOOL_CALL_USAGE_CACHE["value"] = json.loads(json.dumps(value))
    finished["tool"].set()
    return value

def slow_system(hosts=None, me=None, host_probe_cache=None):
    started["system"].set()
    time.sleep(0.35)
    value = {"status": "ok", "cpu": {}, "memory": {}, "disk": {}, "storage": {"devices": []}}
    finished["system"].set()
    return value

mod.collect_token_usage = slow_token
mod.collect_tool_call_usage = slow_tool
mod.collect_system_health = slow_system

t0 = time.perf_counter()
mod.refresh(1)
elapsed = time.perf_counter() - t0
assert elapsed < 0.20, f"pane refresh should not block on slow metrics, took {elapsed:.3f}s"
for name, event in started.items():
    assert event.wait(0.5), f"{name} metric refresh was not scheduled"
for name, event in finished.items():
    assert event.wait(1.5), f"{name} metric refresh did not finish"

mod.refresh(1)
with mod.CACHE_LOCK:
    snapshot = json.loads(json.dumps(mod.CACHE))
assert snapshot["token_usage"]["session_files_scanned"] == 123, snapshot["token_usage"]
assert snapshot["tool_call_usage"]["session_files_scanned"] == 456, snapshot["tool_call_usage"]
assert snapshot["system_health"]["status"] == "ok", snapshot["system_health"]

slow_started = threading.Event()
slow_release = threading.Event()
mod.known_hosts = lambda: {}
mod.this_host_name = lambda hosts: "local"
mod.list_projects = lambda: [{"name": "demo", "path": "/tmp/demo"}]
mod.project_instances = lambda proj: [
    {"host": "local", "session": "fast", "prompts": "", "source": "state"},
    {"host": "local", "session": "slow", "prompts": "", "source": "state"},
]
mod.parse_lanes = lambda path: {}
mod.get_monitor_status = lambda host, session: mod.empty_monitor_status()
mod.REFRESH_INSTANCE_TIMEOUT_SECS = 0.1

def bounded_capture(host, hosts, me, session, lines, lane_map=None, connection=None):
    if session == "slow":
        slow_started.set()
        slow_release.wait(1.0)
    return [{"index": 0, "state": "working", "tail": [session], "tail_html": session}]

mod.capture_session = bounded_capture
t0 = time.perf_counter()
mod.refresh(1)
elapsed = time.perf_counter() - t0
slow_release.set()
assert elapsed < 0.4, f"refresh should not freeze on a slow instance, took {elapsed:.3f}s"
assert slow_started.wait(0.2), "slow instance was not attempted"
with mod.CACHE_LOCK:
    snapshot = json.loads(json.dumps(mod.CACHE))
assert snapshot["projects"][0]["instances"][0]["session"] == "fast", snapshot["projects"]

runner_kwargs = {}
def disk_host_runner(host, hosts, me, **kwargs):
    runner_kwargs.update(kwargs)
    def runner(cmd):
        return type("R", (), {"returncode": 1, "stdout": "", "stderr": "disk skipped"})()
    return runner

mod.host_runner = disk_host_runner
mod.REMOTE_DISK_TIMEOUT = 3.5
mod.collect_remote_disk_health(
    "lunarc",
    {"lunarc": {"ssh": "lunarc", "scheduler": "slurm"}},
    "local",
    {"job_id": "3047628"},
)
assert runner_kwargs.get("timeout") == 3.5, runner_kwargs
assert runner_kwargs.get("retries") == 0, runner_kwargs

disk_calls = []
mod.collect_disk_health = lambda path=None: {
    "path": str(path or "/"),
    "filesystem": "local",
    "total_bytes": 100,
    "used_bytes": 10,
    "free_bytes": 90,
    "used_percent": 10.0,
    "error": "",
}
def counted_remote_disk(host, hosts, me, connection=None):
    disk_calls.append(host)
    return {
        "host": host,
        "aliases": [host],
        "role": "slurm",
        "path": "/shared",
        "filesystem": "shared",
        "total_bytes": 1000,
        "used_bytes": 200,
        "free_bytes": 800,
        "used_percent": 20.0,
        "reachable": True,
        "error": "",
    }

mod.collect_remote_disk_health = counted_remote_disk
storage = mod.collect_storage_health(
    {
        "lunarc": {"ssh": "lunarc", "scheduler": "slurm", "slurm_job_name": "mcaccel-sup"},
        "lunarc-d": {"ssh": "lunarc-babbloo", "scheduler": "slurm", "slurm_job_name": "mcaccel-sup"},
    },
    "local",
    {
        "lunarc": {"reachable": True, "job_id": "3047628", "node": "cx04"},
        "lunarc-d": {"reachable": True, "job_id": "3047628", "node": "cx04"},
    },
)
assert disk_calls == ["lunarc"], disk_calls
assert storage["devices"][1]["aliases"] == ["lunarc", "lunarc-d"], storage["devices"]

print("ok: dashboard keeps pane refresh live while overview metrics refresh asynchronously")
PY
