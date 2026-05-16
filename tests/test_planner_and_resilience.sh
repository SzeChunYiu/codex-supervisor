#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Default behavior: a generated real CEO lane is added when the prompt file
# does not already define an executive role. DEBUG/VALIDATOR are opt-in.
default_info="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; last=$((${#PROMPTS[@]} - 1)); echo "count=${#PROMPTS[@]}"; printf "lane=%s\n" "${LANE_LABELS[@]}"; printf "prompt=%s\n" "${PROMPTS[@]}"; echo "last_prompt=${PROMPTS[$last]}"' \
  _ "$SCRIPT")"

printf '%s\n' "$default_info" | grep -q '^count=3$' || { printf 'expected fixed CEO role to make 3 prompts, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q '^lane=CEO$' || { printf 'expected generated CEO lane, got:\n%s\n' "$default_info" >&2; exit 1; }
printf '%s\n' "$default_info" | grep -q 'decide teams, priorities, staffing, escalations' || { printf 'CEO prompt must decide teams, priorities, staffing, and escalations, got:\n%s\n' "$default_info" >&2; exit 1; }

# Operator can explicitly disable fixed roles for exceptional one-off runs.
count_without_planner="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_GM=0 \
  CODEX_SUPERVISOR_DEBUGGER=0 \
  CODEX_SUPERVISOR_PLANNER=0 \
  CODEX_SUPERVISOR_PROMPTS="$ROOT/codex-prompts.example.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}"' _ "$SCRIPT")"
[[ "$count_without_planner" == "2" ]] || { echo "expected disabling fixed roles to keep 2 prompts, got $count_without_planner" >&2; exit 1; }

cat > "$TMPDIR/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane CEO. Read docs/parallel-sessions.md and docs/parallel-sessions/ceo-executive.md, then set direction.
/goal You are PANE 0, lane MANAGER. Read docs/parallel-sessions.md and docs/parallel-sessions/general-manager.md, then manage the team.
/goal You are PANE 1, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
PROMPTS
count_with_existing="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}"' _ "$SCRIPT")"
[[ "$count_with_existing" == "3" ]] || { echo "existing CEO/manager roles should not be duplicated, got $count_with_existing prompts" >&2; exit 1; }

cat > "$TMPDIR/codex-prompts-colon.txt" <<'PROMPTS'
/goal You are PANE 0, lane: LEADER. Read docs/parallel-sessions.md and docs/parallel-sessions/planner.md, then update the team plan.
PROMPTS
count_with_colon_leader="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_GM=0 \
  CODEX_SUPERVISOR_DEBUGGER=0 \
  CODEX_SUPERVISOR_PROMPTS="$TMPDIR/codex-prompts-colon.txt" \
  bash -c 'source "$1"; load_prompts; echo "${#PROMPTS[@]}:${LANE_LABELS[0]}"' _ "$SCRIPT")"
[[ "$count_with_colon_leader" == "1:LEADER" ]] || { echo "lane: LEADER should satisfy the planner slot, got $count_with_colon_leader" >&2; exit 1; }

generated_workers="$(CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_SUPERVISOR_GM=0 \
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
  if [[ "$AUTO_RESPAWN_DEAD_PANES" != "1" ]]; then
    echo "AUTO_RESPAWN_DEAD_PANES should default to 1" >&2
    exit 1
  fi
  if [[ "$AUTO_RECREATE_SESSION" != "1" ]]; then
    echo "AUTO_RECREATE_SESSION should default to 1" >&2
    exit 1
  fi
  type pane_dead >/dev/null
  type recreate_missing_session >/dev/null
' _ "$SCRIPT"
