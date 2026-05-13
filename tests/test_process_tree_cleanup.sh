#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 0 ;;
  list-panes)
    printf '%s\n' "$FAKE_PANE_PID"
    exit 0
    ;;
  display-message)
    printf '%s\n' "$FAKE_PANE_PID"
    exit 0
    ;;
  kill-session|respawn-pane)
    exit 0
    ;;
esac
exit 0
TMUX
chmod +x "$TMPDIR/bin/tmux"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
PATH="$TMPDIR/bin:$PATH" \
  bash -c '
    set -euo pipefail
    source "$1"

    # Simulate a Codex pane process running a script that starts a child
    # script, which then starts a long-running command. Killing only the
    # pane/root shell would leave descendants reparented to launchd/init.
    root_pid=""
    child_pid=""
    grandchild_pid=""
    cleanup_procs() {
      for pid in "$grandchild_pid" "$child_pid" "$root_pid"; do
        [[ -n "${pid:-}" ]] && kill -TERM "$pid" 2>/dev/null || true
      done
    }
    trap cleanup_procs EXIT

    bash -c "bash -c '\''sleep 999 & wait'\'' & wait" &
    root_pid=$!

    for _ in 1 2 3 4 5 6 7 8 9 10; do
      child_pid=$(pgrep -P "$root_pid" 2>/dev/null | head -1 || true)
      if [[ -n "$child_pid" ]]; then
        grandchild_pid=$(pgrep -P "$child_pid" 2>/dev/null | head -1 || true)
        [[ -n "$grandchild_pid" ]] && break
      fi
      sleep 0.1
    done

    [[ -n "$child_pid" ]] || { echo "child process did not start" >&2; exit 1; }
    [[ -n "$grandchild_pid" ]] || { echo "grandchild process did not start" >&2; exit 1; }

    terminate_process_tree "$root_pid" "test pane" >/dev/null 2>&1

    direct_done=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if ! kill -0 "$root_pid" 2>/dev/null \
         && ! kill -0 "$child_pid" 2>/dev/null \
         && ! kill -0 "$grandchild_pid" 2>/dev/null; then
        direct_done=1
        break
      fi
      sleep 0.1
    done

    if (( ! direct_done )); then
      echo "direct process tree survived: root=$root_pid child=$child_pid grandchild=$grandchild_pid" >&2
      ps -o pid=,ppid=,command= -p "$root_pid" "$child_pid" "$grandchild_pid" 2>/dev/null >&2 || true
      exit 1
    fi

    bash -c "bash -c '\''sleep 999 & wait'\'' & wait" &
    root_pid=$!
    child_pid=""
    grandchild_pid=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      child_pid=$(pgrep -P "$root_pid" 2>/dev/null | head -1 || true)
      if [[ -n "$child_pid" ]]; then
        grandchild_pid=$(pgrep -P "$child_pid" 2>/dev/null | head -1 || true)
        [[ -n "$grandchild_pid" ]] && break
      fi
      sleep 0.1
    done
    [[ -n "$child_pid" && -n "$grandchild_pid" ]]

    FAKE_PANE_PID="$root_pid" terminate_session_process_trees >/dev/null 2>&1

    session_done=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      if ! kill -0 "$root_pid" 2>/dev/null \
         && ! kill -0 "$child_pid" 2>/dev/null \
         && ! kill -0 "$grandchild_pid" 2>/dev/null; then
        session_done=1
        break
      fi
      sleep 0.1
    done

    if (( ! session_done )); then
      echo "session process tree survived: root=$root_pid child=$child_pid grandchild=$grandchild_pid" >&2
      ps -o pid=,ppid=,command= -p "$root_pid" "$child_pid" "$grandchild_pid" 2>/dev/null >&2 || true
      exit 1
    fi
  ' _ "$SCRIPT"
