#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj" "$TMPDIR/home/.config/csup"
cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts."local"]
ssh = "local"
session = "proj-local"
TOML
cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."local"]
ssh = "local"
HOSTS

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_PROJECT_ROOTS_FILE="$TMPDIR/home/.config/csup/project-roots.txt" \
"$CSUP" ls > "$TMPDIR/out.txt"

expected="$(cd "$TMPDIR/home/Desktop/projects/proj" && pwd -P)"
count="$(grep -Fx "$expected" "$TMPDIR/home/.config/csup/project-roots.txt" | wc -l | tr -d ' ')"
[[ "$count" == "1" ]] || {
  echo "expected csup ls to register project root exactly once" >&2
  cat "$TMPDIR/home/.config/csup/project-roots.txt" >&2 || true
  exit 1
}

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_PROJECT_ROOTS_FILE="$TMPDIR/home/.config/csup/project-roots.txt" \
"$CSUP" ls > "$TMPDIR/out2.txt"
count="$(grep -Fx "$expected" "$TMPDIR/home/.config/csup/project-roots.txt" | wc -l | tr -d ' ')"
[[ "$count" == "1" ]] || {
  echo "project root registry should remain de-duplicated" >&2
  cat "$TMPDIR/home/.config/csup/project-roots.txt" >&2 || true
  exit 1
}

echo "ok: csup records discovered project roots for dashboard fallback"
