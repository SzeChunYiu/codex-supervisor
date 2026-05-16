#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import concurrent.futures as cf
import os
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

hosts = {
    "lunarc": {
        "ssh": "lunarc",
        "scheduler": "slurm",
        "slurm_job_name": "mcaccel-sup",
        "remote_env": "source /projects/hep/fs10/shared/codex-tooling/env-shared.sh",
    },
    "lunarc-c": {
        "ssh": "lunarc-babbloo",
        "scheduler": "slurm",
        "slurm_job_name": "mcaccel-sup",
    }
}
seen = []
squeue_calls = {"n": 0}
ssh_true_calls = {"n": 0}

def fake_run_stable(cmd, *, timeout, retries=1):
    seen.append(cmd)
    joined = " ".join(cmd)
    if " true" in joined:
        ssh_true_calls["n"] += 1
        return subprocess.CompletedProcess(cmd, 0, "", "")
    if "squeue" in joined:
        squeue_calls["n"] += 1
        return subprocess.CompletedProcess(cmd, 0, "3041294|cx04\n", "")
    return subprocess.CompletedProcess(cmd, 0, "captured\n", "")

orig_max_run_stable = mod.MAX_RUN_STABLE_OUTPUT_BYTES
mod.MAX_RUN_STABLE_OUTPUT_BYTES = 1024
small_capture = mod.run_stable([sys.executable, "-c", "print('ok')"], timeout=2, retries=0)
assert small_capture.returncode == 0 and small_capture.stdout.strip() == "ok", small_capture
huge_capture = mod.run_stable(
    [sys.executable, "-c", "import sys; sys.stdout.write('x' * 4096)"],
    timeout=2,
    retries=0,
)
assert huge_capture.returncode == 124 and huge_capture.stderr == "output limit exceeded", huge_capture
mod.MAX_RUN_STABLE_OUTPUT_BYTES = orig_max_run_stable

source_text = path.read_text()
remote_script = source_text.split("if host != me:", 1)[1].split("remote_text = r.stdout", 1)[0]
assert "CSUP_REMOTE_CAPTURE_CMD_TIMEOUT_SECS" in remote_script
assert "CSUP_REMOTE_CAPTURE_CMD_MAX_OUTPUT_BYTES" in remote_script
assert "def run_capture(cmd):" in remote_script
assert "subprocess.run(cmd, capture_output=True, text=True)" not in remote_script
assert "subprocess.run(tx(" not in remote_script
assert "subprocess.Popen" in remote_script
assert "select.select" in remote_script
assert "output limit exceeded" in remote_script

mod.run_stable = fake_run_stable
probe = mod.probe_host("lunarc", hosts, me="mac-mini")
assert probe["reachable"] is True, probe
assert probe["job_id"] == "3041294", probe
assert probe["node"] == "cx04", probe
assert squeue_calls["n"] == 1, squeue_calls
assert ssh_true_calls["n"] == 0, "SLURM probe should combine SSH reachability and squeue"
runner = mod.host_runner("lunarc", hosts, me="mac-mini", slurm_job_id=probe["job_id"])
assert runner is not None
result = runner(["tmux", "capture-pane", "-t", "session:.1", "-p"])
assert result.stdout == "captured\n"
assert squeue_calls["n"] == 1, "cached job_id should avoid a second squeue call"
remote_cmd = seen[-1][-1]
assert "srun --jobid=3041294 --overlap" in remote_cmd, remote_cmd
assert "env-shared.sh" in remote_cmd, remote_cmd
assert "tmux capture-pane -t session:.1 -p" in remote_cmd, remote_cmd

os.environ["CSUP_DASHBOARD_SRUN_TIMEOUT_SECS"] = "bad"
result = runner(["tmux", "display-message", "-p", "ok"])
assert result.stdout == "captured\n"
assert "timeout 20s srun --jobid=3041294" in seen[-1][-1], seen[-1][-1]
os.environ.pop("CSUP_DASHBOARD_SRUN_TIMEOUT_SECS", None)

probe_alias = mod.probe_host("lunarc-c", hosts, me="mac-mini")
assert probe_alias["reachable"] is True, probe_alias
assert seen[-1][-2] == "lunarc", f"LUNARC aliases should reuse the pre-authenticated lunarc socket: {seen[-1]}"
runner_alias = mod.host_runner("lunarc-c", hosts, me="mac-mini", slurm_job_id=probe_alias["job_id"])
assert runner_alias is not None
runner_alias(["tmux", "list-panes", "-t", "demo"])
assert seen[-1][-2] == "lunarc", f"LUNARC alias runner should call ssh lunarc: {seen[-1]}"

active = {"n": 0, "max": 0}
lock = threading.Lock()

def slow_run_stable(cmd, *, timeout, retries=1):
    with lock:
        active["n"] += 1
        active["max"] = max(active["max"], active["n"])
    time.sleep(0.05)
    with lock:
        active["n"] -= 1
    return subprocess.CompletedProcess(cmd, 0, "captured\n", "")

mod.run_stable = slow_run_stable
runner = mod.host_runner("lunarc", hosts, me="mac-mini", slurm_job_id="3041294")
with cf.ThreadPoolExecutor(max_workers=3) as ex:
    list(ex.map(lambda _: runner(["tmux", "list-panes", "-t", "demo"]), range(3)))
assert active["max"] == 1, f"LUNARC SSH+srun calls should be serialized per ssh target, saw {active['max']}"

orig_host_runner = mod.host_runner
orig_streaming = mod.CSUP_STREAMING
orig_max_remote_json = mod.MAX_REMOTE_JSON_CHARS
orig_max_capture_panes = mod.MAX_CAPTURE_PANES
mod.CSUP_STREAMING = False
mod.MAX_REMOTE_JSON_CHARS = 8
def oversized_runner(*args, **kwargs):
    def run(cmd):
        return subprocess.CompletedProcess(cmd, 0, "[" + ("x" * 32), "")
    return run
mod.host_runner = oversized_runner
mod.INSTANCE_CAPTURE_CACHE.clear()
assert mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "demo", 5, _bypass_cache=True) is None
cache_values = list(mod.INSTANCE_CAPTURE_CACHE.values())
assert cache_values and cache_values[-1].get("last_error") == "remote capture JSON too large", cache_values
mod.host_runner = orig_host_runner
mod.CSUP_STREAMING = orig_streaming
mod.MAX_REMOTE_JSON_CHARS = orig_max_remote_json

mod.CSUP_STREAMING = False
mod.MAX_CAPTURE_PANES = 2
def many_panes_runner(*args, **kwargs):
    def run(cmd):
        return subprocess.CompletedProcess(cmd, 0, '{"panes": [' + ",".join(
            '{"index": %d, "ansi": "pane%d"}' % (i, i) for i in range(5)
        ) + ']}', "")
    return run
mod.host_runner = many_panes_runner
mod.INSTANCE_CAPTURE_CACHE.clear()
panes = mod.capture_session("remote", {"remote": {"ssh": "remote"}}, "local", "demo", 5, _bypass_cache=True)
assert [p["index"] for p in panes] == [0, 1], panes
mod.host_runner = orig_host_runner
mod.CSUP_STREAMING = orig_streaming
mod.MAX_CAPTURE_PANES = orig_max_capture_panes
print("ok: dashboard wraps LUNARC captures with ssh+srun active allocation and cached job id")
PY
