#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/hidden/project-a" "$TMPDIR/home/.config/csup"
cat > "$TMPDIR/hidden/project-a/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "project-a"
[hosts."local"]
ssh = "local"
session = "project-a"
prompts = "prompts.txt"
TOML
printf '%s\n' "$TMPDIR/hidden/project-a" > "$TMPDIR/home/.config/csup/project-roots.txt"

python3 - "$DASHBOARD" "$TMPDIR/home" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import socket
import sys

path = pathlib.Path(sys.argv[1])
home = pathlib.Path(sys.argv[2])
loader = importlib.machinery.SourceFileLoader("csup_dashboard_under_test", str(path))
spec = importlib.util.spec_from_loader("csup_dashboard_under_test", loader)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(mod)

mod.HOSTS_FILE = home / ".config/csup/hosts.toml"
mod.PROJECT_ROOTS_FILE = home / ".config/csup/project-roots.txt"
mod.PROJECT_CACHE_FILE = home / ".config/csup/missing-cache.json"
mod.PROJECT_SEARCH_DIRS = [home / "Desktop/projects-does-not-exist"]
mod.EXTRA_PROJECT_ROOTS = []
mod.STATE_GLOB = home / ".codex-supervisor-*.state"
socket.gethostname = lambda: "local"
projects = mod.list_projects()
assert [(p["name"], pathlib.Path(p["path"]).name) for p in projects] == [("project-a", "project-a")], projects

# If direct project config access is unavailable too, the cache still carries
# the backstage host structure from a prior trusted csup discovery pass.
mod.PROJECT_ROOTS_FILE = home / ".config/csup/missing-roots.txt"
mod.PROJECT_CACHE_FILE = home / ".config/csup/project-cache.json"
mod.PROJECT_CACHE_FILE.write_text(__import__("json").dumps([{
    "path": str(home / "Desktop/proj-cache"),
    "config": {"project": {"name": "cached-proj"}, "hosts": {"local": {"ssh": "local", "session": "cached"}}},
}]))
projects = mod.list_projects()
assert any(p["name"] == "cached-proj" and p["hosts"].get("local", {}).get("session") == "cached" for p in projects), projects
mod.PROJECT_ROOTS_FILE = home / ".config/csup/oversized-roots.txt"
mod.PROJECT_ROOTS_FILE.write_text("#" * 1_000_001)
mod.PROJECT_CACHE_FILE = home / ".config/csup/oversized-cache.json"
mod.PROJECT_CACHE_FILE.write_text("[" + (" " * 2_000_001) + "]")
projects = mod.list_projects()
assert projects == [], projects

mod.PROJECT_ROOTS_FILE = home / ".config/csup/missing-roots.txt"
mod.PROJECT_CACHE_FILE = home / ".config/csup/project-cache.json"
hosts = {
    "lunarc": {
        "ssh": "lunarc",
        "scheduler": "slurm",
        "slurm_job_name": "mcaccel-sup",
        "remote_env": "source /shared/env.sh",
    }
}
projects = [{
    "name": "cached-lunarc-proj",
    "path": str(home / "Desktop/cached-lunarc-proj"),
    "hosts": {
        "team-build-lunarc": {
            "ssh": "lunarc",
            "session": "team-build",
            "prompts": "prompts.txt",
            "role": "team",
        }
    },
    "instances": [],
}]
merged = mod.merge_project_hosts_into_inventory(hosts, projects)
assert merged["team-build-lunarc"]["ssh"] == "lunarc", merged
assert merged["team-build-lunarc"]["session"] == "team-build", merged
assert merged["team-build-lunarc"]["scheduler"] == "slurm", merged
assert merged["team-build-lunarc"]["slurm_job_name"] == "mcaccel-sup", merged
assert merged["team-build-lunarc"]["remote_env"] == "source /shared/env.sh", merged
projects = [{
    "name": "colliding-host-proj",
    "path": str(home / "Desktop/colliding-host-proj"),
    "hosts": {
        "lunarc": {
            "ssh": "lunarc-project-alias",
            "session": "project-lunarc",
            "prompts": "prompts.txt",
        }
    },
    "instances": [],
}]
merged = mod.merge_project_hosts_into_inventory(hosts, projects)
assert merged["lunarc"]["ssh"] == "lunarc", merged
effective = mod.effective_hosts_for_instance(hosts, "lunarc", projects[0]["hosts"]["lunarc"])
assert effective["lunarc"]["ssh"] == "lunarc-project-alias", effective
assert effective["lunarc"]["scheduler"] == "slurm", effective
instances = mod.project_instances(projects[0])
assert instances[0]["ssh"] == "lunarc-project-alias", instances
effective_from_instance = mod.effective_hosts_for_instance(hosts, instances[0]["host"], instances[0])
assert effective_from_instance["lunarc"]["ssh"] == "lunarc-project-alias", effective_from_instance
assert effective_from_instance["lunarc"]["scheduler"] == "slurm", effective_from_instance
print("ok: dashboard discovers registered/cache project roots when directory scans are unavailable")
PY
