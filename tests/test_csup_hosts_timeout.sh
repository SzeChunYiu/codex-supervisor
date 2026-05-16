#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."slow-lunarc"]
ssh = "lunarc"
description = "slow SSH probe"
HOSTS

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
sleep 5
echo should-not-print
SSH
chmod +x "$TMPDIR/bin/ssh"

set +e
out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SSH_TIMEOUT_SECS=1 \
  PATH="$TMPDIR/bin:$PATH" \
  python3 - "$CSUP" <<'PY'
import subprocess, sys, time
cmd = [sys.argv[1], "hosts"]
t0 = time.monotonic()
p = subprocess.run(cmd, text=True, capture_output=True, timeout=3)
elapsed = time.monotonic() - t0
print(p.stdout, end="")
print(p.stderr, end="", file=sys.stderr)
print(f"elapsed={elapsed:.2f}")
sys.exit(p.returncode)
PY
)"
status=$?
set -e

if (( status != 0 )); then
  printf 'csup hosts should return successfully even when a host probe times out, got %s:\n%s\n' "$status" "$out" >&2
  exit 1
fi
[[ "$out" == *"slow-lunarc"* && "$out" == *"down"* ]] || {
  printf 'expected slow host to be marked down, got:\n%s\n' "$out" >&2
  exit 1
}
elapsed="${out##*elapsed=}"
python3 - "$elapsed" <<'PY'
import sys
elapsed = float(sys.argv[1])
assert elapsed < 2.5, f"csup hosts probe timeout too slow: {elapsed}"
PY

bad_timeout_out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SSH_TIMEOUT_SECS=bad \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" hosts 2>&1
)"

[[ "$bad_timeout_out" == *"slow-lunarc"* ]] || {
  printf 'expected invalid SSH timeout to still report host status, got:\n%s\n' "$bad_timeout_out" >&2
  exit 1
}
[[ "$bad_timeout_out" != *"Traceback"* && "$bad_timeout_out" != *"ValueError"* ]] || {
  printf 'invalid SSH timeout should not leak Python tracebacks, got:\n%s\n' "$bad_timeout_out" >&2
  exit 1
}

echo "ok: csup hosts bounds slow SSH reachability probes"
