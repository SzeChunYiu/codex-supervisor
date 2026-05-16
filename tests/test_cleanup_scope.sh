#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/projects/current-proj" "$TMPDIR/projects/current-proj-worker" "$TMPDIR/projects/other-proj-worker"
mkdir -p \
  "$TMPDIR/home" \
  "$TMPDIR/private-tmp/current-proj-temp" \
  "$TMPDIR/private-tmp/current-proj-recent" \
  "$TMPDIR/private-tmp/other-proj-temp" \
  "$TMPDIR/superpowers/worktrees/current-proj/old-worker" \
  "$TMPDIR/superpowers/worktrees/other-proj/old-worker" \
  "$TMPDIR/projects/current-proj/.next" \
  "$TMPDIR/projects/current-proj/app with spaces/.next" \
  "$TMPDIR/projects/other-proj/.next"
printf gitdir > "$TMPDIR/projects/current-proj-worker/.git"
printf gitdir > "$TMPDIR/projects/other-proj-worker/.git"
touch -t 202001010000 \
  "$TMPDIR/private-tmp/current-proj-temp" \
  "$TMPDIR/private-tmp/other-proj-temp" \
  "$TMPDIR/superpowers/worktrees/current-proj/old-worker" \
  "$TMPDIR/superpowers/worktrees/other-proj/old-worker" \
  "$TMPDIR/projects/current-proj-worker" \
  "$TMPDIR/projects/other-proj-worker" \
  "$TMPDIR/projects/current-proj/.next" \
  "$TMPDIR/projects/current-proj/app with spaces/.next" \
  "$TMPDIR/projects/other-proj/.next"
python3 - "$TMPDIR/private-tmp/current-proj-recent" <<'PY'
import os
import sys
import time
old = time.time() - 3600
os.utime(sys.argv[1], (old, old))
PY
ln -s ../other-proj "$TMPDIR/projects/current-proj/link-out"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
HOME="$TMPDIR/home" \
CODEX_SUPERVISOR_SESSION=current-proj \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
CODEX_SUPERVISOR_PROJECTS_ROOT="$TMPDIR/projects" \
CODEX_SUPERVISOR_TMP_SWEEP_ROOT="$TMPDIR/private-tmp" \
CODEX_SUPERVISOR_SUPERPOWERS_WORKTREES_ROOT="$TMPDIR/superpowers/worktrees" \
CODEX_SUPERVISOR_MYDRIVE_SUPERPOWERS_WORKTREES_ROOT="$TMPDIR/mydrive/worktrees" \
CODEX_SUPERVISOR_ACTIONS_RUNNER_WORK_ROOT="$TMPDIR/actions-runner-work" \
CODEX_SUPERVISOR_CODEX_LOG_MAX_GB=0 \
CODEX_SUPERVISOR_LOG_MAX_MB=999999 \
CODEX_SUPERVISOR_CODEX_SESSIONS_RETAIN_DAYS=999999 \
CODEX_SUPERVISOR_PERIODIC_CLEANUP_SECS=0 \
  bash -c '
    set -euo pipefail
    source "$1"
    assert_exists() {
      if [[ ! -e "$1" ]]; then
        echo "expected path to exist: $1" >&2
        exit 1
      fi
    }
    assert_missing() {
      if [[ -e "$1" ]]; then
        echo "expected path to be removed: $1" >&2
        exit 1
      fi
    }
    cd "$2/projects/current-proj"

    [[ $(nonnegative_int_or_default 999999 3 365) == 3 ]] || {
      echo "cleanup day caps should fail closed to default" >&2
      exit 1
    }
    [[ $(nonnegative_int_or_default 999999 50 1000) == 50 ]] || {
      echo "cleanup log caps should fail closed to default" >&2
      exit 1
    }
    [[ $(nonnegative_int_or_default 999999 1 100) == 1 ]] || {
      echo "periodic Codex log caps should fail closed to default" >&2
      exit 1
    }

    printf "%s\n" "name = \"../other-proj\"" > .codex-supervisor.toml
    scopes="$(SESSION="../other-proj" cleanup_scope_names)"
    if printf "%s\n" "$scopes" | grep -Eq "/|\.\."; then
      echo "cleanup scope names should reject traversal-like session/config names:" >&2
      printf "%s\n" "$scopes" >&2
      exit 1
    fi
    long_scope="$(printf "%0129d" 0 | tr 0 x)"
    if SESSION="$long_scope" cleanup_scope_names | grep -q "$long_scope"; then
      echo "cleanup scope names should reject oversized session names" >&2
      exit 1
    fi

    cleanup_path_in_project_scope "$2/projects/current-proj-worker" || exit 1
    cleanup_path_under_current_project "$2/projects/current-proj/.next" || {
      echo "project cleanup should accept canonical in-project paths" >&2
      exit 1
    }
    if cleanup_path_in_project_scope "$2/projects/other-proj-worker"; then
      echo "project cleanup scope should not match sibling project worker" >&2
      exit 1
    fi
    if cleanup_path_under_current_project "$2/projects/current-proj/../other-proj/.next"; then
      echo "project cleanup should reject parent traversal outside current project" >&2
      exit 1
    fi
    if cleanup_path_under_current_project "$2/projects/current-proj/link-out/.next"; then
      echo "project cleanup should reject symlink traversal outside current project" >&2
      exit 1
    fi

    CODEX_SUPERVISOR_GLOBAL_CLEANUP=1 cleanup_path_in_project_scope "$2/projects/other-proj-worker"

    CODEX_SUPERVISOR_GLOBAL_CLEANUP=0
    GLOBAL_CLEANUP=0
    PERIODIC_WORKTREE_AGE_MIN=999999
    CODEX_LOG_MAX_GB=999999
    SUPERVISOR_LOG_MAX_MB=999999
    python3 - "$LOG_FILE" <<'"'"'PY'"'"'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("wb") as f:
    chunk = b"x" * (1024 * 1024)
    for _ in range(61):
        f.write(chunk)
PY
    run_periodic_cleanup

    assert_missing "$2/private-tmp/current-proj-temp"
    assert_missing "$2/private-tmp/current-proj-recent"
    assert_exists "$2/private-tmp/other-proj-temp"
    assert_missing "$2/superpowers/worktrees/current-proj/old-worker"
    assert_exists "$2/superpowers/worktrees/other-proj/old-worker"
    assert_missing "$2/projects/current-proj-worker"
    assert_exists "$2/projects/other-proj-worker"
    log_size="$(python3 - "$LOG_FILE" <<'"'"'PY'"'"'
import os
import sys
print(os.path.getsize(sys.argv[1]))
PY
)"
    if (( log_size > 1024 * 1024 )); then
      echo "periodic cleanup should sanitize oversized supervisor log cap and rotate the log" >&2
      exit 1
    fi

    SUPERVISOR_LOG_MAX_MB=999999
    CODEX_SESSIONS_RETAIN_DAYS=999999
    python3 - "$LOG_FILE" <<'"'"'PY'"'"'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
path.parent.mkdir(parents=True, exist_ok=True)
with path.open("wb") as f:
    chunk = b"x" * (1024 * 1024)
    for _ in range(61):
        f.write(chunk)
PY
    PRUNE_WORKTREE_AGE_HOURS=-1
    cmd_cleanup
    PRUNE_WORKTREE_AGE_HOURS=999999
    [[ $(signed_int_or_default "$PRUNE_WORKTREE_AGE_HOURS" 1 -1 8760) == 1 ]] || {
      echo "oversized prune age should fail closed to default" >&2
      exit 1
    }
    cmd_cleanup
    PRUNE_WORKTREE_AGE_HOURS=-999999
    [[ $(signed_int_or_default "$PRUNE_WORKTREE_AGE_HOURS" 1 -1 8760) == 1 ]] || {
      echo "overly negative prune age should fail closed to default" >&2
      exit 1
    }
    cmd_cleanup
    PRUNE_WORKTREE_AGE_HOURS=bad
    cmd_cleanup
    log_size="$(python3 - "$LOG_FILE" <<'"'"'PY'"'"'
import os
import sys
print(os.path.getsize(sys.argv[1]))
PY
)"
    if (( log_size > 1024 * 1024 )); then
      echo "explicit cleanup should sanitize oversized supervisor log cap and rotate the log" >&2
      exit 1
    fi
    assert_missing "$2/projects/current-proj/.next"
    assert_missing "$2/projects/current-proj/app with spaces/.next"
    assert_exists "$2/projects/other-proj/.next"
    assert_exists "$2/projects/other-proj-worker"
  ' _ "$SCRIPT" "$TMPDIR"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
HOME="$TMPDIR/home" \
CODEX_SUPERVISOR_PROJECTS_ROOT=/ \
CODEX_SUPERVISOR_TMP_SWEEP_ROOT="$(printf '%05000d' 0 | tr 0 x)" \
CODEX_SUPERVISOR_SUPERPOWERS_WORKTREES_ROOT=relative/worktrees \
CODEX_SUPERVISOR_DIAGNOSTIC_MESSAGES_ROOT=relative/diagnostics \
  bash -c '
    set -euo pipefail
    source "$1"
    [[ "$PROJECTS_ROOT" == "$HOME/Desktop/projects" ]] || { echo "root projects path should fall back" >&2; exit 1; }
    [[ "$(CODEX_SUPERVISOR_PROJECTS_ROOT=relative/projects safe_root_env_path CODEX_SUPERVISOR_PROJECTS_ROOT "$HOME/Desktop/projects")" == "$HOME/Desktop/projects" ]] || { echo "relative projects root should fall back" >&2; exit 1; }
    [[ "$TMP_SWEEP_ROOT" == "/private/tmp" ]] || { echo "oversized tmp sweep root should fall back" >&2; exit 1; }
    [[ "$SUPERPOWERS_WORKTREES_ROOT" == "$HOME/.config/superpowers/worktrees" ]] || { echo "relative superpowers root should fall back" >&2; exit 1; }
    [[ "$DIAGNOSTIC_MESSAGES_ROOT" == "/private/var/log/DiagnosticMessages" ]] || { echo "relative diagnostics root should fall back" >&2; exit 1; }
  ' _ "$SCRIPT"
