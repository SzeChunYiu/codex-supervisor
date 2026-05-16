#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

log_file="$TMPDIR/tmux.log"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
TMUX_LOG="$log_file" \
bash -c '
  source "$1"
  sleep() { :; }
  tmux() {
    case "$1" in
      set-buffer|paste-buffer)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
      send-keys)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
      capture-pane)
        printf "Pursuing goal: test\n"
        ;;
      display-message)
        printf "⠋ gpt-5.5 xhigh fast · Working\n"
        ;;
      *)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
    esac
  }
  send_prompt_to_pane "demo:0.1" "/goal long prompt with spaces and /slashes"
' _ "$SCRIPT" >/dev/null

if ! grep -q '^set-buffer ' "$log_file"; then
  echo "send_prompt_to_pane should stage long prompts through tmux set-buffer" >&2
  cat "$log_file" >&2
  exit 1
fi
if ! grep -q '^paste-buffer ' "$log_file"; then
  echo "send_prompt_to_pane should paste staged prompt into the TUI" >&2
  cat "$log_file" >&2
  exit 1
fi
if grep -q ' C-a\\| C-k' "$log_file"; then
  echo "send_prompt_to_pane must not inject C-a/C-k; Codex can render them literally as ^A^K" >&2
  cat "$log_file" >&2
  exit 1
fi

title_log="$TMPDIR/tmux-title.log"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
TMUX_LOG="$title_log" \
bash -c '
  source "$1"
  sleep() { :; }
  tmux() {
    case "$1" in
      set-buffer|paste-buffer|send-keys)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
      capture-pane)
        printf "Tip: start a goal\n"
        ;;
      display-message)
        printf "⠋ gpt-5.5 xhigh fast · Working\n"
        ;;
      *)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
    esac
  }
  send_prompt_to_pane "demo:0.1" "/goal prompt whose visible capture stays blank"
' _ "$SCRIPT" >/dev/null

paste_count=$(grep -c '^paste-buffer ' "$title_log" || true)
if [[ "$paste_count" != "1" ]]; then
  echo "spinner pane titles should confirm active Codex work without repeated re-paste loops" >&2
  cat "$title_log" >&2
  exit 1
fi

ready_log="$TMPDIR/ready.log"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_READY_TIMEOUT=bad \
CODEX_SUPERVISOR_READY_SETTLE=bad \
READY_LOG="$ready_log" \
bash -c '
  source "$1"
  LANE_LABELS=(READY)
  PROMPTS=("/goal ready lane")
  PANE_IDX=(0)
  sleep() { printf "sleep=%s\n" "$1" >> "$READY_LOG"; }
  pane_target() { echo "demo:0.1"; }
  capture_tail() { printf "Tip: ready\n"; }
  send_prompt_to_pane() { printf "sent=%s\n" "$2" >> "$READY_LOG"; return 0; }
  wait_ready_and_send 0 "${PROMPTS[0]}"
' _ "$SCRIPT" >/dev/null

grep -q '^sleep=5$' "$ready_log" || {
  echo "invalid READY_SETTLE should sanitize to the default before sleep" >&2
  cat "$ready_log" >&2
  exit 1
}
grep -q '^sent=/goal ready lane$' "$ready_log" || {
  echo "invalid READY_TIMEOUT should not stop ready prompt delivery" >&2
  cat "$ready_log" >&2
  exit 1
}

stale_log="$TMPDIR/tmux-stale.log"
if CODEX_SUPERVISOR_TEST_SOURCE=1 \
TMUX_LOG="$stale_log" \
bash -c '
  source "$1"
  sleep() { :; }
  tmux() {
    case "$1" in
      set-buffer|paste-buffer|send-keys)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
      capture-pane)
        # Same stale activity marker before and after paste; no spinner title.
        # This used to be misread as successful submission while the prompt was
        # still sitting in the composer.
        printf "• Goal active Objective: previous task\n› /goal new task still in composer\n"
        ;;
      display-message)
        printf "babbloo-codex\n"
        ;;
      *)
        printf "%s\n" "$*" >> "$TMUX_LOG"
        ;;
    esac
  }
  send_prompt_to_pane "demo:0.1" "/goal new task still in composer"
' _ "$SCRIPT" >/dev/null; then
  echo "stale scrollback activity must not confirm a newly pasted prompt" >&2
  cat "$stale_log" >&2
  exit 1
fi

echo "ok: prompt sending uses tmux paste-buffer and spinner titles for reliable long prompt entry"
