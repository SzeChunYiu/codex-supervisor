#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
TMPDIR="$(cd "$TMPDIR" && pwd -P)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/projects/current-proj" \
  "$TMPDIR/projects/current-project" \
  "$TMPDIR/projects/current-proj-worker"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_SESSION=current-proj \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
TEST_ROOT="$TMPDIR" \
  bash -c '
    set -euo pipefail
    source "$1"
    cd "$2/projects/current-proj"

    ps() {
      if [[ "$*" != "-o command= -p "* ]]; then
        command ps "$@"
        return
      fi
      case "${*: -1}" in
        101) printf "python %s/projects/current-project/worker.py\n" "$TEST_ROOT" ;;
        102) printf "python %s/projects/current-proj/worker.py\n" "$TEST_ROOT" ;;
        103) printf "python %s/projects/current-proj-worker/worker.py\n" "$TEST_ROOT" ;;
        *) return 1 ;;
      esac
    }

    if cleanup_process_in_project_scope 101; then
      echo "process cleanup scope should not match sibling project whose path only shares a prefix" >&2
      exit 1
    fi
    cleanup_process_in_project_scope 102 || {
      echo "process cleanup scope should match current project root" >&2
      exit 1
    }
    cleanup_process_in_project_scope 103 || {
      echo "process cleanup scope should match current project worktree suffix" >&2
      exit 1
    }
  ' _ "$SCRIPT" "$TMPDIR"

echo "ok: process cleanup scope uses path/token boundaries"
