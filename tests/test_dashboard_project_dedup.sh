#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/real/neural_grow" "$TMPDIR/search-a" "$TMPDIR/search-b"
cat > "$TMPDIR/real/neural_grow/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "neural_grow"
[hosts."local"]
ssh = "local"
session = "neural-local"
TOML
ln -s "$TMPDIR/real/neural_grow" "$TMPDIR/search-a/neural_grow"
ln -s "$TMPDIR/real/neural_grow" "$TMPDIR/search-b/neural_grow"

python3 - "$DASHBOARD" "$TMPDIR/search-a" "$TMPDIR/search-b" "$TMPDIR/real/neural_grow" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys

dashboard_path = pathlib.Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

mod.PROJECT_SEARCH_DIRS = [pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])]
mod.EXTRA_PROJECT_ROOTS = [pathlib.Path(sys.argv[4])]
mod.DIRECT_PROJECT_FALLBACKS = {}
mod.state_instances = lambda: []

projects = mod.list_projects()
names = [p["name"] for p in projects]
assert names == ["neural_grow"], projects
print("ok: dashboard de-duplicates project roots discovered through symlinks/search paths")
PY
