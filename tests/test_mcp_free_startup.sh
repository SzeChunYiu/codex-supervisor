#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

REAL_CODEX_HOME="$TMPDIR/real-codex"
SUP_CODEX_HOME="$TMPDIR/supervisor-codex"
mkdir -p "$REAL_CODEX_HOME"

cat > "$REAL_CODEX_HOME/config.toml" <<'CONFIG'
model = "gpt-5.5"

[features]
goals = true

[mcp_servers.filesystem]
command = "npx"
args = ["-y", "filesystem-mcp"]

[mcp_servers.github.env]
GITHUB_TOKEN = "secret"

[projects."/tmp/example"]
trust_level = "trusted"
CONFIG
printf '{"token":"redacted"}\n' > "$REAL_CODEX_HOME/auth.json"
printf '{"credential":"redacted"}\n' > "$REAL_CODEX_HOME/.credentials.json"
mkdir -p "$REAL_CODEX_HOME/skills/example" "$REAL_CODEX_HOME/memories" "$REAL_CODEX_HOME/plugins"
printf 'skill payload\n' > "$REAL_CODEX_HOME/skills/example/SKILL.md"
printf 'memory payload\n' > "$REAL_CODEX_HOME/memories/MEMORY.md"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_HOME="$REAL_CODEX_HOME" \
CODEX_SUPERVISOR_CODEX_HOME="$SUP_CODEX_HOME" \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
  bash -c 'cd "$2"; source "$1"; prepare_codex_home; build_codex_command' \
  _ "$SCRIPT" "$ROOT" > "$TMPDIR/cmd.out"

cmd="$(cat "$TMPDIR/cmd.out")"
if [[ "$cmd" != *"CODEX_HOME="*"$SUP_CODEX_HOME"* ]]; then
  printf 'default startup command should use supervisor MCP-free CODEX_HOME, got: %s\n' "$cmd" >&2
  exit 1
fi

if grep -q 'mcp_servers' "$SUP_CODEX_HOME/config.toml"; then
  echo "MCP sections should be stripped from supervisor config" >&2
  cat "$SUP_CODEX_HOME/config.toml" >&2
  exit 1
fi

grep -q 'model = "gpt-5.5"' "$SUP_CODEX_HOME/config.toml"
grep -q '\[features\]' "$SUP_CODEX_HOME/config.toml"
grep -q '\[projects."/tmp/example"\]' "$SUP_CODEX_HOME/config.toml"
grep -Fq "[projects.\"$ROOT\"]" "$SUP_CODEX_HOME/config.toml"
python3 - "$SCRIPT" <<'PY'
import pathlib
import re
import sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'trust_project_in_codex_config\(\) \{.*?python3 - "\$cfg" "\$project_dir" <<\'PY\'\n(.*?)\nPY', text, re.S)
assert match, "trust_project_in_codex_config Python snippet missing"
snippet = match.group(1)
assert "read_text" not in snippet, "codex config trust edit must use bounded binary reads"
assert "read(max_cfg_bytes + 1)" in snippet
PY
awk -v header="[projects.\"$ROOT\"]" '
  $0 == header { in_section=1; next }
  in_section && /^\[/ { exit 1 }
  in_section && $0 == "trust_level = \"trusted\"" { found=1; exit 0 }
  END { exit found ? 0 : 1 }
' "$SUP_CODEX_HOME/config.toml"
test -e "$SUP_CODEX_HOME/auth.json"
test -e "$SUP_CODEX_HOME/.credentials.json"
if [[ -e "$SUP_CODEX_HOME/skills" || -e "$SUP_CODEX_HOME/memories" || -e "$SUP_CODEX_HOME/plugins" ]]; then
  echo "default lean supervisor CODEX_HOME should omit skills/memories/plugins for high-density workers" >&2
  find "$SUP_CODEX_HOME" -maxdepth 1 -mindepth 1 -print >&2
  exit 1
fi
if [[ "$cmd" != *"nice -n 5"* ]]; then
  printf 'default startup command should lower worker CPU priority with nice -n 5, got: %s\n' "$cmd" >&2
  exit 1
fi
if [[ "$cmd" != *"--dangerously-bypass-approvals-and-sandbox"* ]]; then
  printf 'default startup command should launch codex with dangerous bypass permissions, got: %s\n' "$cmd" >&2
  exit 1
fi
for expected in \
  "XDG_CACHE_HOME='$TMPDIR/supervisor-root/cache/codex-supervisor/xdg'" \
  "npm_config_cache='$TMPDIR/supervisor-root/cache/codex-supervisor/npm'" \
  "UV_CACHE_DIR='$TMPDIR/supervisor-root/cache/codex-supervisor/uv'" \
  "PIP_CACHE_DIR='$TMPDIR/supervisor-root/cache/codex-supervisor/pip'" \
  "TMPDIR='$TMPDIR/supervisor-root/tmp/codex-supervisor'"
do
  if [[ "$cmd" != *"$expected"* ]]; then
    printf 'default startup command should redirect worker cache env %s, got: %s\n' "$expected" "$cmd" >&2
    exit 1
  fi
done

FULL_SUP_CODEX_HOME="$TMPDIR/full-supervisor-codex"
CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_HOME="$REAL_CODEX_HOME" \
CODEX_SUPERVISOR_CODEX_HOME="$FULL_SUP_CODEX_HOME" \
CODEX_SUPERVISOR_CODEX_HOME_PROFILE=full \
  bash -c 'source "$1"; prepare_codex_home' \
  _ "$SCRIPT"
test -e "$FULL_SUP_CODEX_HOME/skills"
test -e "$FULL_SUP_CODEX_HOME/memories"
test -e "$FULL_SUP_CODEX_HOME/plugins"

CODEX_SUPERVISOR_TEST_SOURCE=1 \
CODEX_HOME="$REAL_CODEX_HOME" \
CODEX_SUPERVISOR_MCP_MODE=inherit \
CODEX_SUPERVISOR_CODEX_HOME="$TMPDIR/unused-home" \
  bash -c 'source "$1"; prepare_codex_home; build_codex_command' \
  _ "$SCRIPT" > "$TMPDIR/inherit-cmd.out"

inherit_cmd="$(cat "$TMPDIR/inherit-cmd.out")"
if [[ "$inherit_cmd" == *"CODEX_HOME="* ]]; then
  printf 'inherit mode should not override CODEX_HOME, got: %s\n' "$inherit_cmd" >&2
  exit 1
fi

if CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_HOME="$REAL_CODEX_HOME" \
  CODEX_SUPERVISOR_CODEX_HOME="$REAL_CODEX_HOME" \
  bash -c 'source "$1"; prepare_codex_home' _ "$SCRIPT" \
  >/tmp/codex-supervisor-same-home.out 2>/tmp/codex-supervisor-same-home.err; then
  echo "prepare_codex_home should refuse to rewrite the source CODEX_HOME" >&2
  exit 1
fi
grep -q "must differ" /tmp/codex-supervisor-same-home.err

CODEX_SUPERVISOR_TEST_SOURCE=1 \
HOME="$TMPDIR/home" \
CODEX_SUPERVISOR_ROOT="$TMPDIR/supervisor-root" \
  bash -c 'source "$1"; SESSION="custom-session"; refresh_session_paths; [[ "$SUPERVISOR_CODEX_HOME" == "$CODEX_SUPERVISOR_ROOT/codex-home/custom-session" ]] && [[ "$SUPERVISOR_CACHE_ROOT" == "$CODEX_SUPERVISOR_ROOT/cache/custom-session" ]] && [[ "$SUPERVISOR_TMP_ROOT" == "$CODEX_SUPERVISOR_ROOT/tmp/custom-session" ]] && [[ "$LOG_FILE" == "$CODEX_SUPERVISOR_ROOT/logs/custom-session.log" ]] && [[ "$STATE_FILE" == "$CODEX_SUPERVISOR_ROOT/run/custom-session.state" ]]' \
  _ "$SCRIPT"

OVERSIZED_CODEX_HOME="$TMPDIR/oversized-codex"
OVERSIZED_SUP_HOME="$TMPDIR/oversized-supervisor-codex"
mkdir -p "$OVERSIZED_CODEX_HOME"
python3 - <<PY
from pathlib import Path
Path("$OVERSIZED_CODEX_HOME/config.toml").write_text("model = \"gpt-5.5\"\n" + "x" * 2_000_001)
PY
if CODEX_SUPERVISOR_TEST_SOURCE=1 \
  CODEX_HOME="$OVERSIZED_CODEX_HOME" \
  CODEX_SUPERVISOR_CODEX_HOME="$OVERSIZED_SUP_HOME" \
  CODEX_SUPERVISOR_ROOT="$TMPDIR/oversized-supervisor-root" \
  bash -c 'cd "$2"; source "$1"; prepare_codex_home' _ "$SCRIPT" "$ROOT" >/tmp/csup-oversized-config.out 2>&1; then
  echo "oversized copied config should fail closed instead of being edited or clobbered" >&2
  exit 1
fi
grep -q 'refusing to copy oversized codex config' /tmp/csup-oversized-config.out || {
  echo "missing oversized source config copy refusal" >&2
  cat /tmp/csup-oversized-config.out >&2
  exit 1
}
if [[ -s "$OVERSIZED_SUP_HOME/config.toml" ]]; then
  echo "oversized source config should not be copied into supervisor CODEX_HOME" >&2
  ls -l "$OVERSIZED_SUP_HOME/config.toml" >&2
  exit 1
fi

echo "ok: each pane gets an isolated Codex home/state runtime"
