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

help_out="$("$CSUP" help)"
[[ "$help_out" == *"csup capacity"* ]] || {
  printf 'help should advertise the capacity command, got:\n%s\n' "$help_out" >&2
  exit 1
}
