#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/root/run" "$TMPDIR/project/codex-tasks"
printf '/goal state helper test\n' > "$TMPDIR/project/prompts.txt"

cat > "$TMPDIR/root/run/state-test.state" <<STATE
FOOXBAR=wrong-regex-match
FOO.BAR=literal-dot-match
PROMPTS_FILE=prompts.txt
TASKS_DIR=$TMPDIR/project/codex-tasks
PROJECT_ROOT=$TMPDIR/project
STATE

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/root" \
CODEX_SUPERVISOR_SESSION=state-test \
CODEX_SUPERVISOR_STATE_FILE="$TMPDIR/root/run/state-test.state" \
  bash -c '
    set -euo pipefail
    source "$1"

    literal_value="$(state_value "FOO.BAR")"
    if [[ "$literal_value" != "literal-dot-match" ]]; then
      printf "state_value should match literal keys, got: %s\n" "$literal_value" >&2
      exit 1
    fi

    PROMPTS_FILE=""
    resolve_prompts_file
    if [[ "$PROMPTS_FILE" != "$2/project/prompts.txt" ]]; then
      printf "resolve_prompts_file should resolve relative state paths against PROJECT_ROOT, got: %s\n" "$PROMPTS_FILE" >&2
      exit 1
    fi

    TASKS_DIR=""
    resolve_tasks_dir
    if [[ "$TASKS_DIR" != "$2/project/codex-tasks" ]]; then
      printf "resolve_tasks_dir should load TASKS_DIR from state, got: %s\n" "$TASKS_DIR" >&2
      exit 1
    fi
  ' _ "$SCRIPT" "$TMPDIR"

echo "ok: state file helpers use literal keys and resolve persisted paths"
