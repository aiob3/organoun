#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
export ORGAN_CONFIG="$REPO_ROOT/tests/fixtures/targets.json"

actual="$("$REPO_ROOT/bin/organ" list --json)"
assert_jq "$actual" '.ok == true'
assert_jq "$actual" '.data.targets | length == 3'
assert_jq "$actual" '.data.targets[0].alias == "claude-onp"'

export ORGAN_CONFIG="$REPO_ROOT/tests/fixtures/valid-alias-targets.json"
actual="$("$REPO_ROOT/bin/organ" list --json)"
assert_jq "$actual" '.data.targets[0].alias == "claude_onp.1"'

mkdir -p -- "$XDG_CONFIG_HOME/organoun"
cp -- "$REPO_ROOT/tests/fixtures/targets.json" "$XDG_CONFIG_HOME/organoun/targets.json"
unset ORGAN_CONFIG
actual="$("$REPO_ROOT/bin/organ" list --json)"
assert_jq "$actual" '.data.targets | length == 3'

export ORGAN_CONFIG="$REPO_ROOT/tests/fixtures/targets.json"
set +e
actual="$("$REPO_ROOT/bin/organ" status missing --json 2>&1)"
rc=$?
set -e
assert_eq "64" "$rc"
assert_jq "$actual" '.error.code == "TARGET_NOT_FOUND"'

assert_config_rejected() {
  local label="$1"
  local config_path="$2"
  local output reject_rc

  export ORGAN_CONFIG="$config_path"
  set +e
  output="$("$REPO_ROOT/bin/organ" list --json 2>&1)"
  reject_rc=$?
  set -e
  if [[ "$reject_rc" -ne 64 ]]; then
    printf '%s: expected exit 64, got %s\n%s\n' "$label" "$reject_rc" "$output" >&2
    return 1
  fi
  assert_jq "$output" '.ok == false and .error.code == "CONFIG_INVALID"'
}

# The registry is authority, so jq's last-key-wins and invalid-UTF-8 repair
# behavior must never decide routing. Strict rejection covers every object
# scope, escaped-equivalent keys, and exactly one JSON document.
raw_duplicate="$TEST_TMP/config-raw-duplicate.json"
printf '%s\n' '{"schema_version":"1","schema_version":"1","targets":[]}' >"$raw_duplicate"
assert_config_rejected 'raw top-level duplicate' "$raw_duplicate"

escaped_duplicate="$TEST_TMP/config-escaped-duplicate.json"
printf '%s\n' '{"schema_version":"1","\u0073chema_version":"1","targets":[]}' >"$escaped_duplicate"
assert_config_rejected 'escaped top-level duplicate' "$escaped_duplicate"

nested_duplicate="$TEST_TMP/config-nested-duplicate.json"
printf '%s\n' '{"schema_version":"1","targets":[{"alias":"nested","alias":"nested","transport":"local","host":"local","cwd":"/tmp","mode":"adopted","tmux_target":"nested:0.0"}]}' >"$nested_duplicate"
assert_config_rejected 'nested routing duplicate' "$nested_duplicate"

nested_escaped_duplicate="$TEST_TMP/config-nested-escaped-duplicate.json"
printf '%s\n' '{"schema_version":"1","targets":[{"alias":"nested","transport":"local","host":"local","\u0068ost":"local","cwd":"/tmp","mode":"adopted","tmux_target":"nested:0.0"}]}' >"$nested_escaped_duplicate"
assert_config_rejected 'nested escaped routing duplicate' "$nested_escaped_duplicate"

invalid_utf8="$TEST_TMP/config-invalid-utf8.json"
printf '{"schema_version":"1","targets":[{"alias":"invalid-byte","transport":"local","host":"local","cwd":"/tmp/\377","mode":"adopted","tmux_target":"invalid:0.0"}]}\n' >"$invalid_utf8"
assert_config_rejected 'invalid UTF-8 routing field' "$invalid_utf8"

multi_document="$TEST_TMP/config-multi-document.json"
printf '%s\n%s\n' \
  '{"schema_version":"1","targets":[]}' \
  '{"schema_version":"1","targets":[]}' >"$multi_document"
assert_config_rejected 'multiple JSON documents' "$multi_document"

# Mutating the source after schema validation must not change the lookup.
# The jq shim changes only the mutable source and delegates every operation to
# the real binary; a private snapshot therefore remains authoritative.
real_jq="$(command -v jq)"
shim_dir="$TEST_TMP/jq-shim"
mkdir -p -- "$shim_dir"
apply_config="$TEST_TMP/config-snapshot.json"
replacement_config="$TEST_TMP/config-replacement.json"
cp -- "$REPO_ROOT/tests/fixtures/targets.json" "$apply_config"
printf '%s\n' '{"schema_version":"1","targets":[{"alias":"mutated","transport":"local","host":"local","cwd":"/tmp","mode":"adopted","tmux_target":"mutated:0.0"}]}' >"$replacement_config"
cat >"$shim_dir/jq" <<'SHIM'
#!/usr/bin/env bash
set -u

set +e
"${ORGAN_TEST_REAL_JQ:?}" "$@"
jq_rc=$?
set -e

for jq_arg in "$@"; do
  if [[ "$jq_arg" == *'def valid_target'* && ! -e "${ORGAN_TEST_MUTATION_MARKER:?}" ]]; then
    cp -- "${ORGAN_TEST_REPLACEMENT_CONFIG:?}" "${ORGAN_TEST_MUTATE_CONFIG:?}"
    : >"$ORGAN_TEST_MUTATION_MARKER"
    break
  fi
done
exit "$jq_rc"
SHIM
chmod 700 -- "$shim_dir/jq"

export ORGAN_CONFIG="$apply_config"
snapshot_output="$(
  PATH="$shim_dir:$PATH" \
    ORGAN_TEST_REAL_JQ="$real_jq" \
    ORGAN_TEST_MUTATE_CONFIG="$apply_config" \
    ORGAN_TEST_REPLACEMENT_CONFIG="$replacement_config" \
    ORGAN_TEST_MUTATION_MARKER="$TEST_TMP/config-mutated" \
    "$REPO_ROOT/bin/organ" list --json
)"
assert_jq "$snapshot_output" '.ok == true and (.data.targets | length) == 3 and .data.targets[0].alias == "claude-onp"'
