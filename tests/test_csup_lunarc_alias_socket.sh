#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."sim-lunarc"]
ssh = "lunarc-cn018"
reachable = "ssh -o ConnectTimeout=3 -o BatchMode=yes lunarc true"
scheduler = "slurm"
slurm_job_name = "nnbar-csup"
slurm_max_panes = "8"
remote_env = "source /shared/env.sh"
supervisor = "/shared/codex-supervisor.sh"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts."sim-lunarc"]
project_dir = "/remote/proj"
prompts = "prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-sim"
TOML

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *" true"*) exit 0 ;;
  *"squeue"*"nnbar-csup"*) echo "333|cn018"; exit 0 ;;
  *"tmux list-panes"*) echo 1; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" station proj --host=sim-lunarc --sessions=1 --workers=2 --dry-run >/tmp/csup-alias.out

grep -q "START proj/sim-lunarc slot=1 job=333 node=cn018" /tmp/csup-alias.out
if grep -q "lunarc-cn018" "$TMPDIR/ssh.log"; then
  printf 'csup should execute LUNARC aliases through canonical lunarc control socket, log:\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi
grep -q "ControlPath=.*sockets" "$TMPDIR/ssh.log"
grep -q " lunarc " "$TMPDIR/ssh.log"

echo "ok: csup LUNARC aliases use the canonical authenticated control socket"
