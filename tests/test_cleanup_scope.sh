#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/projects/current-proj" "$TMPDIR/projects/current-proj-worker" "$TMPDIR/projects/other-proj-worker"
mkdir -p \
  "$TMPDIR/private-tmp/current-proj-temp" \
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

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_SESSION=current-proj \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
CODEX_SUPERVISOR_PROJECTS_ROOT="$TMPDIR/projects" \
CODEX_SUPERVISOR_TMP_SWEEP_ROOT="$TMPDIR/private-tmp" \
CODEX_SUPERVISOR_SUPERPOWERS_WORKTREES_ROOT="$TMPDIR/superpowers/worktrees" \
CODEX_SUPERVISOR_MYDRIVE_SUPERPOWERS_WORKTREES_ROOT="$TMPDIR/mydrive/worktrees" \
CODEX_SUPERVISOR_ACTIONS_RUNNER_WORK_ROOT="$TMPDIR/actions-runner-work" \
CODEX_SUPERVISOR_CODEX_LOG_MAX_GB=0 \
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

    cleanup_path_in_project_scope "$2/projects/current-proj-worker" || exit 1
    if cleanup_path_in_project_scope "$2/projects/other-proj-worker"; then
      echo "project cleanup scope should not match sibling project worker" >&2
      exit 1
    fi

    CODEX_SUPERVISOR_GLOBAL_CLEANUP=1 cleanup_path_in_project_scope "$2/projects/other-proj-worker"

    CODEX_SUPERVISOR_GLOBAL_CLEANUP=0
    GLOBAL_CLEANUP=0
    PERIODIC_WORKTREE_AGE_MIN=0
    run_periodic_cleanup

    assert_missing "$2/private-tmp/current-proj-temp"
    assert_exists "$2/private-tmp/other-proj-temp"
    assert_missing "$2/superpowers/worktrees/current-proj/old-worker"
    assert_exists "$2/superpowers/worktrees/other-proj/old-worker"
    assert_missing "$2/projects/current-proj-worker"
    assert_exists "$2/projects/other-proj-worker"

    PRUNE_WORKTREE_AGE_HOURS=-1
    cmd_cleanup
    assert_missing "$2/projects/current-proj/.next"
    assert_missing "$2/projects/current-proj/app with spaces/.next"
    assert_exists "$2/projects/other-proj/.next"
    assert_exists "$2/projects/other-proj-worker"
  ' _ "$SCRIPT" "$TMPDIR"
