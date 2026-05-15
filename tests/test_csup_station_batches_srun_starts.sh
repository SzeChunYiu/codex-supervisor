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
slurm_max_panes = "128"
slurm_start_batch_size = "32"
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
  *" true"*) exit 0 ;;
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 0; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_STATION_START_STAGGER_SECS=0 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" station proj --host=lunarc --sessions=18 --workers=4 --apply 2>&1
)"

for n in $(seq 1 18); do
  [[ "$out" == *"session=proj-lunarc-station-$n workers=4 panes=5"* ]] || {
    printf 'expected START line for station-%s, got:\n%s\n' "$n" "$out" >&2
    exit 1
  }
  grep -q "CODEX_SUPERVISOR_SESSION=.*proj-lunarc-station-$n" "$TMPDIR/ssh.log" || {
    printf 'expected batched launch command to include station-%s, log:\n' "$n" >&2
    cat "$TMPDIR/ssh.log" >&2
    exit 1
  }
done

launch_count=$(grep -o "nohup setsid env -u LD_LIBRARY_PATH srun" "$TMPDIR/ssh.log" | wc -l | tr -d ' ')
if [[ "$launch_count" != "1" ]]; then
  printf 'expected one persistent srun launch for eighteen station sessions, got %s; log:\n' "$launch_count" >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

grep -q 'SLURM_JOB_ID' "$TMPDIR/ssh.log" || {
  printf 'expected compute-node guard in batched srun launch, log:\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
}

echo "ok: station batches >100 panes of supervisor starts into one persistent srun step"
