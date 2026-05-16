#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/codex-tasks"
cat > "$TMPDIR/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane bugs. Read docs/parallel-sessions.md, then do one task.
PROMPTS
cat > "$TMPDIR/codex-tasks/bugs.txt" <<'TASKS'
/goalbad malformed task should not count
not a goal
/goal valid bug task
TASKS
cat > "$TMPDIR/codex-tasks/bad,lane.txt" <<'TASKS'
/goal unsafe filename task should not render
TASKS

out="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts.txt" \
  CODEX_SUPERVISOR_TASKS_DIR="$TMPDIR/codex-tasks" \
    bash -c 'source "$1"; cmd_queue' _ "$SCRIPT"
)"

[[ "$out" == *"bugs.txt"* ]] || {
  printf 'queue output should include bugs queue, got:\n%s\n' "$out" >&2
  exit 1
}
grep -Eq '^bugs[.]txt[[:space:]]+1[[:space:]]+/goal valid bug task$' <<<"$out" || {
  printf 'queue output should count and preview only valid /goal lines, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" != *"/goalbad"* ]] || {
  printf 'queue preview should not select malformed /goal-like lines, got:\n%s\n' "$out" >&2
  exit 1
}
[[ "$out" != *"bad,lane.txt"* && "$out" != *"unsafe filename"* ]] || {
  printf 'queue output should ignore unsafe queue filenames, got:\n%s\n' "$out" >&2
  exit 1
}

echo "ok: queue display counts only valid goal lines"
