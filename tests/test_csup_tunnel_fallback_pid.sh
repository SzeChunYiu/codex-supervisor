#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" PATH="$TMPDIR/bin:$PATH" "$CSUP" tunnel --kill >/dev/null 2>&1 || true; rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."lunarc"]
ssh = "lunarc"
scheduler = "slurm"
slurm_job_name = "csup-station"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts."lunarc"]
project_dir = "/remote/proj"
prompts = "prompts.txt"
session = "proj-lunarc"
TOML

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"-O check"*) exit 255 ;;
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *" -N "*|"-N "*) sleep 60 ;;
esac
exit 0
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" tunnel > "$TMPDIR/first.out"

grep -q 'tunnel opened: cx01' "$TMPDIR/first.out"
awk -F '\t' '$1 == "cx01" && $2 ~ /^[0-9]+$/ && $2 > 0 && $3 == "7778" && $4 == "lunarc" {found=1} END {exit found ? 0 : 1}' "$TMPDIR/home/.config/csup/tunnels.tsv" || {
  printf 'expected tunnel state to record node, live pid, port, and ssh target; state:\n' >&2
  cat "$TMPDIR/home/.config/csup/tunnels.tsv" >&2
  exit 1
}
first_launches=$(grep -c -- '-N' "$TMPDIR/ssh.log" || true)
[[ "$first_launches" == "1" ]] || { cat "$TMPDIR/ssh.log" >&2; exit 1; }

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" tunnel > "$TMPDIR/second.out"

grep -q 'tunnel already up: cx01' "$TMPDIR/second.out"
second_launches=$(grep -c -- '-N' "$TMPDIR/ssh.log" || true)
[[ "$second_launches" == "1" ]] || { cat "$TMPDIR/ssh.log" >&2; exit 1; }

bad_port_help="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" \
  CSUP_TUNNEL_BASE_PORT=bad \
  CSUP_TUNNEL_REMOTE_PORT=bad \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" tunnel --help 2>&1
)"
[[ "$bad_port_help" == *"starting at port 7778"* ]] || {
  printf 'expected invalid tunnel port env values to fall back to defaults, got:\n%s\n' "$bad_port_help" >&2
  exit 1
}
[[ "$bad_port_help" != *"invalid number"* ]] || {
  printf 'invalid tunnel port env should not leak printf/arithmetic errors, got:\n%s\n' "$bad_port_help" >&2
  exit 1
}

cat > "$TMPDIR/home/.config/csup/tunnels.tsv" <<'STATE'
old-node	123	not-a-port	lunarc
STATE
HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" tunnel > "$TMPDIR/bad-state.out"

awk -F '\t' '$1 == "cx01" && $3 == "7778" {found=1} END {exit found ? 0 : 1}' "$TMPDIR/home/.config/csup/tunnels.tsv" || {
  printf 'expected invalid persisted tunnel ports to be ignored; state:\n' >&2
  cat "$TMPDIR/home/.config/csup/tunnels.tsv" >&2
  exit 1
}

python3 - <<PY
from pathlib import Path
Path("$TMPDIR/home/.config/csup/tunnels.tsv").write_text("x" * 1000001)
PY
HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" tunnel > "$TMPDIR/oversized-state.out" 2>&1

grep -q 'tunnel state skipped' "$TMPDIR/oversized-state.out" || {
  printf 'expected oversized tunnel state warning, got:\n%s\n' "$(cat "$TMPDIR/oversized-state.out")" >&2
  exit 1
}

cat > "$TMPDIR/home/.config/csup/tunnels.tsv" <<'STATE'
cx01	123	not-a-port	lunarc
STATE
HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_TUNNEL_STATE="$TMPDIR/home/.config/csup/tunnels.tsv" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" tunnel > "$TMPDIR/bad-existing.out"

awk -F '\t' '$1 == "cx01" && $3 == "7778" {found=1} END {exit found ? 0 : 1}' "$TMPDIR/home/.config/csup/tunnels.tsv" || {
  printf 'expected invalid existing node port to be replaced with a default-based port; state:\n' >&2
  cat "$TMPDIR/home/.config/csup/tunnels.tsv" >&2
  exit 1
}

echo "ok: csup tunnel records fallback ssh pids and avoids duplicate forwards"
