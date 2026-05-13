#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

sent_goal_done="$TMPDIR/sent-goal-done"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ON_COMPLETE= \
CODEX_SUPERVISOR_RESEND_GRACE=1 \
SENT_FILE="$sent_goal_done" \
bash -c '
  source "$1"
  LANE_LABELS=(DATA)
  PROMPTS=("/goal repeat data lane")
  PANE_IDX=(0)
  ITERATION_STARTED[0]=$(($(date +%s) - 10))
  LAST_GOAL_DONE[0]=$(($(date +%s) - 2))
  RESPAWN_ON_GOAL_DONE=0
  CAPTURE="Goal achieved"
  pane_target() { echo "session:0.0"; }
  pane_dead() { return 1; }
  capture_tail() { printf "%s\n" "$CAPTURE"; }
  pop_next_task() { return 1; }
  send_prompt_to_pane() { printf "%s\n" "$2" > "$SENT_FILE"; return 0; }
  check_pane 0 "${PROMPTS[0]}"
' _ "$SCRIPT" > /dev/null

if [[ "$(cat "$sent_goal_done" 2>/dev/null || true)" != "/goal repeat data lane" ]]; then
  echo "goal-done pane should redo its original prompt by default when queue is empty" >&2
  exit 1
fi

sent_ready="$TMPDIR/sent-ready"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ON_COMPLETE= \
CODEX_SUPERVISOR_RESEND_GRACE=1 \
SENT_FILE="$sent_ready" \
bash -c '
  source "$1"
  LANE_LABELS=(QA)
  PROMPTS=("/goal repeat qa lane")
  PANE_IDX=(0)
  ITERATION_STARTED[0]=$(($(date +%s) - 10))
  LAST_GOAL_DONE[0]=0
  RESPAWN_ON_GOAL_DONE=0
  CAPTURE=$'"'"'Tip: New Use /fast for fastest inference.

› goal You are PANE 0, lane QA. Read docs/parallel-sessions.md.

gpt-5.5 xhigh fast · Ready · Context 100% left'"'"'
  pane_target() { echo "session:0.0"; }
  pane_dead() { return 1; }
  capture_tail() { printf "%s\n" "$CAPTURE"; }
  pop_next_task() { return 1; }
  send_prompt_to_pane() { printf "%s\n" "$2" > "$SENT_FILE"; return 0; }
  check_pane 0 "${PROMPTS[0]}"
' _ "$SCRIPT" > /dev/null

if [[ "$(cat "$sent_ready" 2>/dev/null || true)" != "/goal repeat qa lane" ]]; then
  echo "ready/idle pane should be retried instead of staying idle forever" >&2
  exit 1
fi

sent_unknown="$TMPDIR/sent-unknown"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ON_COMPLETE= \
CODEX_SUPERVISOR_RESEND_GRACE=1 \
SENT_FILE="$sent_unknown" \
bash -c '
  source "$1"
  LANE_LABELS=(SEC)
  PROMPTS=("/goal repeat sec lane")
  PANE_IDX=(0)
  ITERATION_STARTED[0]=$(($(date +%s) - 10))
  LAST_GOAL_DONE[0]=0
  RESPAWN_ON_GOAL_DONE=0
  CAPTURE=$'"'"'gpt-5.5 xhigh fast · /repo/path

› '"'"'
  pane_target() { echo "session:0.0"; }
  pane_dead() { return 1; }
  capture_tail() { printf "%s\n" "$CAPTURE"; }
  pop_next_task() { return 1; }
  send_prompt_to_pane() { printf "%s\n" "$2" > "$SENT_FILE"; return 0; }
  check_pane 0 "${PROMPTS[0]}"
' _ "$SCRIPT" > /dev/null

if [[ "$(cat "$sent_unknown" 2>/dev/null || true)" != "/goal repeat sec lane" ]]; then
  echo "unknown idle pane should be retried instead of staying idle forever" >&2
  exit 1
fi

respawned_ready="$TMPDIR/respawn-ready"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ON_COMPLETE= \
CODEX_SUPERVISOR_RESEND_GRACE=1 \
RESPAWN_FILE="$respawned_ready" \
bash -c '
  source "$1"
  LANE_LABELS=(DEBUG)
  PROMPTS=("/goal repeat debug lane")
  PANE_IDX=(0)
  ITERATION_STARTED[0]=$(($(date +%s) - 10))
  LAST_GOAL_DONE[0]=0
  RESPAWN_ON_GOAL_DONE=1
  CAPTURE=$'"'"'■ Failed to read thread goal: thread/goal/get failed in TUI

› Implement {feature}

gpt-5.5 low fast · Ready · Context 100% left'"'"'
  pane_target() { echo "session:0.0"; }
  pane_dead() { return 1; }
  capture_tail() { printf "%s\n" "$CAPTURE"; }
  pop_next_task() { return 1; }
  send_prompt_to_pane() { return 1; }
  respawn_pane_and_prompt() { printf "%s\n" "$2" > "$RESPAWN_FILE"; }
  check_pane 0 "${PROMPTS[0]}"
' _ "$SCRIPT" > /dev/null

if [[ "$(cat "$respawned_ready" 2>/dev/null || true)" != "/goal repeat debug lane" ]]; then
  echo "ready/idle panes with unconfirmed prompt send should respawn into a clean TUI" >&2
  exit 1
fi

echo "ok: panes auto-continue after goal-done, ready, unknown idle, and wedged ready stalls"
