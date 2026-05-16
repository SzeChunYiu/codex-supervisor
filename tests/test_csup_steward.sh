#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

grep -q 'MAX_DASHBOARD_STATE_BYTES + 1' "$CSUP" || { echo "csup steward dashboard reads must detect oversized payloads" >&2; exit 1; }
grep -q 'CSUP_STEWARD_MAX_SAMPLE_SECS' "$CSUP" || { echo "csup steward sample window must be capped" >&2; exit 1; }

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
[[ "$out" == *"done=1"* ]] || { printf 'missing done count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"blocked=1"* ]] || { printf 'missing blocked count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"dead=1"* ]] || { printf 'missing dead count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"stale_working=1"* ]] || { printf 'missing stale count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"waiting_stale=1"* ]] || { printf 'missing waiting count:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"action=reassign-or-stop"* ]] || { printf 'missing reassign action:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"VALIDATOR should recycle"* ]] || { printf 'missing recommendation:\n%s\n' "$out" >&2; exit 1; }

echo "ok: csup steward classifies done/blocked/stale panes and recommends reassignment"
