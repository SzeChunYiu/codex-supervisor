#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

python3 - "$DASHBOARD" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_ansi_resilience", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_ansi_resilience", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

assert mod.ansi_to_html("\x1b[31mred\x1b[0m") == '<span style="color:#ff7b72">red</span>'
assert mod.ansi_to_html("\x1b[" + ("9" * 10000) + "mplain") == "plain"
assert mod.ansi_to_html("\x1b[38;2;999999999999999999999999;0;0mplain") == "plain"
assert mod.ansi_to_html("\x1b[38;2;255;0;0mred") == '<span style="color:#ff0000">red</span>'

print("ok: dashboard ANSI SGR parsing ignores hostile long numeric params")
PY
