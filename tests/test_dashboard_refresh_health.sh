#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$SCRIPT" "$DASHBOARD" <<'PY'
import hashlib
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import socket
import socketserver
import subprocess
import sys
import threading
import time
import tempfile

script = pathlib.Path(sys.argv[1])
dashboard_path = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

with mod.CACHE_LOCK:
    mod.CACHE["refresh_interval_secs"] = 0.5
    mod.CACHE["updated_at"] = time.time()
    mod.CACHE["projects"] = [{
        "name": "demo",
        "instances": [{
            "host": "local",
            "session": "demo",
            "panes": [
                {"index": 0, "state": "working", "lane": "BUGS", "tail": ["working"]},
                {"index": 1, "state": "idle", "lane": "BUGS", "tail": ["› prompt"]},
                {"index": 2, "state": "rate-limited", "lane": "PERF", "tail": ["usage limit"]},
            ],
        }],
    }]
    mod.CACHE["projects"].append({
        "name": "second project",
        "instances": [{
            "host": "remote",
            "session": "second",
            "panes": [{"index": 0, "state": "working", "lane": "X", "tail": ["other"]}],
        }],
    })
project_state = mod.state_payload("demo")
assert [p["name"] for p in project_state["projects"]] == ["demo"], project_state
assert {p["slug"] for p in project_state["project_index"]} == {"demo", "second-project"}, project_state
assert project_state["project_index"][0]["panes"] == 3, project_state
with mod.CACHE_LOCK:
    mod.CACHE["projects"][0]["instances"][0]["panes"][0]["tail"] = ["a", "b", "c"]
    mod.CACHE["projects"][0]["instances"][0]["panes"][0]["tail_html"] = "<b>rich</b>"
compact_project_state = mod.state_payload("demo", compact=True, tail_lines=2)
compact_pane = compact_project_state["projects"][0]["instances"][0]["panes"][0]
assert compact_pane["tail"] == ["b", "c"], compact_pane
assert "tail_html" not in compact_pane, compact_pane
with mod.CACHE_LOCK:
    mod.CACHE["projects"] = mod.CACHE["projects"][:1]
health = mod.health_payload()
assert health.get("refresh_interval_secs") == 0.5, health
assert health.get("source", {}).get("path", "").endswith("csup-dashboard"), health
assert health.get("source", {}).get("sha256"), health
large_source = pathlib.Path(tempfile.mkdtemp()) / "large-dashboard"
large_source.write_bytes((b"0123456789abcdef" * 200000) + b"tail")
large_info = mod.dashboard_source_info(large_source)
assert large_info["size_bytes"] == large_source.stat().st_size, large_info
assert large_info["sha256"] == hashlib.sha256(large_source.read_bytes()).hexdigest()[:16], large_info
capped_large_info = mod.dashboard_source_info(large_source)
old_hash_cap = mod.MAX_SOURCE_HASH_BYTES
try:
    mod.MAX_SOURCE_HASH_BYTES = 1024
    capped_large_info = mod.dashboard_source_info(large_source)
finally:
    mod.MAX_SOURCE_HASH_BYTES = old_hash_cap
assert capped_large_info["sha256"] == "", capped_large_info
assert "too large to hash" in capped_large_info.get("error", ""), capped_large_info
assert health.get("status") == "degraded", health
assert health.get("state_counts", {}).get("working") == 1, health
assert health.get("state_counts", {}).get("idle") == 1, health
assert health.get("state_counts", {}).get("rate-limited") == 1, health
assert health.get("pane_issue_count") == 2, health
assert any("pane-idle" in issue.get("reasons", []) for issue in health.get("pane_issues", [])), health
assert any("rate-limited" in issue.get("reasons", []) for issue in health.get("pane_issues", [])), health

system_calls = {"n": 0}
mod.known_hosts = lambda: {}
mod.this_host_name = lambda hosts: "local"
mod.list_projects = lambda: []
mod.collect_token_usage = lambda now=None, force=False: {}
mod.collect_tool_call_usage = lambda now=None, force=False: {}

def fake_system_health(hosts=None, me=None, host_probe_cache=None):
    system_calls["n"] += 1
    return {"status": "ok", "updated_at": 100 + system_calls["n"], "cpu": {}, "memory": {}, "disk": {}, "storage": {"devices": []}}

mod.collect_system_health = fake_system_health
mod.SYSTEM_HEALTH_CACHE = {"key": None, "updated_at": 0, "value": None}
system_calls["n"] = 0
mod.collect_system_health_cached({}, "local", {"remote": {"reachable": True, "latency_ms": 10}}, now=100)
mod.collect_system_health_cached({}, "local", {"remote": {"reachable": True, "latency_ms": 999}}, now=101)
assert system_calls["n"] == 1, system_calls

default_refresh = subprocess.check_output(
    ["bash", "-c", f"source {script}; printf '%s' \"$DASHBOARD_REFRESH\""],
    env={**os.environ, "CODEX_SUPERVISOR_TEST_SOURCE": "1"},
    text=True,
).strip()
assert default_refresh == "0.2", default_refresh

sanitized_dashboard_knobs = subprocess.check_output(
    [
        "bash",
        "-c",
        f"source {script}; printf '%s|%s|%s' \"$DASHBOARD_PORT\" \"$DASHBOARD_LINES\" \"$DASHBOARD_REFRESH\"",
    ],
    env={
        **os.environ,
        "CODEX_SUPERVISOR_TEST_SOURCE": "1",
        "CODEX_SUPERVISOR_DASHBOARD_PORT": "bad",
        "CODEX_SUPERVISOR_DASHBOARD_LINES": "bad",
        "CODEX_SUPERVISOR_DASHBOARD_REFRESH": "bad",
    },
    text=True,
).strip()
assert sanitized_dashboard_knobs == "7777|12|0.2", sanitized_dashboard_knobs

with tempfile.TemporaryDirectory() as tmp:
    launcher_link = pathlib.Path(tmp) / "codex-supervisor.sh"
    launcher_link.symlink_to(script)
    default_dashboard_cmd = subprocess.check_output(
        ["bash", "-c", 'source "$1"; printf "%s" "$DASHBOARD_CMD"', "_", str(launcher_link)],
        env={**os.environ, "CODEX_SUPERVISOR_TEST_SOURCE": "1"},
        text=True,
    ).strip()
assert pathlib.Path(default_dashboard_cmd).resolve() == dashboard_path.resolve(), default_dashboard_cmd


class QuietServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, *args, **kwargs):
        self.errors = []
        super().__init__(*args, **kwargs)

    def handle_error(self, request, client_address):
        self.errors.append(sys.exc_info()[1])


class BrokenClientHandler(mod.Handler):
    def do_GET(self):
        raise BrokenPipeError("test client closed")


with QuietServer(("127.0.0.1", 0), BrokenClientHandler) as srv:
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()
    with socket.create_connection(("127.0.0.1", srv.server_address[1]), timeout=2) as sock:
        sock.sendall(b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    time.sleep(0.1)
    srv.shutdown()
assert not srv.errors, srv.errors


def dashboard_ok(payload, desired="0.5", cmd=dashboard_path, extra_env=None):
    return dashboard_ok_body(json.dumps(payload).encode(), desired=desired, cmd=cmd, extra_env=extra_env)

def dashboard_ok_body(body, desired="0.5", cmd=dashboard_path, extra_env=None):
    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            _ = self.request.recv(4096)
            self.request.sendall(
                b"HTTP/1.1 200 OK\r\n"
                b"Content-Type: application/json\r\n"
                + f"Content-Length: {len(body)}\r\n\r\n".encode()
                + body
            )

    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", 0), Handler) as srv:
        port = str(srv.server_address[1])
        thread = threading.Thread(target=srv.serve_forever, daemon=True)
        thread.start()
        env = os.environ.copy()
        env.update({
            "CODEX_SUPERVISOR_TEST_SOURCE": "1",
            "CODEX_SUPERVISOR_DASHBOARD_PORT": port,
            "CODEX_SUPERVISOR_DASHBOARD_REFRESH": desired,
            "CODEX_SUPERVISOR_DASHBOARD_CMD": str(cmd),
        })
        if extra_env:
            env.update(extra_env)
        rc = subprocess.run(
            ["bash", "-c", f"source {script}; dashboard_http_ok"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        srv.shutdown()
        return rc == 0


script_text = script.read_text()
assert "read(MAX_HTTP_BYTES + 1)" in script_text, "dashboard health HTTP reads must detect oversized responses"
assert "r.read(1_000_000)" not in script_text, "dashboard HTTP reads must not silently truncate at exactly 1 MB"
assert "dashboard refresh response too large" in script_text, "manual refresh response should fail closed when oversized"
assert "def read_json_response" in script_text, "dashboard health JSON reads should share a bounded helper"
assert 'hashlib.sha256(open(expected_cmd, "rb").read())' not in script_text, "dashboard source hash must stream file chunks"
assert "def file_sha256_prefix" in script_text, "dashboard source hash helper should stream chunks"
assert "CODEX_SUPERVISOR_DASHBOARD_HASH_MAX_BYTES" in script_text, "dashboard source hash should have a safety cap"
assert "dashboard source file too large to hash" in script_text, "oversized dashboard source hashes should fail closed"

dashboard_sha = mod.file_sha256_prefix(dashboard_path)
base = {"status": "ok", "panes": 1, "source": {"path": str(dashboard_path), "sha256": dashboard_sha}}
assert dashboard_ok({**base, "refresh_interval_secs": 0.2}, desired="0.2")
assert dashboard_ok({**base, "refresh_interval_secs": 0.2}, desired="0.2", extra_env={"CODEX_SUPERVISOR_DASHBOARD_HASH_MAX_BYTES": "bad"}), "invalid hash cap env should sanitize to the safe default"
large_base = {"status": "ok", "panes": 1, "refresh_interval_secs": 0.5, "source": {"path": str(large_source), "sha256": large_info["sha256"]}}
assert not dashboard_ok(large_base, cmd=large_source, extra_env={"CODEX_SUPERVISOR_DASHBOARD_HASH_MAX_BYTES": "1024"}), "oversized dashboard source hash should fail closed"
oversized_body = json.dumps({**base, "refresh_interval_secs": 0.2}).encode() + (b" " * 1_000_001)
assert not dashboard_ok_body(oversized_body, desired="0.2"), "oversized health response should fail closed"
assert not dashboard_ok({**base, "refresh_interval_secs": 0.5}, desired="0.2"), "0.5s dashboard is too slow for requested livestream cadence"
assert dashboard_ok({**base, "refresh_interval_secs": 0.5})
assert not dashboard_ok({**base, "refresh_interval_secs": 1.0}), "1s dashboard is too slow for a requested 0.5s real-time cadence"
assert not dashboard_ok({**base, "refresh_interval_secs": 30.0}), "slow dashboard should be replaced"
assert not dashboard_ok({"status": "ok", "panes": 1, "refresh_interval_secs": 0.5}), "untraceable dashboards without source path should be replaced"
assert not dashboard_ok({**base, "refresh_interval_secs": 0.5, "source": {"path": str(dashboard_path.with_name("old-csup-dashboard"))}}), "dashboard from the wrong source path should be replaced"
assert not dashboard_ok(base), "old dashboards without refresh interval should be replaced"
assert not dashboard_ok({**base, "refresh_interval_secs": 0.5, "source": {"path": str(dashboard_path), "sha256": "wrong-sha"}}), "same-path stale dashboard binaries should be replaced"
print("ok: dashboard health exposes and enforces refresh interval")
PY
