#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_cache_numeric", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_cache_numeric", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

# Corrupt in-memory cache timestamps should degrade to stale/refreshing paths,
# not crash state/health payload generation with ValueError/TypeError.
assert mod.cache_timestamp("bad") == 0.0
assert mod.cache_age(10.0, "bad") == 10.0

mod.start_async_metric_refresh = lambda *args, **kwargs: None

with mod.PROMPT_LANE_CACHE_LOCK:
    mod.PROMPT_LANE_CACHE[("h", "/tmp/prompts", "")] = {
        "updated_at": "bad",
        "value": {0: "CEO"},
    }
mod.start_remote_lanes_refresh = lambda *args, **kwargs: None
assert mod.parse_remote_lanes_cached("h", {}, "local", "/tmp/prompts", async_ok=True) == {0: "CEO"}

with mod.SYSTEM_HEALTH_CACHE_LOCK:
    mod.SYSTEM_HEALTH_CACHE.clear()
    mod.SYSTEM_HEALTH_CACHE.update({
        "key": mod.system_health_cache_key({}, "local", {}),
        "updated_at": "bad",
        "value": {"status": "ok", "updated_at": "bad"},
    })
snapshot = mod.collect_system_health_snapshot({}, "local", {})
assert snapshot["status"] == "ok", snapshot

mod.token_usage_cache_key = lambda: ("tokens",)
with mod.TOKEN_USAGE_CACHE_LOCK:
    mod.TOKEN_USAGE_CACHE.clear()
    mod.TOKEN_USAGE_CACHE.update({"key": ("tokens",), "updated_at": "bad", "value": {"cached": True}})
assert mod.collect_token_usage_snapshot()["cached"] is True

mod.tool_call_usage_cache_key = lambda: ("tools",)
with mod.TOOL_CALL_USAGE_CACHE_LOCK:
    mod.TOOL_CALL_USAGE_CACHE.clear()
    mod.TOOL_CALL_USAGE_CACHE.update({"key": ("tools",), "updated_at": "bad", "value": {"cached": True}})
assert mod.collect_tool_call_usage_snapshot()["cached"] is True

with mod.CACHE_LOCK:
    mod.CACHE["updated_at"] = "bad"
    mod.CACHE["refresh_interval_secs"] = "bad"
health = mod.health_payload()
assert health["status"] in {"ok", "degraded"}, health
assert health["age_secs"] >= 0, health

storage = mod.collect_storage_health(hosts={}, me="local", host_probe_cache={})
storage["devices"].append({"reachable": True, "total_bytes": "bad", "free_bytes": "bad", "used_bytes": "bad"})
# Re-run aggregate logic indirectly by monkey-patching collectors to include malformed remote data.
mod.collect_disk_health = lambda: {"reachable": True, "filesystem": "local", "path": "/", "total_bytes": "bad", "free_bytes": "bad", "used_bytes": "bad"}
assert mod.collect_storage_health(hosts={}, me="local", host_probe_cache={})["total_bytes"] >= 0

print("ok: dashboard cache numeric inputs fail closed instead of crashing")
PY
