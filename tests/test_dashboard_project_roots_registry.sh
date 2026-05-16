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

scan_dir = home / "Desktop/many-projects"
scan_dir.mkdir(parents=True)
for i in range(5):
    child = scan_dir / f"proj-{i}"
    child.mkdir()
    (child / ".codex-supervisor.toml").write_text(
        f"[project]\nname = \"proj-{i}\"\n[hosts.local]\nssh = \"local\"\n"
    )
mod.PROJECT_SEARCH_DIRS = [scan_dir]
mod.PROJECT_ROOTS_FILE = home / ".config/csup/missing-roots.txt"
mod.PROJECT_CACHE_FILE = home / ".config/csup/missing-cache.json"
orig_max_project_scan = mod.MAX_PROJECT_SCAN_ENTRIES
mod.MAX_PROJECT_SCAN_ENTRIES = 2
projects = mod.list_projects()
assert len([p for p in projects if p["name"].startswith("proj-")]) == 2, projects
mod.MAX_PROJECT_SCAN_ENTRIES = orig_max_project_scan

root_cap_dir = home / "Desktop/root-cap"
root_cap_dir.mkdir(parents=True)
root_lines = []
for i in range(5):
    child = root_cap_dir / f"root-proj-{i}"
    child.mkdir()
    (child / ".codex-supervisor.toml").write_text(
        f"[project]\nname = \"root-proj-{i}\"\n[hosts.local]\nssh = \"local\"\n"
    )
    root_lines.append(str(child))
mod.PROJECT_SEARCH_DIRS = [home / "Desktop/projects-does-not-exist"]
mod.PROJECT_ROOTS_FILE = home / ".config/csup/root-cap-roots.txt"
mod.PROJECT_ROOTS_FILE.write_text("\n".join(root_lines) + "\n")
mod.PROJECT_CACHE_FILE = home / ".config/csup/missing-cache.json"
mod.MAX_PROJECT_SCAN_ENTRIES = 2
projects = mod.list_projects()
assert len([p for p in projects if p["name"].startswith("root-proj-")]) == 2, projects
mod.MAX_PROJECT_SCAN_ENTRIES = orig_max_project_scan

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

mod.PROJECT_CACHE_FILE.write_text(__import__("json").dumps([{
    "path": str(home / f"Desktop/cache-cap-{i}"),
    "config": {"project": {"name": f"cache-cap-{i}"}, "hosts": {"local": {"ssh": "local"}}},
} for i in range(5)]))
mod.MAX_PROJECT_SCAN_ENTRIES = 2
projects = mod.list_projects()
assert len([p for p in projects if p["name"].startswith("cache-cap-")]) == 2, projects
mod.MAX_PROJECT_SCAN_ENTRIES = orig_max_project_scan

mod.PROJECT_SEARCH_DIRS = [home / "Desktop/projects-does-not-exist"]
mod.PROJECT_ROOTS_FILE = home / ".config/csup/oversized-roots.txt"
mod.PROJECT_ROOTS_FILE.write_text("#" * 1_000_001)
mod.PROJECT_CACHE_FILE = home / ".config/csup/oversized-cache.json"
mod.PROJECT_CACHE_FILE.write_text("[" + (" " * 2_000_001) + "]")
projects = mod.list_projects()
assert projects == [], projects
assert mod.read_text_bounded(mod.PROJECT_ROOTS_FILE, max_bytes=1_000_000, label="project roots read") is None
assert mod.read_text_bounded(mod.PROJECT_CACHE_FILE, max_bytes=2_000_000, label="project cache read") is None
assert mod.bounded_env_file_path("MISSING_TEST_ENV", pathlib.Path("fallback")) == pathlib.Path("fallback")
old_registry_env = __import__("os").environ.get("CSUP_PROJECT_ROOTS_FILE")
try:
    __import__("os").environ["CSUP_PROJECT_ROOTS_FILE"] = "x" * (mod.MAX_DASHBOARD_ENV_PATH_CHARS + 1)
    assert mod.bounded_env_file_path("CSUP_PROJECT_ROOTS_FILE", pathlib.Path("fallback")) == pathlib.Path("fallback")
finally:
    if old_registry_env is None:
        __import__("os").environ.pop("CSUP_PROJECT_ROOTS_FILE", None)
    else:
        __import__("os").environ["CSUP_PROJECT_ROOTS_FILE"] = old_registry_env
small = home / ".config/csup/small.txt"
small.write_bytes("ok\xff".encode("latin1"))
assert mod.read_text_bounded(small, max_bytes=10, label="small read") == "ok�"

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

orig_run_stable = mod.run_stable
run_calls = []
def fake_run_stable(cmd, *args, **kwargs):
    run_calls.append((cmd, kwargs))
    assert kwargs.get("timeout") == 8.0, kwargs
    assert kwargs.get("retries") == 0, kwargs
    assert cmd[0] == "ssh" and "cat" in cmd, cmd
    return __import__("subprocess").CompletedProcess(
        cmd, 0,
        "[hosts.remote-team]\nssh = \"lunarc\"\nsession = \"remote-team\"\n",
        "",
    )
mod.REMOTE_PROJECT_TOML_CACHE.clear()
mod.run_stable = fake_run_stable
merged_remote = mod.merge_remote_project_hosts({
    "lunarc": {"ssh": "lunarc", "project_dir": "/remote/proj"}
})
assert merged_remote["remote-team"]["session"] == "remote-team", merged_remote
assert run_calls, "remote toml fetch must use bounded run_stable"
mod.run_stable = orig_run_stable

print("ok: dashboard discovers registered/cache project roots when directory scans are unavailable")
PY
