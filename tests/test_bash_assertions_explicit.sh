#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

python3 - "$ROOT/tests" <<'PY'
import pathlib
import re
import sys

tests_dir = pathlib.Path(sys.argv[1])
violations: list[str] = []
bare_assertion = re.compile(r"^\s*\[\[")
allowed_control = re.compile(r"\]\]\s*(\|\||&&)")

for path in sorted(tests_dir.glob("test_*.sh")):
    if path.name == "test_bash_assertions_explicit.sh":
        continue
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        stripped = line.strip()
        if not bare_assertion.match(line):
            continue
        if allowed_control.search(line):
            continue
        if stripped.startswith("[[ ") and stripped.endswith(" ]]"):
            violations.append(f"{path.name}:{lineno}: {stripped}")

if violations:
    print("bare [[ ... ]] assertions do not fail bash tests reliably; use if/exit or || exit:", file=sys.stderr)
    for item in violations:
        print(f"  {item}", file=sys.stderr)
    raise SystemExit(1)

print("ok: bash tests use explicit exits for [[ assertions")
PY
