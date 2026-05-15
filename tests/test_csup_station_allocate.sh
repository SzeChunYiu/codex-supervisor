#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."lunarc"]
ssh = "lunarc"
scheduler = "slurm"
slurm_job_name = "csup-station"
slurm_slots = "2"
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
  *"squeue"*"csup-station-2"*) exit 0 ;;
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 8; exit 0 ;;
  *"sbatch"*"csup-station-2"*) echo 222; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

set +e
out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SLURM_WAIT_SECS=0 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" station proj --host=lunarc --sessions=1 --workers=4 --apply 2>&1
)"
status=$?
set -e

if (( status != 0 )); then
  printf 'station should return success for a queued hold, got %s:\n%s\n' "$status" "$out" >&2
  exit 1
fi

[[ "$out" == *"FULL proj/lunarc slot=1 job=111 used=8 capacity=8 load_room="*" requested_panes=5"* ]] || {
  printf 'expected full existing slot, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" == *"SUBMIT proj/lunarc slot=2 job_name=csup-station-2 requested_panes=5"* ]] || {
  printf 'expected second slot submission, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" == *"HOLD proj/lunarc slot=2 job_name=csup-station-2 sessions_waiting=1 reason=slurm_queue"* ]] || {
  printf 'expected hold while second slot queues, got:\n%s\n' "$out" >&2
  exit 1
}

if grep -q "/shared/codex-supervisor.sh start" "$TMPDIR/ssh.log"; then
  printf 'station must not start panes while allocation is still queued\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

grep -q -- "--chdir='/remote/alloc'" "$TMPDIR/ssh.log" || {
  printf 'holder sbatch must run from slurm_workdir so stdout/state stay off home\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
}

echo "ok: station allocates existing slots, books new SLURM slots, and reports queue holds"
