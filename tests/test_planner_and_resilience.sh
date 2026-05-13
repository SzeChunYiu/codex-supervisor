#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Default behavior: one generated DEBUG lane and one generated VALIDATOR lane
# are added when the prompt file does not already define those fixed roles.
default_info="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; last=$((${#PROMPTS[@]} - 1)); echo "count=${#PROMPTS[@]}"; printf "lane=%s\n" "${LANE_LABELS[@]}"; echo "last_prompt=${PROMPTS[$last]}"' \
  _ "$SCRIPT")"

printf '%s\n' "$default_info" | grep -q '^count=4$' || { printf 'expected fixed roles to make 4 prompts, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q '^lane=DEBUG$' || { printf 'expected generated DEBUG lane, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q '^lane=VALIDATOR$' || { printf 'expected generated VALIDATOR lane, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q '/goal .*lane VALIDATOR' || { printf 'expected generated validator /goal prompt, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q 'validator-planner.md' || { printf 'validator prompt should reference validator-planner.md, got:\n%s\n' "$default_info" >&2; exit 1; }

# Operator can explicitly disable fixed roles for exceptional one-off runs.
count_without_planner="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_DEBUGGER=0 \
  CODEX_SUPERVISOR_PLANNER=0 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}"' _ "$SCRIPT")"
[[ "$count_without_planner" == "2" ]] || { echo "expected disabling fixed roles to keep 2 prompts, got $count_without_planner" >&2; exit 1; }

cat > "$TMPDIR/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane VALIDATOR. Read docs/parallel-sessions.md and docs/parallel-sessions/validator-planner.md, then update the team plan.
/goal You are PANE 1, lane DEBUG. Read docs/parallel-sessions.md and docs/parallel-sessions/debugger.md, then debug one slice.
/goal You are PANE 1, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
PROMPTS
count_with_existing="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}"' _ "$SCRIPT")"
[[ "$count_with_existing" == "3" ]] || { echo "existing fixed roles should not be duplicated, got $count_with_existing prompts" >&2; exit 1; }

cat > "$TMPDIR/codex-prompts-colon.txt" <<'PROMPTS'
/goal You are PANE 0, lane: LEADER. Read docs/parallel-sessions.md and docs/parallel-sessions/planner.md, then update the team plan.
PROMPTS
count_with_colon_leader="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_DEBUGGER=0 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts-colon.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}:${LANE_LABELS[0]}"' _ "$SCRIPT")"
[[ "$count_with_colon_leader" == "1:LEADER" ]] || { echo "lane: LEADER should satisfy the planner slot, got $count_with_colon_leader" >&2; exit 1; }

generated_workers="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_DEBUGGER=0 \
  CODEX_SUPERVISOR_PLANNER=0 \
  CODEX_SUPERVISOR_GENERATED_ONLY=1 \
  CODEX_SUPERVISOR_DYNAMIC_WORKERS=2 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; printf "%s\n" "${LANE_LABELS[@]}"' _ "$SCRIPT")"
[[ "$generated_workers" == $'WORKER-1\nWORKER-2' ]] || { echo "generated-only dynamic workers wrong: $generated_workers" >&2; exit 1; }

# Resilience defaults: dead panes are respawned, and a missing tmux session is
# recreated by the daemon instead of silently exiting.
CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  [[ "$AUTO_RESPAWN_DEAD_PANES" == "1" ]]
  [[ "$AUTO_RECREATE_SESSION" == "1" ]]
  type pane_dead >/dev/null
  type recreate_missing_session >/dev/null
' _ "$SCRIPT"
