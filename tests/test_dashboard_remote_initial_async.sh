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
import threading
import time

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

started = threading.Event()
release = threading.Event()
ansi = "hello\nworking\n  gpt-5.5 xhigh fast · /repo Pursuing goal (1m)\n"

def fake_host_runner(host, hosts, me, timeout, retries=1, slurm_job_id=""):
    def runner(cmd):
        started.set()
        release.wait(1.5)
        payload = [{
            "index": 0,
            "ordinal": 0,
            "dead": False,
            "cmd": "codex",
            "width": 120,
            "height": 10,
            "title": "BUGS",
            "ansi": ansi,
        }]
        return subprocess.CompletedProcess(cmd, 0, json.dumps(payload), "")
    return runner

mod.host_runner = fake_host_runner
mod.REMOTE_CAPTURE_CACHE_SECS = 2.0
mod.REMOTE_INITIAL_CAPTURE_ASYNC = True
mod.INSTANCE_CAPTURE_CACHE.clear()

t0 = time.perf_counter()
first = mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "demo", 3, {0: "BUGS"})
elapsed = time.perf_counter() - t0
assert first is None, first
assert elapsed < 0.2, f"initial remote capture should not block pane refresh, took {elapsed:.3f}s"
assert started.wait(0.5), "background remote capture was not scheduled"
release.set()
for _ in range(20):
    second = mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "demo", 3, {0: "BUGS"})
    if second:
        break
    time.sleep(0.1)
assert second and second[0]["state"] == "working", second

mod.INSTANCE_CAPTURE_CACHE.clear()
mod.known_hosts = lambda: {"remote": {"ssh": "remote"}}
mod.this_host_name = lambda hosts: "local"
mod.list_projects = lambda: [{"name": "proj", "path": "/tmp/proj"}]
mod.project_instances = lambda proj: [{"host": "remote", "session": "missing", "prompts": ""}]
mod.cached_probe_host = lambda host, hosts, me, now=None: {"reachable": True, "latency_ms": 1, "error": ""}

failed = threading.Event()

def failing_host_runner(host, hosts, me, timeout, retries=1, slurm_job_id=""):
    def runner(cmd):
        failed.set()
        return subprocess.CompletedProcess(cmd, 1, "", "session not found")
    return runner

mod.host_runner = failing_host_runner
mod.refresh(3)
assert failed.wait(0.5), "failing remote capture was not scheduled"
for _ in range(20):
    mod.refresh(3)
    projects = mod.CACHE.get("projects") or []
    if projects:
        break
    time.sleep(0.1)
projects = mod.CACHE.get("projects") or []
assert not projects, projects

mod.INSTANCE_CAPTURE_CACHE.clear()
mod.host_runner = fake_host_runner
started.clear()
release.clear()
priming = mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "missing", 3, {})
assert priming is None, priming
assert started.wait(0.5), "background cache primer was not scheduled"
release.set()
for _ in range(20):
    cached = mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "missing", 3, {})
    if cached:
        break
    time.sleep(0.1)
assert cached, cached
mod.cached_probe_host = lambda host, hosts, me, now=None: {"reachable": False, "latency_ms": None, "error": "ssh probe timeout"}
mod.refresh(3)
projects = mod.CACHE.get("projects") or []
assert projects, mod.CACHE
inst = projects[0]["instances"][0]
assert inst["host"] == "remote", inst
assert inst["error"] == "host unreachable", inst
assert inst["connection"]["error"] == "ssh probe timeout", inst
assert inst["panes"][0].get("capture_stale") is True, inst
assert "ssh probe timeout" in inst["panes"][0].get("capture_error", ""), inst

mod.cached_probe_host = lambda host, hosts, me, now=None: {
    "reachable": False,
    "latency_ms": 781,
    "queue_wait_ms": 0,
    "error": "mux_client_request_session: session request failed",
    "probe_stale": True,
    "probe_deferred": True,
}
mod.refresh(3)
projects = mod.CACHE.get("projects") or []
assert projects, mod.CACHE
inst = projects[0]["instances"][0]
assert inst["host"] == "remote", inst
assert inst["error"] == "", inst
assert inst["reachable"] is True, inst
assert inst["connection"].get("probe_deferred") is True, inst
assert inst["panes"][0].get("capture_stale") is not True, inst
assert not inst["panes"][0].get("capture_error"), inst

mod.INSTANCE_CAPTURE_CACHE.clear()
mod.REMOTE_CAPTURE_CACHE_SECS = 0.1
mod.REMOTE_CAPTURE_ERROR_RETRY_SECS = 60.0
calls = {"n": 0}

def counted_failing_host_runner(host, hosts, me, timeout, retries=1, slurm_job_id=""):
    def runner(cmd):
        calls["n"] += 1
        return subprocess.CompletedProcess(cmd, 1, "", "session not found")
    return runner

mod.host_runner = counted_failing_host_runner
key = mod.capture_cache_key("remote", "missing", 3, {})
now = time.time()
mod.INSTANCE_CAPTURE_CACHE[key] = {
    "updated_at": now - 30.0,
    "last_attempt_at": now - 1.0,
    "last_error": "session not found",
    "value": None,
    "refreshing": False,
}
again = mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "missing", 3, {})
assert again is None, again
assert calls["n"] == 0, "error backoff should not hammer remote captures every refresh"
print("ok: first remote dashboard capture is asynchronous so local refresh stays live")
PY
