#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPBASE="$(mktemp -d)"
trap 'rm -rf "$TMPBASE"' EXIT

mkdir -p "$TMPBASE/home/Desktop/projects/proj" "$TMPBASE/home/.config/csup" "$TMPBASE/alt-tmp"

cat > "$TMPBASE/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts."local-test"]
ssh = "local"
TOML

cat > "$TMPBASE/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."local-test"]
ssh = "local"
hostname_match = "not-this-host"
description = "local test"
HOSTS

out="$(
  HOME="$TMPBASE/home" \
  CSUP_HOSTS_FILE="$TMPBASE/home/.config/csup/hosts.toml" \
  TMPDIR="$TMPBASE/missing-tmp" \
  CSUP_TMPDIR_FALLBACK="$TMPBASE/alt-tmp" \
  CSUP_MIN_TMP_KB=1 \
  "$CSUP" ls
)"

[[ "$out" == *"proj"* ]] || {
  printf 'expected csup to keep Python-backed TOML parsing working with fallback TMPDIR, got:\n%s\n' "$out" >&2
  exit 1
}

bad_min_out="$(
  HOME="$TMPBASE/home" \
  CSUP_HOSTS_FILE="$TMPBASE/home/.config/csup/hosts.toml" \
  TMPDIR="$TMPBASE/alt-tmp" \
  CSUP_MIN_TMP_KB=bad \
  "$CSUP" ls
)"

[[ "$bad_min_out" == *"proj"* ]] || {
  printf 'expected csup to ignore invalid CSUP_MIN_TMP_KB instead of tripping arithmetic, got:\n%s\n' "$bad_min_out" >&2
  exit 1
}

echo "ok: csup selects a writable TMPDIR fallback before Python-backed parsing"
