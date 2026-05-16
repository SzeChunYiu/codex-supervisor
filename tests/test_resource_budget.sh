#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/codex-supervisor.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  PROMPTS=(a b c)
  free_ram_mb() { echo 4096; }
  free_gb_on_cwd() { echo 100; }
  free_gb_on_runtime_root() { echo 100; }
  MIN_FREE_RAM_MB=512
  RAM_MB_PER_PANE=600
  MIN_FREE_GB=5
  DISK_MB_PER_PANE=1024
  MAX_LOAD_PER_CPU=0
  ensure_start_resource_budget
' _ "$SCRIPT"


if CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  PROMPTS=(a b)
  free_ram_mb() { echo 16000; }
  free_gb_on_cwd() { echo 100; }
  free_gb_on_runtime_root() { echo 100; }
  cpu_count() { echo 2; }
  load1() { echo 2.7; }
  MAX_LOAD_PER_CPU=1.0
  MIN_FREE_RAM_MB=512
  RAM_MB_PER_PANE=600
  MIN_FREE_GB=5
  DISK_MB_PER_PANE=0
  ensure_start_resource_budget
' _ "$SCRIPT" >/tmp/codex-supervisor-cpu.out 2>/tmp/codex-supervisor-cpu.err; then
  echo "resource budget should fail when projected CPU/load headroom is exhausted" >&2
  exit 1
fi
grep -q "not enough CPU/load headroom" /tmp/codex-supervisor-cpu.err

if CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  PROMPTS=(a b c d)
  free_ram_mb() { echo 2000; }
  free_gb_on_cwd() { echo 100; }
  free_gb_on_runtime_root() { echo 100; }
  MIN_FREE_RAM_MB=512
  RAM_MB_PER_PANE=600
  MIN_FREE_GB=5
  DISK_MB_PER_PANE=0
  MAX_LOAD_PER_CPU=0
  ensure_start_resource_budget
' _ "$SCRIPT" >/tmp/codex-supervisor-resource.out 2>/tmp/codex-supervisor-resource.err; then
  echo "resource budget should fail when projected RAM exceeds free RAM" >&2
  exit 1
fi
grep -q "not enough free RAM" /tmp/codex-supervisor-resource.err

if CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  PROMPTS=(a b c)
  free_ram_mb() { echo 4096; }
  free_gb_on_cwd() { echo 6; }
  free_gb_on_runtime_root() { echo 6; }
  MIN_FREE_RAM_MB=512
  RAM_MB_PER_PANE=0
  MIN_FREE_GB=5
  DISK_MB_PER_PANE=1024
  MAX_LOAD_PER_CPU=0
  ensure_start_resource_budget
' _ "$SCRIPT" >/tmp/codex-supervisor-disk.out 2>/tmp/codex-supervisor-disk.err; then
  echo "resource budget should fail when projected disk need exceeds free disk" >&2
  exit 1
fi
grep -q "not enough free disk" /tmp/codex-supervisor-disk.err

CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  PROMPTS=(a b c)
  free_ram_mb() { echo 4096; }
  free_gb_on_cwd() { echo 1; }
  free_gb_on_runtime_root() { echo 100; }
  MIN_FREE_RAM_MB=512
  RAM_MB_PER_PANE=600
  MIN_FREE_GB=5
  DISK_MB_PER_PANE=1024
  MAX_LOAD_PER_CPU=0
  ensure_start_resource_budget
' _ "$SCRIPT"

CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  PROMPTS=(a)
  free_ram_mb() { echo 4096; }
  free_gb_on_runtime_root() { echo 100; }
  MIN_FREE_RAM_MB=bad
  RAM_MB_PER_PANE=bad
  MIN_FREE_GB=bad
  DISK_MB_PER_PANE=bad
  MAX_LOAD_PER_CPU=0
  ensure_start_resource_budget
' _ "$SCRIPT"

CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c '
  source "$1"
  free_gb_on_cwd() { echo 100; }
  MIN_FREE_GB=bad
  WARN_FREE_GB=bad
  ensure_disk_space
' _ "$SCRIPT"

stagger="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c 'source "$1"; effective_start_stagger_secs 2' _ "$SCRIPT")"
[[ "$stagger" == "0" ]] || { echo "2 panes should not stagger by default" >&2; exit 1; }

stagger="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c 'source "$1"; effective_start_stagger_secs 3' _ "$SCRIPT")"
[[ "$stagger" == "1" ]] || { echo "3 panes should stagger 1s by default" >&2; exit 1; }

stagger="$(CODEX_SUPERVISOR_TEST_SOURCE=1 bash -c 'source "$1"; effective_start_stagger_secs 6' _ "$SCRIPT")"
[[ "$stagger" == "2" ]] || { echo "6 panes should stagger 2s by default" >&2; exit 1; }

mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/free" <<'MOCK_FREE'
#!/usr/bin/env bash
cat <<'FREE_OUT'
              total        used        free      shared  buff/cache   available
Mem:          31800        1200        3000          20        9000       27654
Swap:          4096           0        4096
FREE_OUT
MOCK_FREE
chmod +x "$TMPDIR/bin/free"

linux_free="$(PATH="$TMPDIR/bin:$PATH" CODEX_SUPERVISOR_TEST_SOURCE=1 \
  bash -c 'source "$1"; free_ram_mb' _ "$SCRIPT")"
[[ "$linux_free" == "27654" ]] || {
  printf 'Linux free_ram_mb should use Mem available column, got: %s\n' "$linux_free" >&2
  exit 1
}
