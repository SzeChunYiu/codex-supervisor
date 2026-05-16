#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

grep -q 'MAX_DASHBOARD_STATE_BYTES + 1' "$CSUP" || { echo "csup steward dashboard reads must detect oversized payloads" >&2; exit 1; }
grep -q 'CSUP_STEWARD_MAX_SAMPLE_SECS' "$CSUP" || { echo "csup steward sample window must be capped" >&2; exit 1; }
grep -q 'CSUP_STEWARD_MAX_ROWS' "$CSUP" || { echo "csup steward row count must be capped" >&2; exit 1; }
grep -q 'MAX_DASHBOARD_URL_CHARS' "$CSUP" || { echo "csup steward dashboard URL length must be capped" >&2; exit 1; }
grep -q 'MAX_STEWARD_PROJECT_FILTER_CHARS' "$CSUP" || { echo "csup steward project filter length must be capped" >&2; exit 1; }

set +e
unsafe_url_out="$($CSUP steward demo --sample-secs=0 --dashboard-url="file:///tmp/csup-dashboard-state" 2>&1)"
unsafe_url_status=$?
remote_url_out="$($CSUP steward demo --sample-secs=0 --dashboard-url="http://192.0.2.1:7777" 2>&1)"
remote_url_status=$?
long_project_out="$($CSUP steward "$(python3 - <<'PY'
print('p' * 129)
PY
)" --sample-secs=0 --dashboard-url="http://127.0.0.1:7777" 2>&1)"
long_project_status=$?
long_url_out="$($CSUP steward demo --sample-secs=0 --dashboard-url="http://127.0.0.1:7777/$(python3 - <<'PY'
print('u' * 2050)
PY
)" 2>&1)"
long_url_status=$?
set -e
(( unsafe_url_status != 0 )) || { printf 'file dashboard URL should fail closed:
%s
' "$unsafe_url_out" >&2; exit 1; }
(( remote_url_status != 0 )) || { printf 'non-local dashboard URL should fail closed:
%s
' "$remote_url_out" >&2; exit 1; }
(( long_project_status != 0 )) || { printf 'overlong project filter should fail closed:
%s
' "$long_project_out" >&2; exit 1; }
(( long_url_status != 0 )) || { printf 'overlong dashboard URL should fail closed:
%s
' "$long_url_out" >&2; exit 1; }
[[ "$unsafe_url_out" == *"localhost http(s)"* ]] || { printf 'missing file URL rejection detail:
%s
' "$unsafe_url_out" >&2; exit 1; }
[[ "$remote_url_out" == *"localhost http(s)"* ]] || { printf 'missing remote URL rejection detail:
%s
' "$remote_url_out" >&2; exit 1; }
[[ "$long_project_out" == *"project filter too long"* ]] || { printf 'missing project length rejection detail:
%s
' "$long_project_out" >&2; exit 1; }
[[ "$long_url_out" == *"dashboard URL too long"* ]] || { printf 'missing URL length rejection detail:
%s
' "$long_url_out" >&2; exit 1; }

cat > "$TMPDIR/state.json" <<'JSON'
{
  "projects": [
    {
      "name": "demo",
      "slug": "demo",
      "path": "/tmp/demo",
      "instances": [
        {
          "host": "local",
          "session": "demo-main",
          "panes": [
            {"index": 0, "lane": "worker-0", "state": "goal-done", "tail": ["Goal achieved (1m)"]},
            {"index": 1, "lane": "worker-1", "state": "working", "tail": ["blocked: missing exact_path_read"]},
            {"index": 2, "lane": "worker-2", "state": "working", "tail": ["Pursuing goal (30m)"]},
            {"index": 3, "lane": "worker-3", "state": "dead", "tail": ["Pane is dead (status 0)"]},
            {"index": 4, "lane": "worker-4", "state": "working", "tail": ["Waiting for background terminal"]}
          ]
        }
      ]
    }
  ]
}
JSON

python3 - "$TMPDIR/state.json" "$TMPDIR/port" <<'PY' &
import functools
import http.server
import pathlib
import socketserver
import sys

state = pathlib.Path(sys.argv[1])
port_file = pathlib.Path(sys.argv[2])

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return
    def do_GET(self):
        if self.path.startswith("/api/state.json"):
            payload = state.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_error(404)

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as srv:
    port_file.write_text(str(srv.server_address[1]))
    srv.serve_forever()
PY
server_pid=$!
for _ in {1..50}; do
  [[ -s "$TMPDIR/port" ]] && break
  sleep 0.05
done
port="$(cat "$TMPDIR/port")"

out="$("$CSUP" steward demo --sample-secs=0 --dashboard-url="http://127.0.0.1:$port")"
clamped_out="$(CSUP_STEWARD_MAX_SAMPLE_SECS=0 "$CSUP" steward demo --sample-secs=999999 --dashboard-url="http://127.0.0.1:$port")"
row_capped_out="$(CSUP_STEWARD_MAX_ROWS=2 "$CSUP" steward demo --sample-secs=0 --dashboard-url="http://127.0.0.1:$port")"
python3 - "$TMPDIR/state.json" <<'PY'
import json
import pathlib
import sys

panes = [
    {"index": i, "lane": f"worker-{i}", "state": "working", "tail": ["Pursuing goal"]}
    for i in range(5001)
]
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "projects": [{
        "name": "demo",
        "slug": "demo",
        "instances": [{"host": "local", "session": "demo-main", "panes": panes}],
    }]
}))
PY
huge_cap_out="$(CSUP_STEWARD_MAX_SAMPLE_SECS=999999 CSUP_STEWARD_MAX_ROWS=999999 "$CSUP" steward demo --sample-secs=0 --dashboard-url="http://127.0.0.1:$port")"
python3 - "$TMPDIR/state.json" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[1]).write_text('{"projects":[]}' + (' ' * 2_000_001))
PY
set +e
oversized_out="$("$CSUP" steward demo --sample-secs=0 --dashboard-url="http://127.0.0.1:$port" 2>&1)"
oversized_status=$?
set -e
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true

(( oversized_status != 0 )) || { printf 'oversized dashboard state should fail closed:\n%s\n' "$oversized_out" >&2; exit 1; }
[[ "$oversized_out" == *"dashboard state payload too large"* ]] || { printf 'missing oversized payload detail:\n%s\n' "$oversized_out" >&2; exit 1; }
[[ "$out" == *"STEWARD summary"* ]] || { printf 'missing summary:\n%s\n' "$out" >&2; exit 1; }
[[ "$clamped_out" == *"STEWARD summary"* ]] || { printf 'clamped sample run did not complete:\n%s\n' "$clamped_out" >&2; exit 1; }
[[ "$row_capped_out" == *"total=2"* ]] || { printf 'row-capped steward run should scan only 2 panes:\n%s\n' "$row_capped_out" >&2; exit 1; }
[[ "$huge_cap_out" == *"total=5000"* ]] || {
  printf 'oversized steward caps should fall back to safe defaults (first lines):\n%s\n' "$(printf '%s\n' "$huge_cap_out" | sed -n '1,3p')" >&2
  exit 1
}
[[ "$out" == *"done=1"* ]] || { printf 'missing done count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"blocked=1"* ]] || { printf 'missing blocked count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"dead=1"* ]] || { printf 'missing dead count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"stale_working=1"* ]] || { printf 'missing stale count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"waiting_stale=1"* ]] || { printf 'missing waiting count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"action=reassign-or-stop"* ]] || { printf 'missing reassign action:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"VALIDATOR should recycle"* ]] || { printf 'missing recommendation:\n%s\n' "$out" >&2; exit 1; }

echo "ok: csup steward classifies done/blocked/stale panes and recommends reassignment"
