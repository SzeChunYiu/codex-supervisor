#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Default behavior: one generated PLANNER lane is added when the prompt file
# does not already define a planner.
default_info="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; last=$((${#PROMPTS[@]} - 1)); echo "count=${#PROMPTS[@]}"; echo "last_lane=${LANE_LABELS[$last]}"; echo "last_prompt=${PROMPTS[$last]}"' \
  _ "$SCRIPT")"

printf '%s\n' "$default_info" | grep -q '^count=3$' || { printf 'expected planner to make 3 prompts, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q '^last_lane=PLANNER$' || { printf 'expected final lane to be PLANNER, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q '/goal .*lane PLANNER' || { printf 'expected generated planner /goal prompt, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q 'planner.md' || { printf 'planner prompt should reference planner.md, got:\n%s\n' "$default_info" >&2; exit 1; }

# Operator can explicitly disable the planner for exceptional one-off runs.
count_without_planner="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PLANNER=0 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}"' _ "$SCRIPT")"
[[ "$count_without_planner" == "2" ]] || { echo "expected disabling planner to keep 2 prompts, got $count_without_planner" >&2; exit 1; }

cat > "$TMPDIR/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane PLANNER. Read docs/parallel-sessions.md and docs/parallel-sessions/planner.md, then update the team plan.
/goal You are PANE 1, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
PROMPTS
count_with_existing="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}"' _ "$SCRIPT")"
[[ "$count_with_existing" == "2" ]] || { echo "existing planner should not be duplicated, got $count_with_existing prompts" >&2; exit 1; }

cat > "$TMPDIR/codex-prompts-colon.txt" <<'PROMPTS'
/goal You are PANE 0, lane: LEADER. Read docs/parallel-sessions.md and docs/parallel-sessions/planner.md, then update the team plan.
PROMPTS
count_with_colon_leader="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts-colon.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}:${LANE_LABELS[0]}"' _ "$SCRIPT")"
[[ "$count_with_colon_leader" == "1:LEADER" ]] || { echo "lane: LEADER should satisfy the planner slot, got $count_with_colon_leader" >&2; exit 1; }

# Resilience defaults: dead panes are respawned, and a missing tmux session is
# recreated by the daemon instead of silently exiting.
CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  [[ "$AUTO_RESPAWN_DEAD_PANES" == "1" ]]
  [[ "$AUTO_RECREATE_SESSION" == "1" ]]
  type pane_dead >/dev/null
  type recreate_missing_session >/dev/null
' _ "$SCRIPT"
