#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
TMPDIR="$(cd "$TMPDIR" && pwd -P)"
trap 'rm -rf "$TMPDIR"' EXIT

# Keep local execution paths argument-safe. Remote command strings still cross an
# SSH shell boundary, but local status, direct SSH, and LUNARC-compute SLURM paths must not
# re-enter the shell through eval.
if grep -Eq 'eval "\$(sbatch_cmd|run_cmd)"|cd "\$d" && eval|eval "\$\(ssh_cmd_prefix' "$CSUP"; then
  grep -En 'eval "\$(sbatch_cmd|run_cmd)"|cd "\$d" && eval|eval "\$\(ssh_cmd_prefix' "$CSUP" >&2 || true
  printf 'local csup execution paths must avoid eval\n' >&2
  exit 1
fi

mkdir -p "$TMPDIR/home/Desktop/projects/proj" "$TMPDIR/home/.config/csup" "$TMPDIR/super visor"
me="$(uname -n)"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<HOSTS
[hosts."local-safe"]
ssh = "local"
hostname_match = "$me"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj"

[hosts."local-safe"]
prompts = "prompts with spaces.txt"
session = "proj session"
role = "manager"
TOML

cat > "$TMPDIR/super visor/codex supervisor.sh" <<'SH'
#!/usr/bin/env bash
printf 'session=%s\n' "${CODEX_SUPERVISOR_SESSION:-}"
printf 'prompts=%s\n' "${CODEX_SUPERVISOR_PROMPTS:-}"
printf 'ceo=%s manager=%s reviewer=%s debugger=%s validator=%s\n' \
  "${CODEX_SUPERVISOR_CEO:-}" \
  "${CODEX_SUPERVISOR_MANAGER:-}" \
  "${CODEX_SUPERVISOR_REVIEWER:-}" \
  "${CODEX_SUPERVISOR_DEBUGGER:-}" \
  "${CODEX_SUPERVISOR_VALIDATOR:-}"
printf 'args=%s\n' "$*"
SH
chmod +x "$TMPDIR/super visor/codex supervisor.sh"

out="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/super visor/codex supervisor.sh" \
  "$CSUP" status proj 2>&1
)"

[[ "$out" == *"[local-safe] session=proj session"* ]] || { printf 'missing local-safe header:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"session=proj session"* ]] || { printf 'session was not passed literally:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"prompts=$TMPDIR/home/Desktop/projects/proj/prompts with spaces.txt"* ]] || { printf 'prompts path was not passed literally:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"ceo=0 manager=1 reviewer=0 debugger=0 validator=0"* ]] || { printf 'manager role env was not preserved:\n%s\n' "$out" >&2; exit 1; }
[[ "$out" == *"args=status"* ]] || { printf 'supervisor status arg missing:\n%s\n' "$out" >&2; exit 1; }

echo "ok: csup local status, SSH, and compute-node paths avoid eval"
