#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DOC="$ROOT/docs/atomic-productivity.md"
[[ -f "$DOC" ]] || { echo "missing atomic productivity doc" >&2; exit 1; }
for phrase in \
  "real development, not more audits" \
  "one atomic product slice" \
  "ship one verified product atom" \
  "Do not run full test/build suites by default" \
  "one heavy process per pane" \
  "UV_THREADPOOL_SIZE=2" \
  "Managers maintain the atom list" \
  "stops or reassigns that pane"; do
  if ! grep -Fq "$phrase" "$DOC"; then
    echo "atomic productivity doc missing phrase: $phrase" >&2
    exit 1
  fi
done
if ! grep -Fq "atomic-productivity.md" "$ROOT/docs/productivity-contract.md"; then
  echo "productivity contract should link atomic productivity protocol" >&2
  exit 1
fi
echo "ok: atomic productivity protocol covers implementation-first prompt and resource rules"
