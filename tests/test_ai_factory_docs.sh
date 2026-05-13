#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

grep -q "AI factory" "$ROOT/docs/ai-factory.md"
grep -q "Batch outcome" "$ROOT/templates/TEAM_PLAN.md"
grep -q "Acceptance checklist" "$ROOT/templates/TEAM_PLAN.md"
grep -q "codex-tasks/blockers.txt" "$ROOT/docs/ai-factory.md"
grep -q "csup factory-audit" "$ROOT/docs/ai-factory.md"
grep -q "docs/blocker-schema.md" "$ROOT/docs/ai-factory.md"
grep -q "docs/blocker-schema.md" "$ROOT/docs/system-governor.md"
grep -q "type=code|data|approval|infra|empirical|external" "$ROOT/docs/blocker-schema.md"
grep -q "docs/ai-factory.md" "$ROOT/docs/parallel-sessions.md"
grep -q "templates/TEAM_PLAN.md" "$ROOT/docs/parallel-sessions/validator-planner.md"
grep -q "codex-tasks/blockers.txt" "$ROOT/docs/parallel-sessions/validator-planner.md"
grep -q "TEAM_PLAN.md" "$ROOT/docs/parallel-sessions/dynamic-worker.md"
grep -q "codex-tasks/blockers.txt" "$ROOT/templates/TEAM_PLAN.md"
