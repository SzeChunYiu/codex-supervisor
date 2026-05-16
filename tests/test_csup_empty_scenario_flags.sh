#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup"

for cmd in factory-run staff; do
  if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
    "$CSUP" "$cmd" proj --scenario= >/tmp/csup-empty-scenario-"$cmd".out 2>/tmp/csup-empty-scenario-"$cmd".err; then
    echo "csup $cmd should reject empty --scenario values" >&2
    exit 1
  fi
  if ! grep -q "$cmd: --scenario requires a value" /tmp/csup-empty-scenario-"$cmd".err; then
    echo "empty $cmd --scenario error should be explicit" >&2
    cat /tmp/csup-empty-scenario-"$cmd".err >&2
    exit 1
  fi
done

echo "ok: csup factory/staff reject empty scenario flags"
