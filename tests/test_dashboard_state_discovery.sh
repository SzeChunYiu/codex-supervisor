#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/Desktop/projects/example/docs"
cat > "$TMPDIR/home/.config-hosts.toml" <<'HOSTS'
[hosts."local-test"]
ssh = "local"
hostname_match = "test-host"
HOSTS
cat > "$TMPDIR/home/Desktop/projects/example/docs/prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane demo. Read docs/parallel-sessions.md and docs/parallel-sessions/demo.md, then complete one compact-safe iteration.
PROMPTS
cat > "$TMPDIR/home/.codex-supervisor-example-batch.state" <<STATE
PROMPTS_FILE=$TMPDIR/home/Desktop/projects/example/docs/prompts.txt
TASKS_DIR=
PROJECT_ROOT=$TMPDIR/home/Desktop/projects/example
STARTED_AT=2026-05-11 00:00:00
STATE
python3 - <<PY
from pathlib import Path
Path("$TMPDIR/home/.codex-supervisor-huge.state").write_text("PROJECT_ROOT=$TMPDIR/home/Desktop/projects/example\n" + ("#" * 1_000_001))
PY

python3 - "$DASHBOARD" "$TMPDIR/home" <<'PY'
import importlib.util
import importlib.machinery
import pathlib
import socket
import subprocess
import sys

dashboard_path = pathlib.Path(sys.argv[1])
home = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(dashboard_path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

mod.HOSTS_FILE = home / ".config-hosts.toml"
mod.PROJECT_SEARCH_DIRS = [home / "Desktop/projects"]
mod.EXTRA_PROJECT_ROOTS = []
mod.DIRECT_PROJECT_FALLBACKS = {}
mod.STATE_GLOB = home / ".codex-supervisor-*.state"
socket.gethostname = lambda: "test-host"

orig_run_stable = mod.run_stable
def fake_run_stable(cmd, *args, **kwargs):
    assert kwargs.get("timeout") == 2.0, kwargs
    assert kwargs.get("retries") == 0, kwargs
    if cmd[:2] == ["tmux", "ls"] or cmd[:4] == ["tmux", "-L", "default", "ls"]:
        return subprocess.CompletedProcess(cmd, 0, "example-batch\n", "")
    return orig_run_stable(cmd, *args, **kwargs)
mod.run_stable = fake_run_stable

# State discovery must not read an unbounded number of stale/corrupt state files.
for i in range(5):
    (home / f".codex-supervisor-overflow-{i}.state").write_text("BROKEN=1\n")
orig_read_state_file = mod.read_state_file
orig_max_state_files = mod.MAX_STATE_FILES
read_paths = []
def counting_read_state_file(path):
    read_paths.append(path)
    return {}
mod.read_state_file = counting_read_state_file
mod.MAX_STATE_FILES = 2
assert mod.state_instances() == [], read_paths
assert len(read_paths) == 2, read_paths
mod.read_state_file = orig_read_state_file
mod.MAX_STATE_FILES = orig_max_state_files

projects = mod.list_projects()
instances = [
    inst
    for project in projects
    for inst in mod.project_instances(project)
]
assert any(inst["session"] == "example-batch" for inst in instances), projects
assert not any(inst["session"] == "huge" for inst in instances), projects
state_inst = next(inst for inst in instances if inst["session"] == "example-batch")
assert state_inst["host"] == "local-test", state_inst
assert state_inst["prompts"].endswith("docs/prompts.txt"), state_inst
print("ok: dashboard discovers supervisor state files")
PY
