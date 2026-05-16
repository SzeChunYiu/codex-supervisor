#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/codex-tasks"
cat > "$TMPDIR/codex-tasks/open.txt" <<'TASKS'
not a goal line
/goalbad malformed goal-like line
/goal open task one
/goal open task two
TASKS
cat > "$TMPDIR/codex-tasks/blockers.txt" <<'TASKS'
/goal shared blocker task
TASKS
cat > "$TMPDIR/codex-tasks/bugs.txt" <<'TASKS'
/goal specified bug task
TASKS
cat > "$TMPDIR/codex-tasks/worker-1.txt" <<'TASKS'
/goal worker-specific task
TASKS

first_worker="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_TASKS_DIR="$TMPDIR/codex-tasks" \
  bash -c 'source "$1"; pop_next_task "WORKER-1"' _ "$SCRIPT"
)"
[[ "$first_worker" == "/goal shared blocker task" ]] || {
  printf 'dynamic worker should take shared blockers before worker-specific work, got: %s\n' "$first_worker" >&2
  exit 1
}

second_worker="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_TASKS_DIR="$TMPDIR/codex-tasks" \
  bash -c 'source "$1"; pop_next_task "WORKER-1"' _ "$SCRIPT"
)"
[[ "$second_worker" == "/goal worker-specific task" ]] || {
  printf 'dynamic worker should return to worker-specific work after blockers clear, got: %s\n' "$second_worker" >&2
  exit 1
}

third_worker="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_TASKS_DIR="$TMPDIR/codex-tasks" \
  bash -c 'source "$1"; pop_next_task "WORKER-3"' _ "$SCRIPT"
)"
[[ "$third_worker" == "/goal open task one" ]] || {
  printf 'dynamic worker should take the shared open queue after blockers, got: %s\n' "$third_worker" >&2
  exit 1
}

bug_lane="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_TASKS_DIR="$TMPDIR/codex-tasks" \
  bash -c 'source "$1"; pop_next_task "BUGS"' _ "$SCRIPT"
)"
[[ "$bug_lane" == "/goal specified bug task" ]] || {
  printf 'specified lane should keep its lane queue, got: %s\n' "$bug_lane" >&2
  exit 1
}

remaining_open="$(grep -c '^/goal' "$TMPDIR/codex-tasks/open.txt")"
[[ "$remaining_open" == "2" ]] || {
  printf 'expected malformed /goal-like line plus one valid open task remaining, got %s\n' "$remaining_open" >&2
  exit 1
}
valid_remaining_open="$(grep -cE '^/goal([[:space:]]|$)' "$TMPDIR/codex-tasks/open.txt")"
[[ "$valid_remaining_open" == "1" ]] || {
  printf 'expected one valid open task remaining, got %s\n' "$valid_remaining_open" >&2
  exit 1
}
