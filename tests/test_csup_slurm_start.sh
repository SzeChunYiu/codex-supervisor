#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj/docs" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"
cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."local-test"]
ssh = "local"
hostname_match = "not-this-host"

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
prompts = "prompts.txt"
tasks_dir = "codex-tasks"
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
grep -q "squeue .*mcaccel-sup" "$TMPDIR/log.txt"
grep -q "nohup setsid env -u LD_LIBRARY_PATH srun --jobid=.*555.*--overlap" "$TMPDIR/log.txt"
grep -q "disown; echo started slurm_job=555" "$TMPDIR/log.txt"
grep -q "source /shared/env.sh" "$TMPDIR/log.txt"
grep -q "CODEX_SUPERVISOR_MAX_LOAD_PER_CPU=.*:-0" "$TMPDIR/log.txt"
grep -q "CODEX_SUPERVISOR_PROMPTS=.*remote/proj/prompts.txt" "$TMPDIR/log.txt"
grep -q "while tmux -L .*proj-lunarc.* has-session -t.*proj-lunarc" "$TMPDIR/log.txt"
echo "ok: csup starts LUNARC hosts through a persistent SLURM srun step"
