#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
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

started = threading.Event()
release = threading.Event()

def slow_probe(host, hosts, me):
    started.set()
    release.wait(1.0)
    return {"reachable": True, "latency_ms": 777, "error": ""}

mod.probe_host = slow_probe
mod.HOST_PROBE_ASYNC = True
mod.HOST_PROBE_CACHE_SECS = 2.0
mod.HOST_PROBE_CACHE.clear()

t0 = time.perf_counter()
first = mod.cached_probe_host("remote", {"remote": {"ssh": "remote"}}, "local")
elapsed = time.perf_counter() - t0
assert elapsed < 0.2, f"remote host probe should not block refresh, took {elapsed:.3f}s"
assert first.get("probe_warming") is True and not first.get("reachable"), first
assert started.wait(0.5), "background host probe was not scheduled"
release.set()
for _ in range(20):
    second = mod.cached_probe_host("remote", {"remote": {"ssh": "remote"}}, "local")
    if second.get("reachable"):
        break
    time.sleep(0.1)
assert second.get("reachable") is True and second.get("latency_ms") == 777, second
print("ok: remote host probes refresh asynchronously so dashboard polling stays live")
PY
