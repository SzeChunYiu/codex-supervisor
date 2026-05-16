#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup"

check_empty_flag() {
  local cmd="$1" flag="$2"
  shift 2
  if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
    "$CSUP" "$cmd" "$@" "$flag=" >/tmp/csup-empty-"$cmd"-"${flag#--}".out 2>/tmp/csup-empty-"$cmd"-"${flag#--}".err; then
    echo "csup $cmd should reject empty $flag" >&2
    exit 1
  fi
  if ! grep -q "$cmd: $flag requires a value" /tmp/csup-empty-"$cmd"-"${flag#--}".err; then
    echo "empty $cmd $flag error should be explicit" >&2
    cat /tmp/csup-empty-"$cmd"-"${flag#--}".err >&2
    exit 1
  fi
}

check_empty_flag govern --max-panes

for flag in --sessions --workers --max-workers --max-panes; do
  check_empty_flag factory-run "$flag" proj
  check_empty_flag staff "$flag" proj
done

check_empty_flag station --sessions proj
check_empty_flag station --workers proj

echo "ok: csup numeric override flags reject empty values"
