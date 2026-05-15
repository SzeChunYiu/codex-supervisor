#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

default_lanes="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; printf "%s\n" "${LANE_LABELS[@]}"' _ "$SCRIPT"
)"

[[ "$default_lanes" == $'BUGS\nPERF\nCEO' ]] || {
  printf 'default fixed role should be one real CEO pane only, got:\n%s\n' "$default_lanes" >&2
  exit 1
}

team_lanes="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  CODEX_SUPERVISOR_GENERATED_ONLY=1 \
  CODEX_SUPERVISOR_CEO=0 \
  CODEX_SUPERVISOR_MANAGER=1 \
  CODEX_SUPERVISOR_DYNAMIC_WORKERS=2 \
  bash -c 'source "$1"; load_prompts; printf "%s\n" "${LANE_LABELS[@]}"' _ "$SCRIPT"
)"

[[ "$team_lanes" == $'MANAGER\nWORKER-1\nWORKER-2' ]] || {
  printf 'generated team sessions should have manager plus workers only, got:\n%s\n' "$team_lanes" >&2
  exit 1
}

mkdir -p "$TMPDIR/home/.config/csup" "$TMPDIR/home/Desktop/projects/proj/codex-tasks/open" "$TMPDIR/bin"
cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'TOML'
[hosts.lunarc]
ssh = "lunarc"
scheduler = "slurm"
slurm_slots = 1
slurm_max_panes = 8
slurm_job_name = "csup-station"
supervisor = "/shared/codex-supervisor.sh"
TOML
cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts.lunarc]
ssh = "lunarc"
project_dir = "/remote/proj"
prompts = "prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-lunarc"
TOML
cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*) echo "123|cn001"; exit 0 ;;
  *"tmux list-panes"*) echo 0; exit 0 ;;
  *"uptime"*) echo "load average: 0.00, 0.00, 0.00"; exit 0 ;;
  *) echo ok ;;
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

[[ "$out" == *"panes=5"* ]] || {
  printf 'station should reserve one manager pane plus workers, got:\n%s\n' "$out" >&2
  exit 1
}
grep -q "CODEX_SUPERVISOR_CEO=.*0" "$TMPDIR/ssh.log"
grep -q "CODEX_SUPERVISOR_MANAGER=.*1" "$TMPDIR/ssh.log"
grep -q "CODEX_SUPERVISOR_DEBUGGER=.*0" "$TMPDIR/ssh.log"
grep -q "CODEX_SUPERVISOR_VALIDATOR=.*0" "$TMPDIR/ssh.log"

echo "ok: CEO is the only default executive pane and station teams use manager+workers"
