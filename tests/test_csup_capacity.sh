#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    exit 0
    ;;
esac
exit 0
TMUX
chmod +x "$TMPDIR/bin/tmux"

ram_limited="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=4096 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  CSUP_GOVERNOR_RUNNING_PANES=0 \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" capacity
)"

[[ "$ram_limited" == *"available=2"* ]] || {
  printf 'capacity should report two safe panes from RAM budget, got:\n%s\n' "$ram_limited" >&2
  exit 1
}
[[ "$ram_limited" == *"bottleneck=ram"* ]] || {
  printf 'capacity should explain RAM as the bottleneck, got:\n%s\n' "$ram_limited" >&2
  exit 1
}
[[ "$ram_limited" == *"ram_room=2"* && "$ram_limited" == *"disk_room=90"* && "$ram_limited" == *"load_room=12"* ]] || {
  printf 'capacity should expose each resource room, got:\n%s\n' "$ram_limited" >&2
  exit 1
}

cap_limited="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  CSUP_GOVERNOR_RUNNING_PANES=3 \
  CSUP_GOVERNOR_MAX_TOTAL_PANES=5 \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" capacity
)"

[[ "$cap_limited" == *"available=2"* && "$cap_limited" == *"bottleneck=session_cap"* ]] || {
  printf 'capacity should account for already running panes against the cap, got:\n%s\n' "$cap_limited" >&2
  exit 1
}

malformed_inputs="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=bad \
  CSUP_GOVERNOR_FREE_DISK_GB=bad \
  CSUP_GOVERNOR_LOAD1=bad \
  CSUP_GOVERNOR_CPU_COUNT=bad \
  CSUP_GOVERNOR_RUNNING_PANES=bad \
  CSUP_GOVERNOR_MAX_LOAD_PER_CPU=bad \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" capacity
)"

[[ "$malformed_inputs" == *"available=0"* && "$malformed_inputs" == *"bottleneck=ram"* ]] || {
  printf 'capacity should sanitize malformed measured resource values, got:\n%s\n' "$malformed_inputs" >&2
  exit 1
}
[[ "$malformed_inputs" == *"max_load_per_cpu=1.25"* && "$malformed_inputs" == *"running=0"* ]] || {
  printf 'capacity should sanitize malformed load/running values, got:\n%s\n' "$malformed_inputs" >&2
  exit 1
}

huge_env_inputs="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=999999 \
  CSUP_GOVERNOR_FREE_DISK_GB=999999 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=999999 \
  CSUP_GOVERNOR_RUNNING_PANES=0 \
  CSUP_GOVERNOR_MAX_TOTAL_PANES=999999 \
  CSUP_GOVERNOR_RAM_MB_PER_PANE=1 \
  CSUP_GOVERNOR_DISK_MB_PER_PANE=1 \
  CSUP_GOVERNOR_MIN_FREE_RAM_MB=0 \
  CSUP_GOVERNOR_MIN_FREE_DISK_GB=0 \
  CSUP_GOVERNOR_MAX_LOAD_PER_CPU=999999 \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" capacity
)"

[[ "$huge_env_inputs" == *"available=1"* && "$huge_env_inputs" == *"bottleneck=load"* ]] || {
  printf 'capacity should clamp oversized governor env caps to safe defaults, got:\n%s\n' "$huge_env_inputs" >&2
  exit 1
}
[[ "$huge_env_inputs" == *"max_total=8"* && "$huge_env_inputs" == *"max_load_per_cpu=1.25"* ]] || {
  printf 'capacity should report sanitized governor caps, got:\n%s\n' "$huge_env_inputs" >&2
  exit 1
}

overflow_sized_inputs="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=999999999999999999999999 \
  CSUP_GOVERNOR_FREE_DISK_GB=999999999999999999999999 \
  CSUP_GOVERNOR_LOAD1=999999999999999999999999 \
  CSUP_GOVERNOR_CPU_COUNT=999999999999999999999999 \
  CSUP_GOVERNOR_RUNNING_PANES=999999999999999999999999 \
  CSUP_GOVERNOR_MAX_TOTAL_PANES=999999999999999999999999 \
  CSUP_GOVERNOR_RAM_MB_PER_PANE=999999999999999999999999 \
  CSUP_GOVERNOR_DISK_MB_PER_PANE=999999999999999999999999 \
  CSUP_GOVERNOR_MIN_FREE_RAM_MB=999999999999999999999999 \
  CSUP_GOVERNOR_MIN_FREE_DISK_GB=999999999999999999999999 \
  CSUP_GOVERNOR_MAX_LOAD_PER_CPU=999999999999999999999999 \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" capacity
)"

[[ "$overflow_sized_inputs" == *"max_total=8"* && "$overflow_sized_inputs" == *"running=0"* ]] || {
  printf 'capacity should avoid arithmetic overflow from huge numeric env values, got:\n%s\n' "$overflow_sized_inputs" >&2
  exit 1
}

json_out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=4096 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  CSUP_GOVERNOR_RUNNING_PANES=0 \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" capacity --json
)"

python3 - "$json_out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["available"] == 2, payload
assert payload["bottleneck"] == "ram", payload
assert payload["ram_room"] == 2, payload
assert payload["disk_room"] == 90, payload
assert payload["load_room"] == 12, payload
assert payload["max_load_per_cpu"] == 1.25, payload
assert "host" in payload and payload["host"], payload
assert "runtime" in payload and payload["runtime"], payload
PY

help_out="$("$CSUP" help)"
[[ "$help_out" == *"csup capacity"* ]] || {
  printf 'help should advertise the capacity command, got:\n%s\n' "$help_out" >&2
  exit 1
}
