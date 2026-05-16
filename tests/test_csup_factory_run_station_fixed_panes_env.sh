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
slurm_max_panes = "5"
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
/goal Fix A.
/goal Fix B.
/goal Fix C.
/goal Fix D.
TASKS

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
case "$*" in
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 0; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_STATION_FIXED_PANES=bad \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" factory-run proj --host=lunarc --scenario=resume --apply 2>&1
)"

[[ "$out" == *"FACTORY-RUN proj/lunarc scenario=resume work=4 blockers=0 sessions=1 workers=4 panes=5 mode=apply"* ]] || {
  printf 'factory-run should default invalid CSUP_STATION_FIXED_PANES to one fixed pane, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" == *"csup: station mode=apply project=proj host=lunarc sessions=1 workers=4 panes_per_session=5"* ]] || {
  printf 'factory-run sizing must match station sizing under invalid CSUP_STATION_FIXED_PANES, got:\n%s\n' "$out" >&2
  exit 1
}

echo "ok: factory-run and station agree on invalid fixed pane env fallback"
