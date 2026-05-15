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
slurm_max_panes = "8"
slurm_workdir = "/remote/alloc"
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
/goal Keep working.
TASKS

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 4; exit 0 ;;
  *"tmux -L"*"proj-lunarc-station-1"*"has-session"*"proj-lunarc-station-1"*) echo yes; exit 0 ;;
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

[[ "$out" == *"SKIP proj/lunarc slot=1 job=111 node=cx01 session=proj-lunarc-station-1 reason=session_running"* ]] || {
  printf 'expected existing station session to be skipped, got:\n%s\n' "$out" >&2
  exit 1
}
if grep -q "/shared/codex-supervisor.sh.* start --no-attach" "$TMPDIR/ssh.log"; then
  printf 'factory-run must not restart an already-running station session\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: factory-run/station skips already-running station sessions"
