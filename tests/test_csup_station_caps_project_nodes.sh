#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."lunarc"]
ssh = "lunarc"
scheduler = "slurm"
slurm_job_name = "csup-station"
slurm_slots = "4"
slurm_cpus = "8"
slurm_mem = "16G"
slurm_max_panes = "8"
slurm_workdir = "/remote/alloc"
remote_env = "source /shared/env.sh"
supervisor = "/shared/codex-supervisor.sh"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts."lunarc"]
project_dir = "/remote/proj"
prompts = "prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-lunarc"
TOML

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*"csup-station-3"*) echo "333|cx03"; exit 0 ;;
  *"squeue"*"csup-station-2"*) echo "222|cx02"; exit 0 ;;
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 8; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

set +e
out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" station proj --host=lunarc --sessions=1 --workers=4 --dry-run 2>&1
)"
status=$?
set -e

if (( status != 0 )); then
  printf 'station should return success for capped no-capacity hold, got %s:\n%s\n' "$status" "$out" >&2
  exit 1
fi
[[ "$out" == *"FULL proj/lunarc slot=1"* ]] || { printf 'expected slot 1 check, got:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"FULL proj/lunarc slot=2"* ]] || { printf 'expected slot 2 check, got:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"HOLD proj/lunarc sessions_waiting=1 reason=no_station_capacity"* ]] || { printf 'expected no capacity after two-node cap, got:\n%s\n' "$out" >&2; exit 1; }
if grep -q 'csup-station-3' "$TMPDIR/ssh.log"; then
  printf 'station must not inspect or allocate a third project node by default\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: station caps each project at two SLURM computer nodes by default"
