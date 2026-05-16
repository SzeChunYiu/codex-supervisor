#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import os
import pathlib
import subprocess
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_streamer_numeric", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_streamer_numeric", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

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

class FakeSubprocess:
    def __init__(self):
        self.captured = []

    def run(self, cmd, capture_output=True, text=True):
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

fake = FakeSubprocess()
ns["subprocess"] = fake
ns["list_sockets"] = lambda: ["default"]
result = ns["capture_all"]()
assert len(result) == 1, result
panes = result[0]["panes"]
assert len(panes) == 1, panes
assert panes[0]["index"] == 2 and panes[0]["width"] == 120 and panes[0]["height"] == 40, panes
assert all(":.bad" not in " ".join(cmd) for cmd in fake.captured), fake.captured

print("ok: dashboard streamer numeric inputs fail closed")
PY
