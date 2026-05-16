#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HOSTNAME_MATCH="$(uname -n)"
mkdir -p "$TMPDIR/home/Desktop/projects/proj/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<HOSTS
[hosts."mac-mini"]
ssh = "local"
hostname_match = "$HOSTNAME_MATCH"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1

[project]
name = "proj"

[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-main"
TOML

cat > "$TMPDIR/home/Desktop/projects/proj/codex-prompts.txt" <<'PROMPTS'
/goal lane one
/goal lane two
/goal lane three
PROMPTS

cat > "$TMPDIR/home/Desktop/projects/proj/codex-tasks/bugs.txt" <<'TASKS'
/goal bug task
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj/codex-tasks/worker-a.txt" <<'TASKS'
/goal worker task one
/goal worker task two
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj/codex-tasks/open.txt" <<'TASKS'
/goal open task one
/goal open task two
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

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" factory-run proj --host=mac-mini --dry-run --max-panes=4
)"

[[ "$out" == *"FACTORY-RUN proj/mac-mini scenario=resume work=5 blockers=0 mode=dry-run delegate=govern"* ]] || {
  printf 'expected local factory-run to delegate to govern, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" == *"capacity=4 pane(s) bottleneck=operator_cap"* ]] || {
  printf 'expected local factory-run --max-panes to cap govern capacity, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" == *"START proj/mac-mini session=proj-main lanes=worker-a,bugs dynamic_workers=0 panes=4 queued=5"* ]] || {
  printf 'expected local factory-run --max-panes to cap delegated start plan, got:\n%s\n' "$out" >&2
  exit 1
}

echo "ok: local factory-run forwards max-panes to govern"
