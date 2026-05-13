#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"
cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."lunarc"]
ssh = "lunarc"
scheduler = "slurm"
slurm_job_name = "mcaccel-sup"
slurm_workdir = "/remote/alloc"
remote_env = "source /shared/env.sh"
supervisor = "/shared/codex-supervisor.sh"
HOSTS
cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'CFG'
schema_version = 1
[project]
name = "proj"
[hosts."lunarc"]
project_dir = "/remote/proj"
prompts = "/shared/prompts/proj-prompts.txt"
tasks_dir = "/shared/tasks/proj"
session = "proj-lunarc"
CFG
cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *squeue*) echo 555 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
PATH="$TMPDIR/bin:$PATH" \
"$ROOT/bin/csup" start proj --host=lunarc > "$TMPDIR/out.txt"

cat "$TMPDIR/ssh.log" > "$TMPDIR/log.txt"
grep -q "CODEX_SUPERVISOR_PROMPTS=.*shared/prompts/proj-prompts.txt" "$TMPDIR/log.txt"
grep -q "CODEX_SUPERVISOR_TASKS_DIR=.*shared/tasks/proj" "$TMPDIR/log.txt"
if grep -q "/remote/proj//shared" "$TMPDIR/log.txt"; then
  echo "absolute remote paths were incorrectly prefixed with project_dir" >&2
  cat "$TMPDIR/log.txt" >&2
  exit 1
fi

echo "ok: csup preserves absolute remote prompt and task paths"
