#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

protocol="$ROOT/docs/distributed-protocol.md"
shared="$ROOT/docs/parallel-sessions.md"
lane_template="$ROOT/docs/parallel-sessions/lane-template.md"
planner="$ROOT/docs/parallel-sessions/planner.md"
debugger="$ROOT/docs/parallel-sessions/debugger.md"
validator="$ROOT/docs/parallel-sessions/validator-planner.md"
dynamic="$ROOT/docs/parallel-sessions/dynamic-worker.md"
readme="$ROOT/README.md"
lunarc="$ROOT/docs/lunarc-setup.md"

require_text() {
  local file="$1" text="$2"
  if ! grep -Fq "$text" "$file"; then
    printf 'missing required distributed-protocol text in %s:\n  %s\n' "$file" "$text" >&2
    exit 1
  fi
}

[[ -s "$protocol" ]]

require_text "$protocol" "No anonymous source copies"
require_text "$protocol" "One writable lease per scope"
require_text "$protocol" "Git moves source; rsync moves artifacts"
require_text "$protocol" "TEAM_PLAN.md"
require_text "$protocol" "remote-executor"
require_text "$protocol" "read-only-verifier"
require_text "$protocol" "Fail closed on ambiguity"
require_text "$protocol" "DEBUG"
require_text "$protocol" "VALIDATOR"
require_text "$protocol" "codex-tasks/open.txt"

require_text "$shared" "docs/distributed-protocol.md"
require_text "$shared" "one writable lease per scope"
require_text "$shared" "Move source changes through Git"
require_text "$shared" "Dynamic workers"

require_text "$lane_template" "Host role"
require_text "$lane_template" "Source tree"
require_text "$lane_template" "remote-executor"

require_text "$planner" "docs/distributed-protocol.md"
require_text "$planner" "host assignment for each lane"
require_text "$planner" "source tree class for each lane"

require_text "$debugger" "The DEBUG lane is a fixed session"
require_text "$validator" "The VALIDATOR lane is a fixed session"
require_text "$dynamic" "Dynamic workers are the flexible worker pool"
require_text "$dynamic" "codex-tasks/open.txt"

require_text "$readme" "docs/distributed-protocol.md"
require_text "$readme" "one writable lease"
require_text "$readme" "CODEX_SUPERVISOR_DYNAMIC_WORKERS"

require_text "$lunarc" "execution mirror"
require_text "$lunarc" "sync_policy = \"git-only\""
