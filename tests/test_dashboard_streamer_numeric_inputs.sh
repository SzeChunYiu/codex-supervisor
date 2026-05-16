#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import glob
import os
import pathlib
import stat
import subprocess
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_streamer_numeric", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_streamer_numeric", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

os.environ["CSUP_MAX_TMUX_SOCKET_SCAN"] = "3"
os.environ["CSUP_STREAMER_CMD_TIMEOUT_SECS"] = "0.5"
os.environ["CSUP_STREAMER_CMD_MAX_OUTPUT_BYTES"] = "1024"
source = mod._STREAMER_SCRIPT.split('# First message: full snapshot.', 1)[0]
ns = {}
exec(source, ns)

env_float = ns["env_float"]
safe_int = ns["safe_int"]
assert env_float("MISSING", 0.5, 0.01) == 0.5
os.environ["CSUP_STREAMER_TEST_FLOAT"] = "nan"
assert env_float("CSUP_STREAMER_TEST_FLOAT", 0.5, 0.01) == 0.5
assert safe_int("bad", -1, 0) == -1
assert safe_int("3", -1, 0) == 3
assert safe_int(float("inf"), -1, 0) == -1

# Socket enumeration must stream and stop at the configured cap so a malicious
# or corrupted tmux tmpdir cannot force unbounded stat work.
orig_isdir = os.path.isdir
orig_isfile = os.path.isfile
orig_stat = os.stat
orig_iglob = glob.iglob
stat_calls = []
try:
    os.path.isdir = lambda path: str(path).endswith(f"/tmux-{os.getuid()}")
    os.path.isfile = lambda path: False
    glob.iglob = lambda pattern: (f"/tmp/tmux-{os.getuid()}/sock{i}" for i in range(10))
    def fake_stat(path):
        stat_calls.append(path)
        class StatResult:
            st_mode = stat.S_IFSOCK
        return StatResult()
    os.stat = fake_stat
    assert ns["list_sockets"]() == ["sock0", "sock1", "sock2"]
    assert len(stat_calls) == 3, stat_calls
finally:
    os.path.isdir = orig_isdir
    os.path.isfile = orig_isfile
    os.stat = orig_stat
    glob.iglob = orig_iglob

class FakeSubprocess:
    TimeoutExpired = subprocess.TimeoutExpired
    CompletedProcess = subprocess.CompletedProcess

    def __init__(self):
        self.captured = []

    def run(self, cmd, capture_output=True, text=True, timeout=None):
        if cmd[:2] == ["tmux", "ls"]:
            return subprocess.CompletedProcess(cmd, 0, "demo\n", "")
        if cmd[:2] == ["tmux", "list-windows"]:
            return subprocess.CompletedProcess(cmd, 0, "0\twide\n", "")
        if cmd[:2] == ["tmux", "list-panes"]:
            return subprocess.CompletedProcess(
                cmd,
                0,
                "bad\t0\tcodex\twide\ttall\tBROKEN\n2\t0\tcodex\t120\t40\tGOOD\n",
                "",
            )
        if cmd[:2] == ["tmux", "capture-pane"]:
            self.captured.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, "live\n", "")
        if cmd[:2] == ["ps", "-axo"]:
            return subprocess.CompletedProcess(cmd, 0, "", "")
        return subprocess.CompletedProcess(cmd, 0, "", "")

assert ns["CMD_TIMEOUT_SECS"] == 0.5
assert ns["MAX_CMD_OUTPUT_BYTES"] == 1024
assert "select.select" in source, "streamer command capture should read pipes incrementally"
assert "subprocess.Popen" in source, "streamer command capture must not use unbounded subprocess.run capture_output"
assert "output limit exceeded" in source, "streamer command capture should fail closed on oversized output"

fake = FakeSubprocess()
ns["run_capture"] = fake.run
ns["list_sockets"] = lambda: ["default"]
result = ns["capture_all"]()
assert len(result) == 1, result
panes = result[0]["panes"]
assert len(panes) == 1, panes
assert panes[0]["index"] == 2 and panes[0]["width"] == 120 and panes[0]["height"] == 40, panes
assert all(":.bad" not in " ".join(cmd) for cmd in fake.captured), fake.captured

print("ok: dashboard streamer numeric inputs fail closed")
PY
