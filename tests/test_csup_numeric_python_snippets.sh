#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"

python3 - "$CSUP" <<'PY'
import os
import pathlib
import re
import subprocess
import sys

text = pathlib.Path(sys.argv[1]).read_text()

assert "if not math.isfinite(timeout) or timeout <= 0:" in text, "timeout helpers must guard malformed numeric input"
assert "if not math.isfinite(sample_secs) or sample_secs < 0:" in text, "steward sample seconds must guard malformed numeric input"

match = re.search(r"slurm_remote_load_room\(\) \{.*?python3 - <<'PY'\n(.*?)\nPY", text, re.S)
assert match, "could not locate slurm remote load Python snippet"
snippet = match.group(1)

for raw in ["bad", "nan", "-1"]:
    env = {**os.environ, "CODEX_SUPERVISOR_MAX_LOAD_PER_CPU": raw}
    result = subprocess.run([sys.executable, "-c", snippet], env=env, text=True, capture_output=True, timeout=5)
    assert result.returncode == 0, (raw, result.returncode, result.stderr)
    assert result.stdout.strip().isdigit(), (raw, result.stdout, result.stderr)

unlimited = subprocess.run(
    [sys.executable, "-c", snippet],
    env={**os.environ, "CODEX_SUPERVISOR_MAX_LOAD_PER_CPU": "0"},
    text=True,
    capture_output=True,
    timeout=5,
)
assert unlimited.returncode == 0, unlimited.stderr
assert unlimited.stdout.strip() == "9999", unlimited.stdout

print("ok: csup embedded numeric Python snippets fail closed")
PY
