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

python3 - "$DASHBOARD" "$TMPDIR/home" <<'PY'
import importlib.util
import importlib.machinery
import pathlib
import socket
import subprocess
import sys
from types import SimpleNamespace

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

real_run = subprocess.run
def fake_run(cmd, *args, **kwargs):
    if cmd[:2] == ["tmux", "ls"] or cmd[:4] == ["tmux", "-L", "default", "ls"]:
        return SimpleNamespace(returncode=0, stdout="example-batch\n", stderr="")
    return real_run(cmd, *args, **kwargs)
subprocess.run = fake_run

projects = mod.list_projects()
instances = [
    inst
    for project in projects
    for inst in mod.project_instances(project)
]
assert any(inst["session"] == "example-batch" for inst in instances), projects
state_inst = next(inst for inst in instances if inst["session"] == "example-batch")
assert state_inst["host"] == "local-test", state_inst
assert state_inst["prompts"].endswith("docs/prompts.txt"), state_inst
print("ok: dashboard discovers supervisor state files")
PY
