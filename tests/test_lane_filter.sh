#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
/goal You are PANE 1, lane PERF. Read docs/parallel-sessions.md and docs/parallel-sessions/perf.md, then complete one compact-safe iteration.
/goal You are PANE 2, lane worker-a. Read docs/parallel-sessions.md and docs/parallel-sessions/worker-a.md, then complete one compact-safe iteration.
/goal You are PANE 3, lane worker-b. Read docs/parallel-sessions.md and docs/parallel-sessions/worker-b.md, then complete one compact-safe iteration.
PROMPTS

labels="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/prompts.txt" \
  CODEX_SUPERVISOR_PLANNER=0 \
  CODEX_SUPERVISOR_LANES='perf,WORKER-B' \
  bash -c 'source "$1"; load_prompts; printf "%s\n" "${LANE_LABELS[@]}"' _ "$SCRIPT"
)"

expected=$'PERF\nworker-b'
[[ "$labels" == "$expected" ]] || {
  printf 'lane filter should keep only requested lanes, got:\n%s\n' "$labels" >&2
  exit 1
}

planner_prompt="$(
  CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/prompts.txt" \
  CODEX_SUPERVISOR_LANES='bugs,worker-a' \
  bash -c 'source "$1"; load_prompts; last=$((${#PROMPTS[@]} - 1)); printf "%s\n" "${PROMPTS[$last]}"' _ "$SCRIPT"
)"

if [[ "$planner_prompt" != "/goal You are PANE 2, lane PLANNER."* ]]; then
  printf 'generated planner should be indexed after filtered lanes, got:\n%s\n' "$planner_prompt" >&2
  exit 1
fi

if CODEX_SUPERVISOR_TEST_SOURCE=1 \
   CODEX_SUPERVISOR_PROMPTS="$TMPDIR/prompts.txt" \
   CODEX_SUPERVISOR_PLANNER=0 \
   CODEX_SUPERVISOR_LANES='missing' \
   bash -c 'source "$1"; load_prompts' _ "$SCRIPT" >/tmp/codex-supervisor-lanes.out 2>/tmp/codex-supervisor-lanes.err; then
  echo "load_prompts should fail when the lane filter matches no prompts" >&2
  exit 1
fi
grep -q "matched no prompts" /tmp/codex-supervisor-lanes.err
