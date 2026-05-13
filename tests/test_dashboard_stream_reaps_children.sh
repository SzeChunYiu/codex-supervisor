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


class EmptyProc:
    def __init__(self):
        self.stdout = iter(())
        self.wait_called = False

    def wait(self, timeout=None):
        self.wait_called = True
        return 255


conn = mod.StreamingConnection.__new__(mod.StreamingConnection)
conn.ssh_target = "lunarc"
conn.job_id = "3047628"
conn.cache_key = ("lunarc", "3047628")
conn._alive = False
conn._ready = True
conn._proc = EmptyProc()
conn._last_heartbeat = 0.0
conn._consecutive_failures = 0
conn._given_up = False
conn._read_loop()
assert conn._proc.wait_called, "streaming child must be waited/reaped when stdout closes"


class HangingProc:
    def __init__(self):
        self.terminated = False
        self.killed = False
        self.wait_calls = 0

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True

    def wait(self, timeout=None):
        self.wait_calls += 1
        if self.wait_calls == 1:
            raise subprocess.TimeoutExpired(["ssh"], timeout)
        return -9


conn2 = mod.StreamingConnection.__new__(mod.StreamingConnection)
conn2._alive = True
conn2._proc = HangingProc()
conn2.close()
assert conn2._proc.terminated, "close should terminate the streaming ssh subprocess"
assert conn2._proc.killed, "close should kill a streaming subprocess that ignores terminate"
assert conn2._proc.wait_calls == 2, "close should wait after terminate and after kill to avoid zombies"

conn3 = mod.StreamingConnection.__new__(mod.StreamingConnection)
conn3.ssh_target = "lunarc"
conn3.job_id = "3047628"
conn3._last_error = ""
conn3._stderr_loop(iter(["mux_client_request_session: session request failed\n", "\n"]))
assert "mux_client_request_session" in conn3._last_error, "stream stderr should be drained and retained for diagnostics"
print("ok: dashboard stream subprocesses are reaped on EOF and close")
PY
