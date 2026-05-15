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

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

hosts = {
    "ng-content-lunarc": {
        "ssh": "lunarc",
        "scheduler": "slurm",
        "slurm_job_name": "ng-csup-a",
    }
}
project = {
    "name": "neural_grow",
    "path": "/remote/neural_grow",
    "hosts": {},
    "instances": [],
}
instances = {
    "neural_grow": [{
        "host": "ng-content-lunarc",
        "session": "ng-content-lunarc",
        "prompts": "codex-prompts-content.txt",
        "role": "remote-executor",
        "source": "project-config",
    }]
}

def fake_host_runner(host, hosts_arg, me, *, timeout, retries=0, slurm_job_id=""):
    assert host == "ng-content-lunarc"
    assert slurm_job_id == "3061936"
    def run(cmd):
        assert cmd[:3] == ["tmux", "ls", "-F"], cmd
        return subprocess.CompletedProcess(
            cmd,
            0,
            "csup-dashboard\nng-content-lunarc-station-1\nng-unity-lunarc-station-1\n",
            "",
        )
    return run

mod.host_runner = fake_host_runner
mod.add_live_station_instances(
    instances,
    [project],
    hosts,
    me="mac-mini",
    host_probe_cache={"ng-content-lunarc": {"reachable": True, "job_id": "3061936"}},
)

names = [i["session"] for i in instances["neural_grow"]]
assert "ng-content-lunarc" in names, names
assert "ng-content-lunarc-station-1" in names, names
assert "ng-unity-lunarc-station-1" not in names, names
added = [i for i in instances["neural_grow"] if i["session"] == "ng-content-lunarc-station-1"][0]
assert added["source"] == "live-station", added
assert added["prompts"] == "codex-prompts-content.txt", added
print("ok: dashboard adds live station tmux sessions for configured SLURM hosts")
PY

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import subprocess
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test_fallback", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test_fallback", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

hosts = {
    "ng-content-lunarc": {
        "ssh": "lunarc",
        "scheduler": "slurm",
        "slurm_job_name": "ng-csup-a",
    }
}
project = {
    "name": "neural_grow",
    "path": "/remote/neural_grow",
    "hosts": {},
    "instances": [],
}
instances = {
    mod.project_identity(project): [{
        "host": "ng-content-lunarc",
        "session": "ng-content-lunarc",
        "prompts": "codex-prompts-content.txt",
        "role": "remote-executor",
        "source": "project-config",
    }]
}

def fake_discover_tmux_sessions(host, hosts_arg, me, connection=None):
    return []

mod.discover_tmux_sessions = fake_discover_tmux_sessions
mod.add_live_station_instances(
    instances,
    [project],
    hosts,
    me="mac-mini",
    host_probe_cache={"ng-content-lunarc": {"reachable": True, "job_id": "3061936"}},
)

names = [i["session"] for i in instances[mod.project_identity(project)]]
assert names == [
    "ng-content-lunarc",
    "ng-content-lunarc-station-1",
    "ng-content-lunarc-station-2",
    "ng-content-lunarc-station-3",
    "ng-content-lunarc-station-4",
], names
print("ok: dashboard falls back to bounded station candidates when SLURM tmux discovery is empty")
PY

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test_cached", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test_cached", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

hosts = {
    "ng-content-lunarc": {
        "ssh": "lunarc",
        "scheduler": "slurm",
        "slurm_job_name": "ng-csup-a",
    }
}
project = {"name": "neural_grow", "path": "/remote/neural_grow", "hosts": {}, "instances": []}
instances = {
    mod.project_identity(project): [{
        "host": "ng-content-lunarc",
        "session": "ng-content-lunarc",
        "prompts": "codex-prompts-content.txt",
        "role": "remote-executor",
        "source": "project-config",
    }]
}
stream_key = mod.streaming_connection_key("lunarc", "3061936")
with mod.STREAMING_CACHE_LOCK:
    mod.STREAMING_CACHE[(stream_key, "ng-content-lunarc-station-3")] = {"panes": [{"index": 0}], "ts": 1.0}

called = {"discover": False}
def fail_discover(*args, **kwargs):
    called["discover"] = True
    raise AssertionError("tmux discovery should not run when streamer already has the live station session")

mod.discover_tmux_sessions = fail_discover
mod.add_live_station_instances(
    instances,
    [project],
    hosts,
    me="mac-mini",
    host_probe_cache={"ng-content-lunarc": {"reachable": True, "job_id": "3061936"}},
)

names = [i["session"] for i in instances[mod.project_identity(project)]]
assert "ng-content-lunarc-station-3" in names, names
assert not called["discover"], called
print("ok: dashboard reuses streaming-cache station sessions without blocking tmux discovery")
PY
