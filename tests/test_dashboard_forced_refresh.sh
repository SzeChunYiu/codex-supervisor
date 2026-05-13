#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import socket
import socketserver
import sys
import threading
import urllib.request

dashboard_path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

calls = {"n": 0}

def fake_refresh(lines):
    calls["n"] += 1
    with mod.CACHE_LOCK:
        mod.CACHE["refresh_count"] = calls["n"]
        mod.CACHE["updated_at"] = 123 + calls["n"]
        mod.CACHE["projects"] = [{"name": "p", "path": "/tmp/p", "instances": []}]

mod.refresh = fake_refresh
mod.REFRESH_LINES = 28

socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("127.0.0.1", 0), mod.Handler) as srv:
    port = srv.server_address[1]
    thread = threading.Thread(target=srv.serve_forever, daemon=True)
    thread.start()

    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/state.json", timeout=2) as r:
        first = json.loads(r.read().decode())
    assert calls["n"] == 0, first

    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/state.json?refresh=1", timeout=2) as r:
        forced = json.loads(r.read().decode())
    assert calls["n"] == 1, forced
    assert forced["refresh_count"] == 1, forced

    with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/refresh.json", timeout=2) as r:
        endpoint = json.loads(r.read().decode())
    assert calls["n"] == 2, endpoint
    assert endpoint["refresh_count"] == 2, endpoint

    srv.shutdown()

html = mod.INDEX_HTML
assert "refreshNow.addEventListener('click', () => tick(true))" in html
assert "if (force) params.set('refresh', '1')" in html
assert "const url = '/api/state.json' + (query ? '?' + query : '')" in html
print("ok: dashboard manual refresh forces server-side capture")
PY
