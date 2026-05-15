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

cat > "$TMPDIR/home/Desktop/projects/proj/codex-tasks/open.txt" <<'TASKS'
/goal Fix blocker A.
/goal Fix blocker B.
/goal Fix blocker C.
/goal Fix blocker D.
TASKS

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
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
  "$CSUP" factory-run proj --host=lunarc --scenario=resume --apply 2>&1
)"

[[ "$out" == *"FACTORY-RUN proj/lunarc scenario=resume work=4 blockers=0 sessions=1 workers=4 panes=5 mode=apply"* ]] || {
  printf 'expected factory-run sizing line, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" == *"START proj/lunarc slot=1 job=111 node=cx01 session=proj-lunarc-station-1 workers=4 panes=5"* ]] || {
  printf 'expected factory-run to delegate to station on existing allocation, got:\n%s\n' "$out" >&2
  exit 1
}

if grep -q "sbatch" "$TMPDIR/ssh.log"; then
  printf 'factory-run should pack into existing allocation before submitting a new job\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: factory-run resume sizes queued work and uses station without over-submitting"
