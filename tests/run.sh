#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_files=(
  test_artifacts.sh
  test_claims.sh
  test_config.sh
  test_control_plane.sh
  test_dependency.sh
  test_dispatch.sh
  test_guard.sh
  test_install_skill.sh
  test_payload_text.sh
  test_read.sh
  test_read_serialization.sh
  test_smoke.sh
  test_ssh.sh
  test_visible_runner.sh
)

for test_name in "${test_files[@]}"; do
  test_file="$root/tests/$test_name"
  printf '==> %s\n' "${test_file##*/}"
  bash "$test_file"
done
