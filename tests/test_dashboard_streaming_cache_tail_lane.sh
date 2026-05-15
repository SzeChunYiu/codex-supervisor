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

ansi = "\n".join(["old 1", "old 2", "new 3", "new 4", "new 5"]) + "\n"

class ReadyStream:
    def is_ready(self):
        return True

    def get_session(self, session):
        assert session == "remote-session"
        return {
            "ts": 12345.0,
            "panes": [{
                "index": 1,
                "dead": False,
                "cmd": "codex",
                "width": 160,
                "height": 50,
                "title": "codex",
                "ansi": ansi,
            }],
        }

mod.host_runner = lambda host, hosts, me, timeout, retries=1, slurm_job_id="": (
    lambda cmd: subprocess.CompletedProcess(cmd, 1, "", "streaming path should not run fallback capture")
)
mod._get_or_create_streaming_conn = lambda ssh_target, job_id: ReadyStream()
mod.INSTANCE_CAPTURE_CACHE.clear()

panes = mod.capture_session(
    "remote-slurm",
    {"remote-slurm": {"ssh": "lunarc", "scheduler": "slurm"}},
    "local-host",
    "remote-session",
    2,
    {1: "STREAM-LANE"},
    {"job_id": "123"},
)

assert panes is not None, panes
assert len(panes) == 1, panes
pane = panes[0]
assert pane["lane"] == "STREAM-LANE", pane
assert pane["tail"] == ["new 4", "new 5"], pane
assert pane["tail_line_count"] == 2, pane
assert "old 1" not in pane["tail_html"], pane["tail_html"]
assert "new 5" in pane["tail_html"], pane["tail_html"]
print("ok: streaming cache renders requested tail lines and lane labels")
PY
