#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HOSTNAME_MATCH="$(uname -n)"
mkdir -p "$TMPDIR/home/Desktop/projects/proj-factory/codex-tasks" \
  "$TMPDIR/home/Desktop/projects/proj-factory/docs/parallel-sessions" \
  "$TMPDIR/home/Desktop/projects/proj-missing/codex-tasks" \
  "$TMPDIR/home/.config/csup"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<HOSTS
[hosts."mac-mini"]
ssh = "local"
hostname_match = "$HOSTNAME_MATCH"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj-factory/.codex-supervisor.toml" <<'TOML'
schema_version = 1

[project]
name = "proj-factory"

[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-factory-main"
TOML

cat > "$TMPDIR/home/Desktop/projects/proj-factory/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane worker. Read docs/parallel-sessions.md and docs/parallel-sessions/worker.md, then complete one compact-safe iteration.
PROMPTS

cat > "$TMPDIR/home/Desktop/projects/proj-factory/docs/parallel-sessions.md" <<'DOC'
# Shared protocol

> **AI factory override:** read docs/parallel-sessions/AI_FACTORY.md first.
DOC
cat > "$TMPDIR/home/Desktop/projects/proj-factory/docs/parallel-sessions/AI_FACTORY.md" <<'DOC'
# AI Factory System
DOC
cat > "$TMPDIR/home/Desktop/projects/proj-factory/docs/parallel-sessions/TEAM_PLAN.md" <<'DOC'
# Team Plan

## AI Factory acceptance board
DOC
cat > "$TMPDIR/home/Desktop/projects/proj-factory/docs/blocker-schema.md" <<'DOC'
# Factory blocker schema

type=code|data|approval|infra|empirical|external
DOC
cat > "$TMPDIR/home/Desktop/projects/proj-factory/codex-tasks/blockers.txt" <<'TASKS'
/goal unblock shared acceptance gate
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-factory/codex-tasks/open.txt" <<'TASKS'
/goal normal open work
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-factory/codex-tasks/special.txt" <<'TASKS'
/goal specialized lane work
TASKS

audit="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  "$CSUP" factory-audit --project=proj-factory
)"

if [[ "$audit" != *"FACTORY proj-factory/mac-mini status=RED blockers=1 open=1 lane=1 prompts=1"* ]]; then
  printf 'factory-audit should report blocker-led RED status and queue counts, got:\n%s\n' "$audit" >&2
  exit 1
fi
if [[ "$audit" != *"docs=ok"* ]]; then
  printf 'factory-audit should accept complete factory docs, got:\n%s\n' "$audit" >&2
  exit 1
fi
if [[ "$audit" != *"ACTION proj-factory/mac-mini: resolve shared blockers before lane-local work"* ]]; then
  printf 'factory-audit should print blocker-first action, got:\n%s\n' "$audit" >&2
  exit 1
fi

cat > "$TMPDIR/home/Desktop/projects/proj-missing/.codex-supervisor.toml" <<'TOML'
schema_version = 1

[project]
name = "proj-missing"

[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-missing-main"
TOML
cat > "$TMPDIR/home/Desktop/projects/proj-missing/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane worker. Read docs/parallel-sessions.md and docs/parallel-sessions/worker.md, then complete one compact-safe iteration.
PROMPTS

missing="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  "$CSUP" factory-audit --project=proj-missing
)"

if [[ "$missing" != *"FACTORY proj-missing/mac-mini status=RED blockers=0 open=0 lane=0 prompts=1"* ]]; then
  printf 'factory-audit should report missing-doc RED status, got:\n%s\n' "$missing" >&2
  exit 1
fi
if [[ "$missing" != *"docs=missing:shared,ai_factory,team_plan,blocker_schema"* ]]; then
  printf 'factory-audit should list missing factory docs, got:\n%s\n' "$missing" >&2
  exit 1
fi
