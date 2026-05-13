#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HOSTNAME_MATCH="$(uname -n)"
mkdir -p "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<HOSTS
[hosts."mac-mini"]
ssh = "local"
hostname_match = "$HOSTNAME_MATCH"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj-a/.codex-supervisor.toml" <<'TOML'
schema_version = 1

[project]
name = "proj-a"

[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-a-main"
TOML

cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane bugs. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
/goal You are PANE 1, lane perf. Read docs/parallel-sessions.md and docs/parallel-sessions/perf.md, then complete one compact-safe iteration.
/goal You are PANE 2, lane worker-a. Read docs/parallel-sessions.md and docs/parallel-sessions/worker-a.md, then complete one compact-safe iteration.
PROMPTS

cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/bugs.txt" <<'TASKS'
/goal bug task one
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/worker-a.txt" <<'TASKS'
/goal worker task one
/goal worker task two
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/open.txt" <<'TASKS'
/goal open task one
/goal open task two
TASKS
: > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt"

cat > "$TMPDIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  list-sessions) exit 0 ;;
  list-panes) exit 0 ;;
esac
exit 0
TMUX
chmod +x "$TMPDIR/bin/tmux"

cat > "$TMPDIR/supervisor" <<'SUPERVISOR'
#!/usr/bin/env bash
{
  echo "session=$CODEX_SUPERVISOR_SESSION"
  echo "prompts=$CODEX_SUPERVISOR_PROMPTS"
  echo "tasks=$CODEX_SUPERVISOR_TASKS_DIR"
  echo "lanes=$CODEX_SUPERVISOR_LANES"
  echo "dynamic_workers=$CODEX_SUPERVISOR_DYNAMIC_WORKERS"
  echo "generated_only=$CODEX_SUPERVISOR_GENERATED_ONLY"
  echo "max_panes=$CODEX_SUPERVISOR_MAX_PANES"
  echo "args=$*"
} > "$CSUP_CAPTURE_FILE"
echo "fake supervisor started"
SUPERVISOR
chmod +x "$TMPDIR/supervisor"

dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run
)"

if [[ "$dry_run" != *"START proj-a/mac-mini session=proj-a-main lanes=worker-a,bugs dynamic_workers=2 panes=6 queued=5"* ]]; then
  printf 'govern dry-run should propose queued lanes in priority order, got:\n%s\n' "$dry_run" >&2
  exit 1
fi

CSUP_CAPTURE_FILE="$TMPDIR/capture.txt" \
HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_SUPERVISOR="$TMPDIR/supervisor" \
CSUP_GOVERNOR_FREE_RAM_MB=16000 \
CSUP_GOVERNOR_FREE_DISK_GB=100 \
CSUP_GOVERNOR_LOAD1=0 \
CSUP_GOVERNOR_CPU_COUNT=10 \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --apply >/tmp/csup-governor-apply.out

grep -q '^session=proj-a-main$' "$TMPDIR/capture.txt"
grep -q '^lanes=worker-a,bugs$' "$TMPDIR/capture.txt"
grep -q '^dynamic_workers=2$' "$TMPDIR/capture.txt"
grep -q '^generated_only=0$' "$TMPDIR/capture.txt"
grep -q '^max_panes=6$' "$TMPDIR/capture.txt"
grep -q '^args=start --no-attach$' "$TMPDIR/capture.txt"

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_SUPERVISOR="$TMPDIR/supervisor" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" submit proj-a perf "check the perf queue" >/tmp/csup-submit.out

grep -q '^/goal check the perf queue$' "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt"
grep -q "queued proj-a/perf" /tmp/csup-submit.out
