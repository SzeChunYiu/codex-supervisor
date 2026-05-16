#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CSUP="$ROOT/bin/csup"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

HOSTNAME_MATCH="$(uname -n)"
mkdir -p "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks" "$TMPDIR/home/.config/csup" "$TMPDIR/bin"

cat > "$TMPDIR/home/.config/csup/hosts.toml" <<HOSTS
[hosts."mac-mini"]
ssh = "local"
hostname_match = "$HOSTNAME_MATCH"
HOSTS

cat > "$TMPDIR/home/Desktop/projects/proj-a/.codex-supervisor.toml" <<'TOML'
schema_version = 1

[project]
name = "proj-a"

[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "proj-a-main"
TOML

cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-prompts.txt" <<'PROMPTS'
/goal You are PANE 0, lane bugs. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
/goal You are PANE 1, lane perf. Read docs/parallel-sessions.md and docs/parallel-sessions/perf.md, then complete one compact-safe iteration.
/goal You are PANE 2, lane worker-a. Read docs/parallel-sessions.md and docs/parallel-sessions/worker-a.md, then complete one compact-safe iteration.
PROMPTS

cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/bugs.txt" <<'TASKS'
/goal bug task one
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/worker-a.txt" <<'TASKS'
/goal worker task one
/goal worker task two
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/open.txt" <<'TASKS'
/goal open task one
/goal open task two
TASKS
cat > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/bad,lane.txt" <<'TASKS'
/goal unsafe lane task one
/goal unsafe lane task two
/goal unsafe lane task three
/goal unsafe lane task four
/goal unsafe lane task five
/goal unsafe lane task six
/goal unsafe lane task seven
/goal unsafe lane task eight
/goal unsafe lane task nine
TASKS
: > "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt"

cat > "$TMPDIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case "$1" in
  has-session) exit 1 ;;
  list-sessions) exit 0 ;;
  list-panes) exit 0 ;;
esac
exit 0
TMUX
chmod +x "$TMPDIR/bin/tmux"

cat > "$TMPDIR/supervisor" <<'SUPERVISOR'
#!/usr/bin/env bash
{
  echo "session=$CODEX_SUPERVISOR_SESSION"
  echo "prompts=$CODEX_SUPERVISOR_PROMPTS"
  echo "tasks=$CODEX_SUPERVISOR_TASKS_DIR"
  echo "lanes=$CODEX_SUPERVISOR_LANES"
  echo "dynamic_workers=$CODEX_SUPERVISOR_DYNAMIC_WORKERS"
  echo "reviewer=$CODEX_SUPERVISOR_REVIEWER"
  echo "generated_only=$CODEX_SUPERVISOR_GENERATED_ONLY"
  echo "max_panes=$CODEX_SUPERVISOR_MAX_PANES"
  echo "args=$*"
} > "$CSUP_CAPTURE_FILE"
echo "fake supervisor started"
SUPERVISOR
chmod +x "$TMPDIR/supervisor"

dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run
)"

if [[ "$dry_run" != *"START proj-a/mac-mini session=proj-a-main lanes=worker-a,bugs dynamic_workers=2 panes=6 queued=5"* ]]; then
  printf 'govern dry-run should propose queued lanes in priority order, got:\n%s\n' "$dry_run" >&2
  exit 1
fi
if [[ "$dry_run" != *"capacity=8 pane(s) bottleneck=session_cap"* ]]; then
  printf 'govern dry-run should explain the current capacity bottleneck, got:\n%s\n' "$dry_run" >&2
  exit 1
fi

bad_fixed_panes_dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FIXED_PANES=bad \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run
)"

if [[ "$bad_fixed_panes_dry_run" != *"START proj-a/mac-mini session=proj-a-main lanes=worker-a,bugs dynamic_workers=2 panes=6 queued=5"* ]]; then
  printf 'govern should ignore invalid CSUP_GOVERNOR_FIXED_PANES instead of crashing, got:\n%s\n' "$bad_fixed_panes_dry_run" >&2
  exit 1
fi

huge_fixed_panes_dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FIXED_PANES=999999 \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run
)"

if [[ "$huge_fixed_panes_dry_run" != *"START proj-a/mac-mini session=proj-a-main lanes=worker-a,bugs dynamic_workers=2 panes=6 queued=5"* ]]; then
  printf 'govern should clamp oversized CSUP_GOVERNOR_FIXED_PANES to the safe default, got:\n%s\n' "$huge_fixed_panes_dry_run" >&2
  exit 1
fi

capped_dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run --max-panes=4
)"

if [[ "$capped_dry_run" != *"capacity=4 pane(s)"* ]]; then
  printf 'govern --max-panes should cap computed capacity, got:\n%s\n' "$capped_dry_run" >&2
  exit 1
fi
if [[ "$capped_dry_run" != *"bottleneck=operator_cap"* ]]; then
  printf 'govern --max-panes should explain operator-cap bottleneck, got:\n%s\n' "$capped_dry_run" >&2
  exit 1
fi
if [[ "$capped_dry_run" != *"START proj-a/mac-mini session=proj-a-main lanes=worker-a,bugs dynamic_workers=0 panes=4 queued=5"* ]]; then
  printf 'govern --max-panes should cap the started pane count before adding dynamic workers, got:\n%s\n' "$capped_dry_run" >&2
  exit 1
fi

if HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run --max-panes=0 >/tmp/csup-governor-max-panes.out 2>/tmp/csup-governor-max-panes.err; then
  echo "govern --max-panes=0 should fail instead of removing fixed role capacity" >&2
  exit 1
fi
grep -q "govern --max-panes must be a positive integer" /tmp/csup-governor-max-panes.err

json_dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run --json
)"

python3 - "$json_dry_run" <<'PY'
import json
import sys

events = [json.loads(line) for line in sys.argv[1].splitlines() if line.strip()]
assert events[0]["event"] == "summary", events
assert events[0]["capacity"] == 8, events
assert events[0]["bottleneck"] == "session_cap", events
start = next(event for event in events if event["event"] == "start")
assert start["project"] == "proj-a", start
assert start["host"] == "mac-mini", start
assert start["session"] == "proj-a-main", start
assert start["lanes"] == "worker-a,bugs", start
assert start["dynamic_workers"] == 2, start
assert start["panes"] == 6, start
assert start["queued"] == 5, start
assert start["generated_only"] == 0, start
PY

json_capped_dry_run="$(
  HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  CSUP_GOVERNOR_FREE_RAM_MB=16000 \
  CSUP_GOVERNOR_FREE_DISK_GB=100 \
  CSUP_GOVERNOR_LOAD1=0 \
  CSUP_GOVERNOR_CPU_COUNT=10 \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --dry-run --json --max-panes=4
)"

python3 - "$json_capped_dry_run" <<'PY'
import json
import sys

events = [json.loads(line) for line in sys.argv[1].splitlines() if line.strip()]
summary = events[0]
assert summary["event"] == "summary", events
assert summary["capacity"] == 4, summary
assert summary["capacity_raw"] == 8, summary
assert summary["max_panes_override"] == 4, summary
assert summary["bottleneck"] == "operator_cap", summary
start = next(event for event in events if event["event"] == "start")
assert start["panes"] == 4, start
assert start["dynamic_workers"] == 0, start
PY

if HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --apply --json >/tmp/csup-governor-json-apply.out 2>/tmp/csup-governor-json-apply.err; then
  echo "govern --apply --json should fail instead of mixing JSON with launcher output" >&2
  exit 1
fi
grep -q "govern --json is only supported with --dry-run" /tmp/csup-governor-json-apply.err

CSUP_CAPTURE_FILE="$TMPDIR/capture.txt" \
HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_SUPERVISOR="$TMPDIR/supervisor" \
CSUP_GOVERNOR_FREE_RAM_MB=16000 \
CSUP_GOVERNOR_FREE_DISK_GB=100 \
CSUP_GOVERNOR_LOAD1=0 \
CSUP_GOVERNOR_CPU_COUNT=10 \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" govern --apply >/tmp/csup-governor-apply.out

grep -q '^session=proj-a-main$' "$TMPDIR/capture.txt"
grep -q '^lanes=worker-a,bugs$' "$TMPDIR/capture.txt"
grep -q '^dynamic_workers=2$' "$TMPDIR/capture.txt"
grep -q '^reviewer=1$' "$TMPDIR/capture.txt"
grep -q '^generated_only=0$' "$TMPDIR/capture.txt"
grep -q '^max_panes=6$' "$TMPDIR/capture.txt"
grep -q '^args=start --no-attach$' "$TMPDIR/capture.txt"

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_SUPERVISOR="$TMPDIR/supervisor" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" submit proj-a perf "check the perf queue" >/tmp/csup-submit.out

grep -q '^/goal check the perf queue$' "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt"
grep -q "queued proj-a/perf" /tmp/csup-submit.out

HOME="$TMPDIR/home" \
CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
CSUP_SUPERVISOR="$TMPDIR/supervisor" \
PATH="$TMPDIR/bin:$PATH" \
  "$CSUP" submit proj-a perf "/goalbad should be normalized" >/tmp/csup-submit-goalbad.out

grep -q '^/goal /goalbad should be normalized$' "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt" || {
  echo "submit should prefix malformed /goal-like text instead of queuing invalid prompt syntax" >&2
  cat "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt" >&2
  exit 1
}

long_goal="$(printf "%05000d" 0 | tr 0 x)"
if HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" submit proj-a perf "$long_goal" >/tmp/csup-submit-long.out 2>/tmp/csup-submit-long.err; then
  echo "submit should reject oversized goal text" >&2
  exit 1
fi
grep -q "submit: goal text must be 4096 characters or fewer" /tmp/csup-submit-long.err || {
  cat /tmp/csup-submit-long.err >&2
  exit 1
}
if grep -q "$long_goal" "$TMPDIR/home/Desktop/projects/proj-a/codex-tasks/perf.txt"; then
  echo "oversized goal text should not be written to the queue" >&2
  exit 1
fi

if HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" submit proj-a ../escape "bad lane" >/tmp/csup-submit-bad-lane.out 2>/tmp/csup-submit-bad-lane.err; then
  echo "submit should reject path-traversal lane names" >&2
  exit 1
fi
grep -q "submit: lane must be a safe filename token" /tmp/csup-submit-bad-lane.err || {
  cat /tmp/csup-submit-bad-lane.err >&2
  exit 1
}
[[ ! -e "$TMPDIR/home/Desktop/projects/proj-a/escape.txt" ]] || {
  echo "invalid lane should not write outside codex-tasks" >&2
  exit 1
}

mkdir -p "$TMPDIR/home/Desktop/projects/proj-b"
cat > "$TMPDIR/home/Desktop/projects/proj-b/.codex-supervisor.toml" <<'TOML'
schema_version = 1
[project]
name = "proj-b"
[hosts."mac-mini"]
prompts = "codex-prompts.txt"
tasks_dir = "../outside"
session = "proj-b-main"
TOML

if HOME="$TMPDIR/home" \
  CSUP_HOSTS_FILE="$TMPDIR/home/.config/csup/hosts.toml" \
  CSUP_SUPERVISOR="$TMPDIR/supervisor" \
  PATH="$TMPDIR/bin:$PATH" \
    "$CSUP" submit proj-b perf "bad tasks dir" >/tmp/csup-submit-bad-tasks.out 2>/tmp/csup-submit-bad-tasks.err; then
  echo "submit should reject tasks_dir paths outside the project" >&2
  exit 1
fi
grep -q "submit: tasks_dir must resolve inside the project" /tmp/csup-submit-bad-tasks.err || {
  cat /tmp/csup-submit-bad-tasks.err >&2
  exit 1
}
[[ ! -e "$TMPDIR/home/Desktop/projects/outside/perf.txt" ]] || {
  echo "invalid tasks_dir should not write outside the project" >&2
  exit 1
}
