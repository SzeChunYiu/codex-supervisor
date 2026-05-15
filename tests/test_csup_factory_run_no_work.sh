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
echo remote-ok
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"
: > "$FAKE_SSH_LOG"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" factory-run proj --host=lunarc --apply 2>&1
)"

[[ "$out" == *"HOLD proj/lunarc reason=no_queued_work"* ]] || {
  printf 'expected no-work hold, got:\n%s\n' "$out" >&2
  exit 1
}

if grep -q "squeue\\|sbatch\\|srun" "$TMPDIR/ssh.log"; then
  printf 'factory-run must not touch SLURM when no work is queued\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: factory-run refuses to allocate nodes when there is no queued work"
