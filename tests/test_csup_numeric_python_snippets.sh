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
assert "allow_nan=False" in text, "JSON emitters must not serialize non-finite numeric tokens"

shell_capture_match = re.search(r"shell_capture_timeout\(\) \{.*?python3 - \"\$timeout\" \"\$cmd\" <<'PY'\n(.*?)\nPY", text, re.S)
assert shell_capture_match, "could not locate shell_capture_timeout Python snippet"
shell_capture_snippet = shell_capture_match.group(1)
small = subprocess.run(
    [sys.executable, "-c", shell_capture_snippet, "2", f"{sys.executable} -c 'print(42)'"] ,
    text=True, capture_output=True, timeout=5,
)
assert small.returncode == 0 and small.stdout.strip() == "42", (small.returncode, small.stdout, small.stderr)
huge_cmd = f"{sys.executable} -c 'import sys; sys.stdout.write(\"x\" * 4096)'"
huge = subprocess.run(
    [sys.executable, "-c", shell_capture_snippet, "2", huge_cmd],
    env={**os.environ, "CSUP_SHELL_CAPTURE_MAX_BYTES": "1024"},
    text=True, capture_output=True, timeout=5,
)
assert huge.returncode == 124 and huge.stdout == "", (huge.returncode, len(huge.stdout), huge.stderr)

capacity_match = re.search(r"capacity_fields\(\) \{.*?load_room=\$\(python3 - .*?<<'PY'\n(.*?)\nPY", text, re.S)
assert capacity_match, "could not locate local capacity load-room Python snippet"
capacity_snippet = capacity_match.group(1)
for args, expected in [
    (["4", "0", "0"], "999999"),
    (["4", "0", "nan"], "0"),
    (["4", "nan", "1.25"], "0"),
    (["bad", "0", "1.25"], "0"),
]:
    result = subprocess.run([sys.executable, "-c", capacity_snippet, *args], text=True, capture_output=True, timeout=5)
    assert result.returncode == 0, (args, result.returncode, result.stderr)
    assert result.stdout.strip() == expected, (args, result.stdout, result.stderr)

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
