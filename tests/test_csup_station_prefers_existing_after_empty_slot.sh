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
  *"squeue"*"csup-station-2"*) echo "222|cx02"; exit 0 ;;
  *"squeue"*"csup-station"*) exit 0 ;;
  *"tmux list-panes"*) echo 1; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" station proj --host=lunarc --sessions=1 --workers=4 --apply 2>&1
)"

[[ "$out" == *"START proj/lunarc slot=2 job=222 node=cx02 session=proj-lunarc-station-1 workers=4 panes=5"* ]] || {
  printf 'expected station to prefer existing slot 2 before submitting empty slot 1, got:\n%s\n' "$out" >&2
  exit 1
}
if grep -q "sbatch" "$TMPDIR/ssh.log"; then
  printf 'station should not submit while any existing slot has enough room\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: station prefers any existing allocation with room before booking empty slots"
