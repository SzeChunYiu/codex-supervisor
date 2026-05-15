#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/proj/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<'HOSTS'
[hosts."lunarc-login"]
ssh = "lunarc"
supervisor = "/shared/codex-supervisor.sh"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"
[hosts."lunarc-login"]
project_dir = "/remote/proj"
prompts = "prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-lunarc"
TOML

cat > "$TMPDIR/bin/ssh" <<'SSH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_SSH_LOG"
echo remote-ok
SSH
chmod +x "$TMPDIR/bin/ssh"
export FAKE_SSH_LOG="$TMPDIR/ssh.log"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" start proj --host=lunarc-login 2>&1
)"

[[ "$out" == *"refusing to start on the login node"* ]] || {
  printf 'expected login-node refusal, got:\n%s\n' "$out" >&2
  exit 1
}
if [[ -s "$TMPDIR/ssh.log" ]] && grep -q "/shared/codex-supervisor.sh.*start" "$TMPDIR/ssh.log"; then
  printf 'must not start supervisor through SSH on LUNARC login node, log:\n' >&2
  cat "$TMPDIR/ssh.log" >&2
  exit 1
fi

echo "ok: csup refuses non-SLURM LUNARC starts on the login node"
