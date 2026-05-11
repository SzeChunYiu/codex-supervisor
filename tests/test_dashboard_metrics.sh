#!/usr/bin/env bash
set -euo pipefail

DASHBOARD="${CSUP_DASHBOARD:-$HOME/bin/csup-dashboard}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

python3 - "$DASHBOARD" "$TMPDIR" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
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
]) + "\n")

(current / "rollout-b.jsonl").write_text(json.dumps({
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
}) + "\n")
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

html = mod.INDEX_HTML
assert "renderOverviewDashboard" in html, "root page should render a dashboard overview"
assert "Total tokens" in html, "overview should include total token usage"
assert "Refresh latency" in html, "overview should expose dashboard refresh timing"
assert "renderTokenGraphs" in html, "root page should render token usage graphs"
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
assert hasattr(mod, "collect_system_health"), "dashboard should collect local computer health"
health = mod.collect_system_health()
for key in ["cpu", "memory", "disk"]:
    assert key in health, health
assert "Computer health" in html, "dashboard should show computer health"
assert "CPU load" in html, "dashboard should show CPU usage/load"
assert "RAM used" in html, "dashboard should show RAM usage"
assert "Disk free" in html, "dashboard should show disk headroom"
assert "Recent activities" in html, "home page should show recent pane/project activities"
assert "renderRecentActivities" in html, "dashboard should render activity feed"
assert "activity-row" in html, "activity feed should have rows"
assert "activity-project" in html, "activity feed should label source project"
assert "last meaningful pane output" in html, "activity feed should explain its source"
print("ok: dashboard exposes first-page metrics, token usage, cumulative usage, computer health, activities, gridded plots, and readings")
PY
