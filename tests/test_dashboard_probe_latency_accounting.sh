#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
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

def fake_run_stable(cmd, *, timeout, retries=1):
    return subprocess.CompletedProcess(cmd, 0, "3041294|cx04\n", "")

mod.run_stable = fake_run_stable
assert mod.ssh_target_lock("lunarc") is mod.ssh_target_lock("lunarc-babbloo")
assert mod.ssh_target_lock("lunarc") is mod.ssh_target_lock("lunarc-cn018")
lock = mod.ssh_target_lock("lunarc")
lock.acquire()
assert mod.ssh_target_busy("lunarc-babbloo")
assert mod.ssh_target_busy("lunarc-cn018")
result = {}

def probe():
    result["value"] = mod.probe_host(
        "lunarc",
        {"lunarc": {"ssh": "lunarc", "scheduler": "slurm", "slurm_job_name": "mcaccel-sup"}},
        "mac-mini",
    )

thread = threading.Thread(target=probe)
thread.start()
time.sleep(0.25)
lock.release()
thread.join(2.0)
assert not thread.is_alive(), "probe thread did not finish"
value = result["value"]
assert value["reachable"] is True, value
assert value["node"] == "cx04", value
assert value["latency_ms"] < 100, value
assert value["queue_wait_ms"] >= 200, value
assert "ssh queue wait" in mod.INDEX_HTML, "UI should explain lock queue wait separately from ping latency"

calls = {"n": 0}
def should_not_probe(host, hosts, me):
    calls["n"] += 1
    raise AssertionError("stale probe should be deferred while ssh target is busy")

mod.probe_host = should_not_probe
key = ("slurm-job", "lunarc", "mcaccel-sup", "mac-mini")
mod.HOST_PROBE_CACHE.clear()
mod.HOST_PROBE_CACHE[key] = {
    "updated_at": time.time() - 99,
    "value": {"reachable": True, "latency_ms": 626, "queue_wait_ms": 0, "error": "", "job_id": "3041294", "node": "cx04"},
    "refreshing": False,
}
lock = mod.ssh_target_lock("lunarc")
lock.acquire()
try:
    stale = mod.cached_probe_host(
        "lunarc",
        {"lunarc": {"ssh": "lunarc", "scheduler": "slurm", "slurm_job_name": "mcaccel-sup"}},
        "mac-mini",
        now=time.time(),
    )
finally:
    lock.release()
assert calls["n"] == 0, calls
assert stale["latency_ms"] == 626 and stale.get("probe_stale") and stale.get("probe_deferred"), stale

# SLURM aliases that share the LUNARC control master and job name should share
# one probe cache entry. Otherwise lunarc-b/lunarc-c/lunarc-d each start their
# own squeue probe and can make the dashboard mark only some aliases offline
# during a transient mux refusal.
alias_hosts = {
    "lunarc": {"ssh": "lunarc", "scheduler": "slurm", "slurm_job_name": "mcaccel-sup"},
    "lunarc-d": {"ssh": "lunarc-babbloo", "scheduler": "slurm", "slurm_job_name": "mcaccel-sup"},
}
mod.HOST_PROBE_CACHE.clear()
mod.HOST_PROBE_CACHE[key] = {
    "updated_at": time.time(),
    "value": {"reachable": True, "latency_ms": 626, "queue_wait_ms": 0, "error": "", "job_id": "3041294", "node": "cx04"},
    "refreshing": False,
}
aliased = mod.cached_probe_host("lunarc-d", alias_hosts, "mac-mini", now=time.time())
assert aliased["reachable"] is True and aliased["job_id"] == "3041294", aliased

def transient_mux_refusal(host, hosts, me):
    return {
        "reachable": False,
        "latency_ms": 1,
        "queue_wait_ms": 0,
        "error": "mux_client_request_session: session request failed",
    }

mod.probe_host = transient_mux_refusal
mod.refresh_host_probe_cache(key, "lunarc-d", alias_hosts, "mac-mini")
preserved = mod.HOST_PROBE_CACHE[key]["value"]
assert preserved["reachable"] is True, preserved
assert preserved.get("probe_stale") is True and preserved.get("probe_deferred") is True, preserved
assert "mux_client_request_session" in preserved.get("last_probe_error", ""), preserved

# SLURM streaming should be one per allocation/job, not one per SSH alias.
created = []

class FakeStreamingConnection:
    def __init__(self, ssh_target, job_id):
        self.ssh_target = ssh_target
        self.job_id = job_id
        created.append((ssh_target, job_id, self))

mod.STREAMING_CONNECTIONS.clear()
mod.StreamingConnection = FakeStreamingConnection
conn_a = mod._get_or_create_streaming_conn("lunarc", "3047628")
conn_b = mod._get_or_create_streaming_conn("lunarc-babbloo", "3047628")
conn_c = mod._get_or_create_streaming_conn("lunarc-cn018", "3041795")
assert conn_a is conn_b, "aliases for the same LUNARC job should share one streamer"
assert conn_c is not conn_a, "different SLURM jobs must keep separate streamers"
assert [(x[0], x[1]) for x in created] == [("lunarc", "3047628"), ("lunarc-cn018", "3041795")], created

# While a SLURM streamer is warming, do not fall through to per-session srun
# fallback. The fallback is slower and can starve streamer startup by holding
# the shared LUNARC SSH lock repeatedly.
class WarmingStream:
    def is_ready(self):
        return False

    def get_session(self, session):
        raise AssertionError("not-ready stream should not be queried for a session")

fallback_calls = {"n": 0}

def fake_host_runner(host, hosts, me, **kwargs):
    def runner(cmd):
        fallback_calls["n"] += 1
        return subprocess.CompletedProcess(cmd, 0, '{"panes": [], "monitor": {"known": true}}', "")
    return runner

mod.StreamingConnection = FakeStreamingConnection
mod._get_or_create_streaming_conn = lambda ssh_target, job_id: WarmingStream()
mod.host_runner = fake_host_runner
mod.CSUP_STREAMING = True
mod.REMOTE_INITIAL_CAPTURE_ASYNC = False
mod.INSTANCE_CAPTURE_CACHE.clear()
warming_value = mod.capture_session(
    "lunarc",
    {"lunarc": {"ssh": "lunarc", "scheduler": "slurm"}},
    "mac-mini",
    "weather-market-batch12",
    12,
    connection={"job_id": "3047628"},
)
assert warming_value is None, warming_value
assert fallback_calls["n"] == 0, "warming streamer should not trigger fallback srun capture"
print("ok: dashboard cx04 probe latency excludes serialized ssh queue wait")
PY
