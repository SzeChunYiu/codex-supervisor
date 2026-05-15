#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap '[[ -f "$TMPDIR/pid" ]] && kill "$(cat "$TMPDIR/pid")" 2>/dev/null || true; rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/bin" "$TMPDIR/root"

cat > "$TMPDIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
echo "tmux should not be used for dashboard launch when CODEX_SUPERVISOR_DASHBOARD_TMUX=0" >> "$FAKE_TMUX_LOG"
exit 99
TMUX
chmod +x "$TMPDIR/bin/tmux"
export FAKE_TMUX_LOG="$TMPDIR/tmux.log"

cat > "$TMPDIR/fake-dashboard" <<'DASH'
#!/usr/bin/env python3
import argparse, json, socketserver, time
from http.server import BaseHTTPRequestHandler
p = argparse.ArgumentParser()
p.add_argument('--port', type=int, required=True)
p.add_argument('--lines')
p.add_argument('--refresh')
args = p.parse_args()
class H(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        if self.path.startswith('/api/health.json'):
            body = json.dumps({'status':'ok','panes':1,'projects':1,'refresh_interval_secs':0.2,'source':{'path':__file__}}).encode()
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
        elif self.path.startswith('/api/refresh.json'):
            self.send_response(200); self.end_headers(); self.wfile.write(b'{}')
        else:
            self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
socketserver.TCPServer.allow_reuse_address=True
with socketserver.TCPServer(('127.0.0.1', args.port), H) as srv:
    srv.serve_forever()
DASH
chmod +x "$TMPDIR/fake-dashboard"

port="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PY
)"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
CODEX_SUPERVISOR_DASHBOARD_TMUX=0 \
CODEX_SUPERVISOR_DASHBOARD_PORT="$port" \
CODEX_SUPERVISOR_DASHBOARD_CMD="$TMPDIR/fake-dashboard" \
CODEX_SUPERVISOR_DASHBOARD_PID_FILE="$TMPDIR/pid" \
PATH="$TMPDIR/bin:$PATH" \
  bash -c 'source "$1"; ensure_dashboard; dashboard_http_ok' _ "$SCRIPT"

[[ -f "$TMPDIR/pid" ]] || { echo "expected nohup dashboard pid file" >&2; exit 1; }
if [[ -s "$TMPDIR/tmux.log" ]]; then
  cat "$TMPDIR/tmux.log" >&2
  exit 1
fi

echo "ok: dashboard launch can bypass tmux to preserve macOS project access"
