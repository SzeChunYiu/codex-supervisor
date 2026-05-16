#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/.config/csup"

if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  "$CSUP" start proj --host= >/tmp/csup-empty-host-start.out 2>/tmp/csup-empty-host-start.err; then
  echo "csup start should reject an empty --host value" >&2
  exit 1
fi
if ! grep -q "start: --host requires a name" /tmp/csup-empty-host-start.err; then
  echo "empty start --host error should be explicit" >&2
  cat /tmp/csup-empty-host-start.err >&2
  exit 1
fi

if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  "$CSUP" stop proj --host= >/tmp/csup-empty-host-stop.out 2>/tmp/csup-empty-host-stop.err; then
  echo "csup stop should reject an empty --host value" >&2
  exit 1
fi
if ! grep -q "stop: --host requires a name" /tmp/csup-empty-host-stop.err; then
  echo "empty stop --host error should be explicit" >&2
  cat /tmp/csup-empty-host-stop.err >&2
  exit 1
fi

if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  "$CSUP" stop proj --bogus >/tmp/csup-stop-bogus.out 2>/tmp/csup-stop-bogus.err; then
  echo "csup stop should reject unknown flags instead of treating them as a project" >&2
  exit 1
fi
if ! grep -q "unknown flag: --bogus" /tmp/csup-stop-bogus.err; then
  echo "unknown stop flag error should be explicit" >&2
  cat /tmp/csup-stop-bogus.err >&2
  exit 1
fi

for cmd in submit govern factory-run gm-start staff station status; do
  if HOME="$TMPDIR/home" CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
    "$CSUP" "$cmd" --host= >/tmp/csup-empty-host-"$cmd".out 2>/tmp/csup-empty-host-"$cmd".err; then
    echo "csup $cmd should reject an empty --host value" >&2
    exit 1
  fi
  if ! grep -q "$cmd: --host requires a name" /tmp/csup-empty-host-"$cmd".err; then
    echo "empty $cmd --host error should be explicit" >&2
    cat /tmp/csup-empty-host-"$cmd".err >&2
    exit 1
  fi
done

echo "ok: csup commands reject empty host values and unknown stop flags"
