#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/projects/app"
cat > "$TMPDIR/projects/app/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "app"
TOML

cat > "$TMPDIR/bin/ps" <<'PS'
#!/usr/bin/env bash
if [[ "$*" == "-o command= -p 101" ]]; then
  printf '%s\n' "/usr/bin/node /tmp/happy-place/node_modules/.bin/next dev"
elif [[ "$*" == "-o command= -p 102" ]]; then
  printf '%s\n' "/usr/bin/node /tmp/app-worker/node_modules/.bin/next dev"
elif [[ "$*" == "-o command= -p 103" ]]; then
  printf '%s\n' "/usr/bin/node $FAKE_PROJECT_ROOT/web/node_modules/.bin/next dev"
else
  exit 1
fi
PS
chmod +x "$TMPDIR/bin/ps"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_SUPERVISOR_SESSION=app \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
CODEX_SUPERVISOR_LOG="$TMPDIR/supervisor.log" \
FAKE_PROJECT_ROOT="$TMPDIR/projects/app" \
PATH="$TMPDIR/bin:$PATH" \
  bash -c '
    set -euo pipefail
    source "$1"
    cd "$2/projects/app"

    if cleanup_process_in_project_scope 101; then
      echo "process cleanup scope should not match arbitrary substrings like happy-place for scope app" >&2
      exit 1
    fi
    cleanup_process_in_project_scope 102 || {
      echo "process cleanup scope should match project-prefixed worker paths" >&2
      exit 1
    }
    cleanup_process_in_project_scope 103 || {
      echo "process cleanup scope should match commands under the current project root" >&2
      exit 1
    }
    CODEX_SUPERVISOR_GLOBAL_CLEANUP=1 cleanup_process_in_project_scope 101 || {
      echo "global cleanup should permit matching any orphan cleanup process" >&2
      exit 1
    }
  ' _ "$SCRIPT" "$TMPDIR"

echo "ok: process cleanup scope avoids substring false positives"
