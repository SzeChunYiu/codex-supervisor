#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HOSTNAME_MATCH="$(uname -n)"
mkdir -p "$TMPDIR/home/Desktop/projects/proj-open/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<HOSTS
[hosts."mac-mini"]
ssh = "local"
hostname_match = "$HOSTNAME_MATCH"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj-open/.codex-supervisor.toml" <<'TOML'
schema_version = 1

[project]
name = "proj-open"

[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-open-main"
TOML

cat > "$TMPDIR/home/Desktop/projects/proj-open/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane bugs. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
/goal You are PANE 1, lane perf. Read docs/parallel-sessions.md and docs/parallel-sessions/perf.md, then complete one compact-safe iteration.
PROMPTS

cat > "$TMPDIR/home/Desktop/projects/proj-open/codex-tasks/open.txt" <<'TASKS'
/goal open task one
/goal open task two
/goal open task three
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-open/codex-tasks/blockers.txt" <<'TASKS'
/goal resolve shared blocker
TASKS

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
  echo "lanes=$CODEX_SUPERVISOR_LANES"
  echo "dynamic_workers=$CODEX_SUPERVISOR_DYNAMIC_WORKERS"
  echo "reviewer=$CODEX_SUPERVISOR_REVIEWER"
  echo "generated_only=$CODEX_SUPERVISOR_GENERATED_ONLY"
  echo "max_panes=$CODEX_SUPERVISOR_MAX_PANES"
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
  "$CSUP" govern --dry-run --project=proj-open
)"

if [[ "$dry_run" != *"START proj-open/mac-mini session=proj-open-main lanes=generated-only dynamic_workers=4 panes=6 queued=4"* ]]; then
  printf 'govern dry-run should count blocker and open queues as generated dynamic-worker work, got:\n%s\n' "$dry_run" >&2
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
  "$CSUP" govern --apply --project=proj-open >/tmp/csup-dynamic-apply.out

grep -q '^lanes=$' "$TMPDIR/capture.txt"
grep -q '^dynamic_workers=4$' "$TMPDIR/capture.txt"
grep -q '^reviewer=1$' "$TMPDIR/capture.txt"
grep -q '^generated_only=1$' "$TMPDIR/capture.txt"
grep -q '^max_panes=6$' "$TMPDIR/capture.txt"
