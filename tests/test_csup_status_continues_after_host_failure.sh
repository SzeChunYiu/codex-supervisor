#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."first"]
ssh = "first-host"
supervisor = "/remote/codex-supervisor.sh"

[hosts."second"]
ssh = "second-host"
supervisor = "/remote/codex-supervisor.sh"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"

[hosts."first"]
project_dir = "/remote/proj"
prompts = "prompts-first.txt"
session = "proj-first"

[hosts."second"]
project_dir = "/remote/proj"
prompts = "prompts-second.txt"
session = "proj-second"
TOML

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
# Real ssh reads from stdin unless callers redirect it.  Simulate that here so
# csup status proves one host command cannot drain the host-list loop.
cat >/dev/null || true
case "$*" in
  *" true") exit 0 ;;
  *"first-host"*"status"*) echo "first exploded"; exit 42 ;;
  *"second-host"*"status"*) echo "second status ok"; exit 0 ;;
  *) exit 0 ;;
esac
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" status proj 2>&1
)"

[[ "$out" == *"[first] session=proj-first"* ]] || { printf 'missing first host header:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"(status command failed)"* ]] || { printf 'missing per-host failure marker:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"[second] session=proj-second"* ]] || { printf 'status aborted before second host:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"second status ok"* ]] || { printf 'missing second host status output:\n%s\n' "$out" >&2; exit 1; }

filtered="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" status proj --host=second 2>&1
)"

[[ "$filtered" != *"[first] session=proj-first"* ]] || { printf 'host filter included first host:\n%s\n' "$filtered" >&2; exit 1; }
[[ "$filtered" == *"[second] session=proj-second"* ]] || { printf 'host filter missed second host:\n%s\n' "$filtered" >&2; exit 1; }
[[ "$filtered" == *"second status ok"* ]] || { printf 'host filter missed second status:\n%s\n' "$filtered" >&2; exit 1; }

echo "ok: csup status continues after one host status command fails"
