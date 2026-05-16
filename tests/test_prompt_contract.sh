#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

run_prompt_check() {
  local prompt="$1"
  CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
    'source "$1"; validate_prompt_line "$2" "test-prompts" 1' \
    _ "$SCRIPT" "$prompt" >/tmp/codex-supervisor-prompt.out 2>/tmp/codex-supervisor-prompt.err
}

valid="/goal You are PANE 0, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then iterate per the protocol until rate-limited."
run_prompt_check "$valid"

CODEX_SUPERVISOR_TEST_SOURCE=1 CODEX_SUPERVISOR_MAX_PROMPT_WORDS=bad bash -c \
  'source "$1"; validate_prompt_line "$2" "test-prompts" 1' \
  _ "$SCRIPT" "$valid"

if run_prompt_check "You are PANE 0, lane BUGS. Read docs/parallel-sessions.md."; then
  echo "prompt without /goal should fail" >&2
  exit 1
fi
if ! grep -q "must start with /goal" /tmp/codex-supervisor-prompt.err; then
  echo "missing /goal error message should explain the prompt contract" >&2
  cat /tmp/codex-supervisor-prompt.err >&2
  exit 1
fi

if run_prompt_check "/goal You are PANE 0, lane BUGS. Fix bugs until rate-limited."; then
  echo "prompt without md reference should fail" >&2
  exit 1
fi
if ! grep -q "must reference" /tmp/codex-supervisor-prompt.err; then
  echo "missing md-reference error should explain where extra instructions live" >&2
  cat /tmp/codex-supervisor-prompt.err >&2
  exit 1
fi

long="/goal "
for i in $(seq 1 50); do long+="w$i "; done
long+="docs/parallel-sessions.md"
if run_prompt_check "$long"; then
  echo "prompt over the 50-word budget should fail" >&2
  exit 1
fi
if ! grep -q "50 words or fewer" /tmp/codex-supervisor-prompt.err; then
  echo "word-budget error should mention the 50-word limit" >&2
  cat /tmp/codex-supervisor-prompt.err >&2
  exit 1
fi

cat > "$TMPDIR/codex-prompts.txt" <<'PROMPTS'
# comments and blank lines are ignored

/goal You are PANE 0, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then iterate per the protocol until rate-limited.
bad prompt
PROMPTS

if CODEX_SUPERVISOR_TEST_SOURCE=1 CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts.txt" \
  bash -c 'source "$1"; load_prompts' _ "$SCRIPT" \
  >/tmp/codex-supervisor-load.out 2>/tmp/codex-supervisor-load.err; then
  echo "load_prompts should reject invalid prompt files" >&2
  exit 1
fi
if ! grep -q "line 4" /tmp/codex-supervisor-load.err; then
  echo "load_prompts error should include invalid line number" >&2
  cat /tmp/codex-supervisor-load.err >&2
  exit 1
fi

CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c \
  'source "$1"; [[ "$MAX_ITERATION_SECS" == "2700" ]]' \
  _ "$SCRIPT"

CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  "$SCRIPT" validate-prompts \
  >/tmp/codex-supervisor-validate.out
if ! grep -q "ok: 3 prompts" /tmp/codex-supervisor-validate.out; then
  echo "validate-prompts should accept the checked-in example prompts plus the fixed CEO role" >&2
  cat /tmp/codex-supervisor-validate.out >&2
  exit 1
fi

if CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_MAX_PANES=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts' _ "$SCRIPT" \
  >/tmp/codex-supervisor-max-panes.out 2>/tmp/codex-supervisor-max-panes.err; then
  echo "load_prompts should reject prompt files over the pane cap" >&2
  exit 1
fi
if ! grep -q "at most 1 panes" /tmp/codex-supervisor-max-panes.err; then
  echo "pane-cap error should mention the configured maximum" >&2
  cat /tmp/codex-supervisor-max-panes.err >&2
  exit 1
fi

CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_MAX_PANES=bad \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; [[ "${#PROMPTS[@]}" == "3" ]]' _ "$SCRIPT"
