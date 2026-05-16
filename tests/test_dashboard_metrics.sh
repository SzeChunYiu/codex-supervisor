#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

python3 - "$DASHBOARD" "$TMPDIR" <<'PY'
import importlib.machinery
import importlib.util
import inspect
import json
import pathlib
import subprocess
import sys
import time


dashboard_path = pathlib.Path(sys.argv[1])
tmp = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

sessions = tmp / "sessions"
current = sessions / "2026" / "05" / "11"
old = sessions / "2026" / "05" / "01"
current.mkdir(parents=True)
old.mkdir(parents=True)

# One file has two token_count events; only the latest event should count for
# that session file, otherwise totals inflate on every refresh.
(current / "rollout-a.jsonl").write_text("\n".join([
    json.dumps({
        "timestamp": "2026-05-11T00:00:30.000Z",
        "type": "response_item",
        "payload": {
            "type": "function_call",
            "name": "exec_command",
            "call_id": "call_a",
        },
    }),
    json.dumps({
        "timestamp": "2026-05-11T00:00:31.000Z",
        "type": "response.function_call_arguments.delta",
        "delta": "{\"cmd\"",
    }),
    json.dumps({
        "timestamp": "2026-05-11T00:00:00.000Z",
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 1, "reasoning_output_tokens": 0, "total_tokens": 2},
                "last_token_usage": {"total_tokens": 2},
                "model_context_window": 258400,
            },
            "rate_limits": {"primary": {"used_percent": 7}, "secondary": {"used_percent": 8}, "plan_type": "plus"},
        },
    }),
    json.dumps({
        "timestamp": "2026-05-11T00:01:00.000Z",
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {"input_tokens": 100, "cached_input_tokens": 25, "output_tokens": 10, "reasoning_output_tokens": 3, "total_tokens": 110},
                "last_token_usage": {"total_tokens": 11},
                "model_context_window": 258400,
            },
            "rate_limits": {"primary": {"used_percent": 55}, "secondary": {"used_percent": 22}, "plan_type": "plus"},
        },
    }),
    json.dumps({
        "timestamp": "2026-05-11T00:01:30.000Z",
        "type": "response_item",
        "payload": {
            "type": "function_call",
            "name": "browser_click",
            "call_id": "call_b",
        },
    }),
]) + "\n")

(current / "rollout-b.jsonl").write_text("\n".join([
    json.dumps({
        "timestamp": "2026-05-11T00:02:00.000Z",
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {"input_tokens": 5, "cached_input_tokens": 2, "output_tokens": 7, "reasoning_output_tokens": 1, "total_tokens": 12},
                "last_token_usage": {"total_tokens": 12},
                "model_context_window": 128000,
            },
            "rate_limits": {"primary": {"used_percent": 12}, "secondary": {"used_percent": 33}, "plan_type": "pro"},
        },
    }),
    json.dumps({
        "timestamp": "2026-05-11T00:02:30.000Z",
        "type": "response_item",
        "payload": {
            "type": "function_call",
            "name": "exec_command",
            "call_id": "call_c",
        },
    }),
]) + "\n")
(old / "no-token.jsonl").write_text('{"type":"event_msg","payload":{"type":"other"}}\n')

mod.CODEX_SESSIONS_DIR = sessions
mod.TOKEN_SCAN_MAX_FILES = 10
mod.TOKEN_SCAN_MTIME_DAYS = 30
usage = mod.collect_token_usage(now=time.time())
assert usage["sessions_with_usage"] == 2, usage
assert usage["session_files_scanned"] == 3, usage
assert usage["total_token_usage"] == {
    "input_tokens": 105,
    "cached_input_tokens": 27,
    "output_tokens": 17,
    "reasoning_output_tokens": 4,
    "total_tokens": 122,
}, usage
assert usage["latest_event_at"] == "2026-05-11T00:02:00.000Z", usage
assert usage["latest_plan_type"] == "pro", usage
assert usage["latest_primary_used_percent"] == 12, usage
assert usage["latest_secondary_used_percent"] == 33, usage
assert [e["total_tokens"] for e in usage["recent_token_events"]] == [2, 11, 12], usage["recent_token_events"]
assert usage["recent_token_events"][-1]["timestamp"] == "2026-05-11T00:02:00.000Z", usage["recent_token_events"]

assert hasattr(mod, "collect_tool_call_usage"), "dashboard should collect tool-call usage"
tool_usage = mod.collect_tool_call_usage(now=time.time(), force=True)
assert tool_usage["sessions_with_tool_calls"] == 2, tool_usage
assert tool_usage["total_tool_calls"] == 3, tool_usage
assert tool_usage["tool_counts"]["exec_command"] == 2, tool_usage
assert tool_usage["tool_counts"]["browser_click"] == 1, tool_usage
assert tool_usage["streaming_arg_delta_events"] == 1, tool_usage
assert [e["tool"] for e in tool_usage["recent_tool_call_events"]] == ["exec_command", "browser_click", "exec_command"], tool_usage["recent_tool_call_events"]
assert tool_usage["latest_tool"] == "exec_command", tool_usage
assert tool_usage["latest_event_at"] == "2026-05-11T00:02:30.000Z", tool_usage

limited = tmp / "limited-sessions"
limited.mkdir()
for i in range(5):
    (limited / f"rollout-{i}.jsonl").write_text(json.dumps({
        "timestamp": f"2026-05-11T00:0{i}:00.000Z",
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {"total_token_usage": {"total_tokens": i + 1}},
        },
    }) + "\n")
mod.CODEX_SESSIONS_DIR = limited
mod.TOKEN_SCAN_MAX_WALK_ENTRIES = 2
mod.TOKEN_SCAN_MAX_FILES = 10
limited_files = mod.recent_codex_session_files(time.time())
assert len(limited_files) == 2, limited_files
walker_source = inspect.getsource(mod.iter_jsonl_files_bounded)
assert "os.scandir" in walker_source, "token scans should stream directory entries"
assert "os.walk" not in walker_source, "token scans must not materialize whole directory trees"
limited_usage = mod.collect_token_usage(now=time.time(), force=True)
assert limited_usage["session_files_scanned"] == 2, limited_usage

html = mod.INDEX_HTML
assert "renderOverviewDashboard" in html, "root page should render a dashboard overview"
assert "Total tokens" in html, "overview should include total token usage"
assert "Tool calls" in html, "overview should expose total tool calls"
assert "Refresh latency" in html, "overview should expose dashboard refresh timing"
assert "renderTokenGraphs" in html, "root page should render token usage graphs"
assert "renderToolCallGraphs" in html, "root page should render tool-call graphs"
assert "Tool calls over time" in html, "tool graph should show calls over time"
assert "Tool mix" in html, "tool graph should show which tools are used most"
assert "renderSystemDiagnostics" in html, "root page should render system diagnostics plots"
assert "CPU load history" in html, "diagnostics should graph CPU load over time"
assert "RAM usage history" in html, "diagnostics should graph RAM use over time"
assert "Top CPU processes" in html, "diagnostics should identify CPU-heavy processes"
assert "Top RAM processes" in html, "diagnostics should identify memory-heavy processes"
assert "Recent token usage" in html, "token graph should show recent usage over time"
assert "Input / output mix" in html, "token graph should show token composition"
assert "renderChartGrid" in html, "plots should render grid lines"
assert "chart-axis-label" in html, "plots should render axis readings"
assert "chart-reading-row" in html, "plots should show numeric readings below charts"
assert "Avg / peak" in html, "token graph should summarize average and peak readings"
assert "Token readings" in html, "dashboard should include detailed token readings"
assert "Cache efficiency" in html, "dashboard should expose cache efficiency"
assert "Cumulative token usage" in html, "dashboard should show cumulative token usage"
assert "renderCumulativeBars" in html, "dashboard should render cumulative token plot"
assert "cumulative-bar" in html, "cumulative chart should have cumulative bars"
assert "Window total" in html, "cumulative chart should show window total reading"
assert "Share of scanned" in html, "cumulative chart should compare cumulative window to scanned total"
assert "meminfo.read_text()" not in dashboard_path.read_text(), "Linux meminfo should use bounded reads"
assert hasattr(mod, "collect_system_health"), "dashboard should collect local computer health"
health = mod.collect_system_health()
for key in ["cpu", "memory", "disk", "storage"]:
    assert key in health, health
assert health["storage"]["devices"], health
assert "top_cpu_processes" in health, health
assert "top_memory_processes" in health, health

def fake_remote_disk(host, hosts, me, connection=None):
    return {
        "host": host,
        "aliases": [host],
        "role": "slurm" if hosts.get(host, {}).get("scheduler") == "slurm" else "ssh",
        "path": "/remote/free",
        "total_bytes": 1000,
        "used_bytes": 300,
        "free_bytes": 700,
        "used_percent": 30,
        "reachable": True,
        "error": "",
        "node": (connection or {}).get("node", ""),
        "job_id": (connection or {}).get("job_id", ""),
    }

orig_collect_remote_disk_health = mod.collect_remote_disk_health
mod.collect_remote_disk_health = fake_remote_disk
storage = mod.collect_storage_health(
    {"laptop": {"ssh": "laptop"}, "lunarc": {"ssh": "lunarc", "scheduler": "slurm"}},
    "mac-mini",
    {
        "laptop": {"reachable": True, "latency_ms": 3},
        "lunarc": {"reachable": False, "error": "no allocation"},
    },
)
assert any(d.get("host") == "laptop" and d.get("free_bytes") == 700 for d in storage["devices"]), storage
assert not any(d.get("host") == "lunarc" for d in storage["devices"]), storage
grouped = mod.collect_system_health(
    {"laptop": {"ssh": "laptop"}, "lunarc": {"ssh": "lunarc", "scheduler": "slurm"}},
    "mac-mini",
    {"laptop": {"reachable": True, "latency_ms": 3}},
)
assert grouped["storage"]["remote_count"] >= 1, grouped

mod.collect_remote_disk_health = orig_collect_remote_disk_health
orig_host_runner = mod.host_runner
orig_max_remote_json = mod.MAX_REMOTE_JSON_CHARS
mod.MAX_REMOTE_JSON_CHARS = 16
def huge_disk_runner(cmd):
    return subprocess.CompletedProcess(cmd, 0, "{" + "x" * 32, "")
mod.host_runner = lambda *args, **kwargs: huge_disk_runner
oversized_disk = mod.collect_remote_disk_health("laptop", {"laptop": {"ssh": "laptop"}}, "mac-mini")
assert oversized_disk["reachable"] is False, oversized_disk
assert oversized_disk["error"] == "disk probe returned oversized JSON", oversized_disk
mod.host_runner = orig_host_runner
mod.MAX_REMOTE_JSON_CHARS = orig_max_remote_json

assert "Computer health" in html, "dashboard should show computer health"
assert "systemHealthCard" in html, "dashboard should group CPU/RAM/disk into one card"
assert "CPU load" in html, "dashboard should show CPU usage/load"
assert "RAM used" in html, "dashboard should show RAM usage"
assert "Disk free" in html, "dashboard should show disk headroom"
assert "Storage headroom" in html, "dashboard should show local plus connected-device storage"
assert "storageHeadroomCard" in html, "dashboard should render grouped storage headroom"
assert "storage-device-row" in html, "storage card should list each connected device in one grouped panel"
assert "Recent activities" in html, "home page should show recent pane/project activities"
assert "renderRecentActivities" in html, "dashboard should render activity feed"
assert "activity-row" in html, "activity feed should have rows"
assert "activity-project" in html, "activity feed should label source project"
assert "last meaningful pane output" in html, "activity feed should explain its source"
print("ok: dashboard exposes first-page metrics, tool-call graphs, token usage, CPU/RAM diagnostics, activities, gridded plots, and readings")
PY
