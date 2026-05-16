#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup"

for cmd in govern factory-audit steward; do
  if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
    "$CSUP" "$cmd" --project= >/tmp/csup-empty-project-"$cmd".out 2>/tmp/csup-empty-project-"$cmd".err; then
    echo "csup $cmd should reject an empty --project value" >&2
    exit 1
  fi
  if ! grep -q "$cmd: --project requires a name" /tmp/csup-empty-project-"$cmd".err; then
    echo "empty $cmd --project error should be explicit" >&2
    cat /tmp/csup-empty-project-"$cmd".err >&2
    exit 1
  fi
done

echo "ok: csup project-scoped commands reject empty project flags"
