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

dashboard_path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

calls = []
block_background = {"enabled": False}
fail_capture = {"enabled": False}
malformed_pane_listing = {"enabled": False}
background_started = threading.Event()
background_release = threading.Event()
ansi = "\n".join(f"line {i}" for i in range(1, 11)) + "\n"

def fake_host_runner(host, hosts, me, timeout, retries=1, slurm_job_id=""):
    def runner(cmd):
        calls.append(cmd)
        if block_background["enabled"]:
            background_started.set()
            background_release.wait(2)
        if fail_capture["enabled"]:
            return subprocess.CompletedProcess(cmd, 1, "", "session not found")
        if cmd[:2] == ["python3", "-c"]:
            payload = [
                {
                    "index": 0,
                    "ordinal": 0,
                    "dead": False,
                    "cmd": "codex",
                    "width": 120,
                    "height": 10,
                    "title": "FAST",
                    "ansi": ansi,
                },
                {
                    "index": 1,
                    "ordinal": 1,
                    "dead": False,
                    "cmd": "codex",
                    "width": 120,
                    "height": 10,
                    "title": "TAIL",
                    "ansi": ansi,
                },
            ]
            return subprocess.CompletedProcess(cmd, 0, json.dumps(payload), "")
        if cmd[:2] == ["tmux", "list-sessions"]:
            return subprocess.CompletedProcess(cmd, 0, "demo-session\n", "")
        if cmd[:2] == ["tmux", "list-panes"]:
            if malformed_pane_listing["enabled"]:
                return subprocess.CompletedProcess(
                    cmd,
                    0,
                    "bad|0|codex|wide|tall|BROKEN\n2|0|codex|120|10|GOOD\n",
                    "",
                )
            return subprocess.CompletedProcess(
                cmd,
                0,
                "0|0|codex|120|10|FAST\n1|0|codex|120|10|TAIL\n",
                "",
            )
        if cmd[:2] == ["tmux", "capture-pane"]:
            return subprocess.CompletedProcess(cmd, 0, ansi, "")
        return subprocess.CompletedProcess(cmd, 1, "", "unexpected command")
    return runner

mod.host_runner = fake_host_runner
mod.DEFAULT_REFRESH = 0.5
mod.REMOTE_CAPTURE_CACHE_SECS = 2.0
mod.REMOTE_INITIAL_CAPTURE_ASYNC = False
mod.INSTANCE_CAPTURE_CACHE.clear()

panes = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "demo-session",
    3,
    {0: "FAST", 1: "TAIL"},
)

assert panes is not None, panes
assert len(calls) == 1 and calls[0][:2] == ["python3", "-c"], calls
for pane in panes:
    assert len(pane["tail"]) == 3, pane
    assert pane["tail"] == ["line 8", "line 9", "line 10"], pane
    assert "line 7" not in pane["tail_html"], pane["tail_html"]
    assert pane.get("tail_line_count") == 3, pane

html = mod.INDEX_HTML
source = dashboard_path.read_text()
assert "const UI_REFRESH_MS = 200" in html, "browser should poll five times per second for livestream-like panes"
assert 'CSUP_DASHBOARD_REMOTE_CAPTURE_CACHE_SECS", 0.5' in source, "remote captures should refresh at least twice per second by default"
assert "Open latest tail" in html, "pane action should describe tail-only output, not full scrollback"
assert "pre.innerHTML = paneTailHtml(pane)" in html, "pane updates should overwrite the visible output"
assert '"-2000"' not in source, "on-demand pane endpoint should not fetch full scrollback by default"
assert "ansi_lines[-pane_lines:]" in source, "on-demand pane endpoint should return latest tail only"
assert "lines = int(sys.argv[2])" not in source, "remote capture snippet should sanitize line counts"

malformed_pane_listing["enabled"] = True
local = mod.capture_session(
    "local-host",
    {"local-host": {}},
    "local-host",
    "demo-session",
    "bad",
    {2: "GOOD"},
)
malformed_pane_listing["enabled"] = False
assert local is not None and len(local) == 1, local
assert local[0]["index"] == 2 and local[0]["lane"] == "GOOD", local
calls.clear()

cached = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "demo-session",
    3,
    {0: "FAST", 1: "TAIL"},
)
assert cached == panes, cached
assert len(calls) == 0, "fresh remote panes should be reused briefly instead of blocking every UI refresh"

for entry in mod.INSTANCE_CAPTURE_CACHE.values():
    entry["updated_at"] = time.time() - 10
block_background["enabled"] = True
t0 = time.perf_counter()
stale = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "demo-session",
    3,
    {0: "FAST", 1: "TAIL"},
)
elapsed = time.perf_counter() - t0
assert stale == panes, stale
assert elapsed < 0.2, f"stale remote cache should return immediately, took {elapsed:.3f}s"
assert background_started.wait(0.5), "stale remote cache should schedule a background refresh"
background_release.set()
block_background["enabled"] = False
time.sleep(0.1)

for entry in mod.INSTANCE_CAPTURE_CACHE.values():
    entry["updated_at"] = time.time() - 10
fail_capture["enabled"] = True
stale_before_failure = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "demo-session",
    3,
    {0: "FAST", 1: "TAIL"},
)
assert stale_before_failure == panes, stale_before_failure
time.sleep(0.2)
stale_after_failure = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "demo-session",
    3,
    {0: "FAST", 1: "TAIL"},
)
assert stale_after_failure is not None, stale_after_failure
assert stale_after_failure[0].get("capture_stale") is True, stale_after_failure
assert stale_after_failure[0].get("capture_error"), stale_after_failure
fail_capture["enabled"] = False

calls.clear()
limited_ansi = "You've hit your usage\nlimit. Try again later.\n\n› prompt\n"
ansi = limited_ansi
mod.INSTANCE_CAPTURE_CACHE.clear()
limited = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "limited-session",
    4,
    {0: "LIMITED", 1: "OTHER"},
)
assert limited is not None, limited
assert limited[0]["state"] == "rate-limited", limited[0]

calls.clear()
mod.INSTANCE_CAPTURE_CACHE.clear()
fail_capture["enabled"] = True
missing = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "missing-session",
    3,
    {0: "MISSING"},
)
again_missing = mod.capture_session(
    "remote-host",
    {"remote-host": {"ssh": "remote-host"}},
    "local-host",
    "missing-session",
    3,
    {0: "MISSING"},
)
fail_capture["enabled"] = False
assert missing is None and again_missing is None
assert len(calls) == 1, "remote missing-session failures should be cached briefly"
print("ok: dashboard captures one remote batch, stores latest tail only, and refreshes faster")
PY
