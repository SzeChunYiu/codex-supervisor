#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/ps" <<PS
#!/usr/bin/env bash
cat <<'OUT'
101 /bin/zsh -lc echo $ROOT/csup-dashboard --port 7777
202 /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python $ROOT/csup-dashboard --port 7777 --lines 14 --refresh 5
303 python3 $ROOT/csup-dashboard --port 8888
404 $ROOT/csup-dashboard --port 7777
OUT
PS
chmod +x "$TMPDIR/bin/ps"

python3 - "$ROOT/codex-supervisor.sh" <<'PY'
import pathlib
import re
import sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'dashboard_matching_pids_for_cmd\(\) \{.*?python3 - "\$match_cmd" "\$DASHBOARD_PORT" <<\'PY\'\n(.*?)\nPY', text, re.S)
assert match, "dashboard_matching_pids_for_cmd Python snippet missing"
snippet = match.group(1)
assert "subprocess.check_output" not in snippet
assert "timeout=2.0" in snippet
assert "MAX_PS_OUTPUT_BYTES = 1_000_000" in snippet
PY

PATH="$TMPDIR/bin:$PATH" \
CODEX_SUPERVISOR_DASHBOARD_CMD="$ROOT/csup-dashboard" \
DASHBOARD_PORT="7777" \
bash -c 'source ./codex-supervisor.sh; dashboard_matching_pids' > "$TMPDIR/pids"

expected=$'202\n404'
actual="$(cat "$TMPDIR/pids")"
if [[ "$actual" != "$expected" ]]; then
  echo "expected dashboard pids:" >&2
  printf '%s\n' "$expected" >&2
  echo "actual dashboard pids:" >&2
  printf '%s\n' "$actual" >&2
  exit 1
fi

echo "ok: dashboard pid matching finds direct and macOS Python.app launchers only"
