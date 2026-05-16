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

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 0; exit 0 ;;
  *"os.getloadavg"*) echo 9999; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

out_no_work="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" staff proj --host=lunarc --dry-run 2>&1
)"
[[ "$out_no_work" == *"STAFF-DOWN proj/lunarc session=proj-lunarc reason=no_queued_work"* ]] || {
  printf 'expected staff to recommend shrink with no work, got:\n%s\n' "$out_no_work" >&2
  exit 1
}

out_gm_boot="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" gm-start proj --host=lunarc --dry-run 2>&1
)"
[[ "$out_gm_boot" == *"CEO-BOOT proj/lunarc session=proj-lunarc action=start_real_ceo_first panes=1 mode=dry-run"* ]] || {
  printf 'expected gm-start alias to plan the real CEO first, got:\n%s\n' "$out_gm_boot" >&2
  exit 1
}
[[ "$out_gm_boot" == *"CEO-NEXT proj/lunarc: after CEO reviews plans/work/resources, run csup staff"* ]] || {
  printf 'expected gm-start alias to delegate follow-on team staffing to CEO/csup staff, got:\n%s\n' "$out_gm_boot" >&2
  exit 1
}
[[ "$out_no_work" == *"GM-NOTE proj/lunarc"* ]] || {
  printf 'expected GM note for no-work SLURM shrink, got:\n%s\n' "$out_no_work" >&2
  exit 1
}

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
case "$*" in
  *"squeue"*"csup-station"*) echo "111|cx01"; exit 0 ;;
  *"tmux list-panes"*) echo 0; exit 0 ;;
  *"os.getloadavg"*) echo 9999; exit 0 ;;
  *"tmux -L"*"proj-lunarc-station-1"*"has-session"*"proj-lunarc-station-1"*) echo yes; exit 0 ;;
  *) echo remote-ok ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
: > "$FAKE_SSH_LOG"

out_gm_wake="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SLURM_WAIT_SECS=0 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" gm-start proj --host=lunarc --apply 2>&1
)"
[[ "$out_gm_wake" == *"SKIP proj/lunarc slot=1 job=111 node=cx01 session=proj-lunarc-station-1 reason=session_running"* ]] || {
  printf 'expected gm-start to detect running CEO station session, got:\n%s\n' "$out_gm_wake" >&2
  exit 1
}
[[ "$out_gm_wake" == *"CEO-WAKE proj/lunarc: queued re-run task in ceo.txt"* ]] || {
  printf 'expected gm-start to queue CEO wake task, got:\n%s\n' "$out_gm_wake" >&2
  exit 1
}
if ! grep -q -- "-o ControlPath=.*ceo.txt" "$FAKE_SSH_LOG"; then
  printf 'CEO wake remote write must use ssh_exec with the managed ControlPath/stdin guard\n' >&2
  cat "$FAKE_SSH_LOG" >&2
  exit 1
fi

cat > "$TMPDIR/home/Desktop/projects/proj/codex-tasks/open.txt" <<'TASKS'
/goal One
/goal Two
TASKS

out_work="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SLURM_WAIT_SECS=0 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" staff proj --host=lunarc --scenario=resume --dry-run 2>&1
)"
[[ "$out_work" == *"STAFF-UP proj/lunarc reason=queued_work work=2"* ]] || {
  printf 'expected staff to recommend adding workers for queued work, got:\n%s\n' "$out_work" >&2
  exit 1
}
[[ "$out_work" == *"FACTORY-RUN proj/lunarc scenario=resume work=2"* ]] || {
  printf 'expected staff to delegate to factory-run sizing, got:\n%s\n' "$out_work" >&2
  exit 1
}
[[ "$out_work" == *"panes=3"* ]] || {
  printf 'expected two workers plus a team manager pane, got:\n%s\n' "$out_work" >&2
  exit 1
}

echo "ok: CEO staff gate recommends shrink on no work and delegates scale-up to factory-run"
