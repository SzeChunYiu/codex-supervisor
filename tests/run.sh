#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

for test_file in "$ROOT"/tests/test_*.sh; do
  printf '==> %s\n' "${test_file##*/}"
  bash "$test_file"
done
