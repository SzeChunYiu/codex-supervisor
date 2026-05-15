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
slurm_slots = "1"
slurm_max_panes = "20"
slurm_workdir = "/remote/alloc"
remote_env = "export CODEX_SUPERVISOR_MAX_LOAD_PER_CPU=0.8"
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

cat > "$TMPDIR/home/Desktop/projects/proj/codex-tasks/open.txt" <<'TASKS'
/goal One
/goal Two
/goal Three
TASKS

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 5; exit 0 ;;
  *"os.getloadavg"*) echo 0; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" factory-run proj --host=lunarc --scenario=resume --apply 2>&1
)"

[[ "$out" == *"FULL proj/lunarc slot=1 job=111 used=5 capacity=20 load_room=0 requested_panes=4"* ]] || {
  printf 'expected station to refuse starts when remote load has no headroom, got:\n%s\n' "$out" >&2
  exit 1
}
if grep -q "/shared/codex-supervisor.sh.* start --no-attach" "$TMPDIR/ssh.log"; then
  printf 'station must not start workers when load_room=0\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: station treats remote load headroom as a hard capacity limit"
