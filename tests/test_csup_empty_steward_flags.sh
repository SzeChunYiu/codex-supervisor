#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup"

for flag in --sample-secs --dashboard-url; do
  if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
    "$CSUP" steward "$flag=" >/tmp/csup-empty-steward-"${flag#--}".out 2>/tmp/csup-empty-steward-"${flag#--}".err; then
    echo "csup steward should reject empty $flag" >&2
    exit 1
  fi
  if ! grep -q "steward: $flag requires a value" /tmp/csup-empty-steward-"${flag#--}".err; then
    echo "empty steward $flag error should be explicit" >&2
    cat /tmp/csup-empty-steward-"${flag#--}".err >&2
    exit 1
  fi
done

echo "ok: csup steward rejects empty value flags"
