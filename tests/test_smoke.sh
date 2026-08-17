#!/usr/bin/env bash
set -euo pipefail

# The smoke scripts must run their real command paths, while these command
# doubles make that behavior hermetic.  A missing jq pipeline, status call, or
# canary release changes the observable log and fails this test.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env

fake_bin="$TEST_TMP/bin"
fake_log="$TEST_TMP/organ.log"
mkdir -p -- "$fake_bin" "$TEST_TMP/state"

make_fake() {
  local name="$1"
  local body="$2"
  printf '%s\n' "$body" >"$fake_bin/$name"
  chmod 700 -- "$fake_bin/$name"
}

make_fake tmux '#!/usr/bin/env bash
exit 0'
make_fake claude '#!/usr/bin/env bash
exit 0'
# shellcheck disable=SC2016
make_fake organ '#!/usr/bin/env bash
set -euo pipefail
printf "%s\n" "$*" >>"${ORGAN_FAKE_LOG:?}"
if [[ -v ORGAN_FAKE_STDERR ]]; then
  printf "%s\n" "$ORGAN_FAKE_STDERR" >&2
fi
case "$*" in
  "list --json")
    if [[ -v ORGAN_FAKE_LIST_RESPONSE ]]; then
      printf "%s\n" "$ORGAN_FAKE_LIST_RESPONSE"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"list","target":"","host":"","state":"unknown","delivery":"not-applicable","data":{"targets":[]}}'\''
    fi
    exit "${ORGAN_FAKE_LIST_RC:-0}"
    ;;
  "status claude-onp --json")
    if [[ -v ORGAN_FAKE_LOCAL_STATUS ]]; then
      printf "%s\n" "$ORGAN_FAKE_LOCAL_STATUS"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"status","target":"claude-onp","host":"local","state":"idle","delivery":"not-applicable","data":{}}'\''
    fi
    exit "${ORGAN_FAKE_LOCAL_STATUS_RC:-0}"
    ;;
  "status remote-managed --json")
    if [[ -v ORGAN_FAKE_REMOTE_STATUS ]]; then
      printf "%s\n" "$ORGAN_FAKE_REMOTE_STATUS"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","data":{}}'\''
    fi
    exit "${ORGAN_FAKE_REMOTE_STATUS_RC:-0}"
    ;;
  "read claude-onp --json")
    read_count_file="${ORGAN_FAKE_STATE:?}/read-count"
    read_count=0
    [[ ! -f "$read_count_file" ]] || read_count="$(<"$read_count_file")"
    read_count=$((read_count + 1))
    printf "%s\n" "$read_count" >"$read_count_file"
    if (( read_count == 1 )); then
      if [[ -v ORGAN_FAKE_READ_BEFORE_RESPONSE ]]; then
        printf "%s\n" "$ORGAN_FAKE_READ_BEFORE_RESPONSE"
      else
        printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"read","target":"claude-onp","host":"local","state":"idle","delivery":"not-applicable","data":{"excerpt":"pre-canary observation\n","truncated":false}}'\''
      fi
      exit "${ORGAN_FAKE_READ_BEFORE_RC:-0}"
    fi
    if [[ -v ORGAN_FAKE_READ_AFTER_RESPONSE ]]; then
      printf "%s\n" "$ORGAN_FAKE_READ_AFTER_RESPONSE"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"read","target":"claude-onp","host":"local","state":"idle","delivery":"not-applicable","data":{"excerpt":"ORGANOUN_LOCAL_CANARY_OK\n","truncated":false}}'\''
    fi
    exit "${ORGAN_FAKE_READ_AFTER_RC:-0}"
    ;;
  "claim claude-onp --json")
    if [[ -v ORGAN_FAKE_CLAIM_RESPONSE ]]; then
      printf "%s\n" "$ORGAN_FAKE_CLAIM_RESPONSE"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"claim","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{}}'\''
    fi
    exit "${ORGAN_FAKE_CLAIM_RC:-0}"
    ;;
  "ask claude-onp --stdin --json")
    prompt="$(cat)"
    [[ "$prompt" == "Responda exatamente ORGANOUN_LOCAL_CANARY_OK" ]] || exit 64
    if [[ -f "${ORGAN_FAKE_STATE:?}/released" ]]; then
      if [[ -v ORGAN_FAKE_POST_RELEASE_ASK_RESPONSE ]]; then
        printf "%s\n" "$ORGAN_FAKE_POST_RELEASE_ASK_RESPONSE"
      else
        printf "%s\n" '\''{"schema_version":"1","ok":false,"action":"ask","target":"claude-onp","host":"local","state":"unknown","delivery":"not-applicable","error":{"code":"CLAIM_REQUIRED","message":"an active claim is required"}}'\''
      fi
      exit "${ORGAN_FAKE_POST_RELEASE_ASK_RC:-64}"
    fi
    if [[ -v ORGAN_FAKE_ASK_RESPONSE ]]; then
      printf "%s\n" "$ORGAN_FAKE_ASK_RESPONSE"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"ask","target":"claude-onp","host":"local","state":"unknown","delivery":"unknown","data":{}}'\''
    fi
    exit "${ORGAN_FAKE_ASK_RC:-0}"
    ;;
  "release claude-onp --json")
    : >"${ORGAN_FAKE_STATE:?}/released"
    if [[ -v ORGAN_FAKE_RELEASE_RESPONSE ]]; then
      printf "%s\n" "$ORGAN_FAKE_RELEASE_RESPONSE"
    else
      printf "%s\n" '\''{"schema_version":"1","ok":true,"action":"release","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{}}'\''
    fi
    exit "${ORGAN_FAKE_RELEASE_RC:-0}"
    ;;
  *) exit 64 ;;
esac'

local_script="$REPO_ROOT/scripts/smoke-local.sh"
remote_script="$REPO_ROOT/scripts/smoke-remote.sh"
valid_list='{"schema_version":"1","ok":true,"action":"list","target":"","host":"","state":"unknown","delivery":"not-applicable","data":{"targets":[]}}'
valid_local_status='{"schema_version":"1","ok":true,"action":"status","target":"claude-onp","host":"local","state":"idle","delivery":"not-applicable","data":{}}'
valid_remote_status='{"schema_version":"1","ok":true,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","data":{}}'
valid_read_before='{"schema_version":"1","ok":true,"action":"read","target":"claude-onp","host":"local","state":"idle","delivery":"not-applicable","data":{"excerpt":"pre-canary observation\n","truncated":false}}'
valid_local_unknown_error='{"schema_version":"1","ok":false,"action":"status","target":"claude-onp","host":"local","state":"unknown","delivery":"not-applicable","error":{"code":"OUTSOURCERER_UNAVAILABLE","message":"synthetic observation unavailable"}}'
valid_remote_unknown_error='{"schema_version":"1","ok":false,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","error":{"code":"REMOTE_UNREACHABLE","message":"synthetic observation unavailable"}}'
valid_claim='{"schema_version":"1","ok":true,"action":"claim","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{}}'
valid_ask='{"schema_version":"1","ok":true,"action":"ask","target":"claude-onp","host":"local","state":"unknown","delivery":"unknown","data":{}}'
valid_release='{"schema_version":"1","ok":true,"action":"release","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{}}'
valid_post_release_refusal='{"schema_version":"1","ok":false,"action":"ask","target":"claude-onp","host":"local","state":"unknown","delivery":"not-applicable","error":{"code":"CLAIM_REQUIRED","message":"an active claim is required"}}'
duplicate_list_data='{"schema_version":"1","ok":true,"action":"list","target":"","host":"","state":"unknown","delivery":"not-applicable","data":{"transcript":"synthetic-secret"},"data":{"targets":[]}}'
duplicate_list_targets_escaped='{"schema_version":"1","ok":true,"action":"list","target":"","host":"","state":"unknown","delivery":"not-applicable","data":{"targets":[{"transcript":"synthetic-secret"}],"\u0074argets":[]}}'
duplicate_local_status_data='{"schema_version":"1","ok":true,"action":"status","target":"claude-onp","host":"local","state":"idle","delivery":"not-applicable","data":{"transcript":"synthetic-secret"},"data":{}}'
duplicate_local_status_error_escaped='{"schema_version":"1","ok":false,"action":"status","target":"claude-onp","host":"local","state":"unknown","delivery":"not-applicable","error":{"\u0063ode":"synthetic-secret","code":"OUTSOURCERER_UNAVAILABLE","message":"synthetic observation unavailable"}}'
duplicate_remote_status_data='{"schema_version":"1","ok":true,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","data":{"transcript":"synthetic-secret"},"data":{}}'
duplicate_remote_status_error_escaped='{"schema_version":"1","ok":false,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","error":{"\u0063ode":"synthetic-secret","code":"REMOTE_UNREACHABLE","message":"synthetic observation unavailable"}}'
duplicate_claim_data='{"schema_version":"1","ok":true,"action":"claim","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{"transcript":"synthetic-secret"},"data":{}}'
duplicate_ask_data='{"schema_version":"1","ok":true,"action":"ask","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{"transcript":"synthetic-secret"},"data":{}}'
duplicate_release_data='{"schema_version":"1","ok":true,"action":"release","target":"claude-onp","host":"local","state":"unknown","delivery":"confirmed","data":{"transcript":"synthetic-secret"},"data":{}}'
duplicate_post_release_error_escaped='{"schema_version":"1","ok":false,"action":"ask","target":"claude-onp","host":"local","state":"unknown","delivery":"not-applicable","error":{"code":"CLAIM_REQUIRED","message":"synthetic-secret","\u006dessage":"an active claim is required"}}'

run_smoke() {
  PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" "$@"
}

run_smoke_env() {
  local -a env_specs=()

  while [[ "$1" != -- ]]; do
    env_specs+=("$1")
    shift
  done
  shift
  env PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" \
    "${env_specs[@]}" "$@"
}

run_smoke_override() {
  local env_name="$1"
  local response="$2"
  shift 2

  run_smoke_env "${env_name}=${response}" -- "$@"
}

assert_fake_override_bytes() {
  local env_name="$1"
  local expected="$2"
  shift 2
  local actual

  : >"$fake_log"
  actual="$(env PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" \
    "${env_name}=${expected}" "$fake_bin/organ" "$@")"
  assert_eq "$expected" "$actual"
}

assert_fake_stdin_override_bytes() {
  local env_name="$1"
  local expected="$2"
  local expected_rc="$3"
  shift 3
  local actual actual_rc

  : >"$fake_log"
  set +e
  actual="$(printf '%s' 'Responda exatamente ORGANOUN_LOCAL_CANARY_OK' |
    env PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" \
      "${env_name}=${expected}" "$fake_bin/organ" "$@")"
  actual_rc=$?
  set -e
  assert_eq "$expected" "$actual"
  assert_eq "$expected_rc" "$actual_rc"
}

boundary_failures=0
record_boundary_failure() {
  printf 'smoke boundary regression (%s): %s\n' "$1" "$2" >&2
  boundary_failures=$((boundary_failures + 1))
}

assert_smoke_accepts_env() {
  local label="$1"
  local summary="$2"
  local expected_log="$3"
  shift 3
  local actual rc logged

  : >"$fake_log"
  set +e
  actual="$(run_smoke_env "$@" 2>&1)"
  rc=$?
  set -e
  logged="$(<"$fake_log")"
  if [[ "$rc" -ne 0 || "$actual" != "$summary" ]]; then
    record_boundary_failure "$label" "expected success rc=0 summary=${summary}; got rc=${rc} output=${actual}"
  fi
  if [[ "$logged" != "$expected_log" ]]; then
    record_boundary_failure "$label" "unexpected command log=${logged}"
  fi
  return 0
}

assert_smoke_rejects_env() {
  local label="$1"
  local summary="$2"
  local expected_log="$3"
  shift 3
  local actual rc logged

  : >"$fake_log"
  set +e
  actual="$(run_smoke_env "$@" 2>&1)"
  rc=$?
  set -e
  logged="$(<"$fake_log")"
  if [[ "$rc" -eq 0 || "$actual" == *"$summary"* ]]; then
    record_boundary_failure "$label" "accepted rc=${rc} output=${actual}"
  fi
  if [[ "$logged" != "$expected_log" ]]; then
    record_boundary_failure "$label" "unexpected command log=${logged}"
  fi
  return 0
}

assert_canary_rejects_override() {
  local label="$1"
  local env_name="$2"
  local response="$3"
  local expected_log="$4"
  local actual rc logged

  rm -f -- "$TEST_TMP/state/released"
  rm -f -- "$TEST_TMP/state/read-count"
  : >"$fake_log"
  set +e
  actual="$(printf 'YES\n' | env PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" \
    ORGAN_FAKE_STATE="$TEST_TMP/state" "${env_name}=${response}" \
    script -qefc "$local_script --canary" /dev/null 2>&1)"
  rc=$?
  set -e
  rm -f -- "$TEST_TMP/state/released"
  logged="$(<"$fake_log")"
  if [[ "$rc" -eq 0 || "$actual" == *'ORGAN_LOCAL_SMOKE_OK'* ]]; then
    record_boundary_failure "$label" "accepted rc=${rc} output=${actual}"
  fi
  if [[ "$logged" != "$expected_log" ]]; then
    record_boundary_failure "$label" "unexpected command log=${logged}"
  fi
  return 0
}

hostile_failures=0
assert_smoke_rejects() {
  local label="$1"
  local env_name="$2"
  local response="$3"
  local script="$4"
  local summary="$5"
  local expected_log="$6"
  local actual rc logged

  : >"$fake_log"
  set +e
  actual="$(run_smoke_override "$env_name" "$response" "$script" 2>&1)"
  rc=$?
  set -e
  logged="$(<"$fake_log")"
  if [[ "$rc" -eq 0 || "$actual" == *"$summary"* ]]; then
    printf 'smoke accepted hostile envelope (%s): rc=%s output=%s\n' \
      "$label" "$rc" "$actual" >&2
    hostile_failures=$((hostile_failures + 1))
  fi
  if [[ "$logged" != "$expected_log" ]]; then
    printf 'unexpected smoke command log (%s): %s\n' "$label" "$logged" >&2
    hostile_failures=$((hostile_failures + 1))
  fi
  return 0
}

assert_fake_override_bytes ORGAN_FAKE_LIST_RESPONSE "$valid_list" list --json
assert_fake_override_bytes ORGAN_FAKE_LOCAL_STATUS "$valid_local_status" status claude-onp --json
assert_fake_override_bytes ORGAN_FAKE_REMOTE_STATUS "$valid_remote_status" status remote-managed --json
assert_fake_override_bytes ORGAN_FAKE_READ_BEFORE_RESPONSE "$valid_read_before" read claude-onp --json
rm -f -- "$TEST_TMP/state/read-count"
assert_fake_override_bytes ORGAN_FAKE_CLAIM_RESPONSE "$valid_claim" claim claude-onp --json
assert_fake_stdin_override_bytes ORGAN_FAKE_ASK_RESPONSE "$valid_ask" 0 ask claude-onp --stdin --json
assert_fake_override_bytes ORGAN_FAKE_RELEASE_RESPONSE "$valid_release" release claude-onp --json
assert_fake_stdin_override_bytes ORGAN_FAKE_POST_RELEASE_ASK_RESPONSE "$valid_post_release_refusal" 64 ask claude-onp --stdin --json
rm -f -- "$TEST_TMP/state/released" "$TEST_TMP/state/read-count"
assert_fake_override_bytes ORGAN_FAKE_LIST_RESPONSE "$duplicate_list_data" list --json
assert_smoke_rejects_env 'list duplicate data key' ORGAN_LOCAL_SMOKE_OK \
  'list --json' \
  "ORGAN_FAKE_LIST_RESPONSE=$duplicate_list_data" -- "$local_script"
: >"$fake_log"

local_output="$(run_smoke "$local_script")"
assert_eq 'ORGAN_LOCAL_SMOKE_OK' "$local_output"
assert_eq $'list --json\nstatus claude-onp --json' "$(<"$fake_log")"

: >"$fake_log"
remote_output="$(run_smoke "$remote_script")"
assert_eq 'ORGAN_REMOTE_SMOKE_OK' "$remote_output"
assert_eq 'status remote-managed --json' "$(<"$fake_log")"

assert_smoke_accepts_env 'local documented unknown status with rc64' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "ORGAN_FAKE_LOCAL_STATUS=$valid_local_unknown_error" ORGAN_FAKE_LOCAL_STATUS_RC=64 -- "$local_script"
assert_smoke_accepts_env 'remote documented unknown status with rc64' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "ORGAN_FAKE_REMOTE_STATUS=$valid_remote_unknown_error" ORGAN_FAKE_REMOTE_STATUS_RC=64 -- "$remote_script"

list_wrong_schema="$(jq -c '.schema_version = "2"' <<<"$valid_list")"
list_wrong_action="$(jq -c '.action = "status"' <<<"$valid_list")"
list_wrong_target="$(jq -c '.target = "claude-onp"' <<<"$valid_list")"
list_wrong_host="$(jq -c '.host = "local"' <<<"$valid_list")"
list_wrong_delivery="$(jq -c '.delivery = "confirmed"' <<<"$valid_list")"
list_wrong_state="$(jq -c '.state = "idle"' <<<"$valid_list")"
list_missing_data="$(jq -c 'del(.data)' <<<"$valid_list")"
list_protected_top="$(jq -c '.unexpected = {transcript:"synthetic-secret"}' <<<"$valid_list")"
list_protected_data="$(jq -c '.data.transcript = "synthetic-secret"' <<<"$valid_list")"

for label_response in \
  "wrong schema:$list_wrong_schema" \
  "wrong action:$list_wrong_action" \
  "wrong target:$list_wrong_target" \
  "wrong host:$list_wrong_host" \
  "wrong delivery:$list_wrong_delivery" \
  "wrong state:$list_wrong_state" \
  "missing data:$list_missing_data" \
  "protected top-level:$list_protected_top" \
  "protected data:$list_protected_data"; do
  label="${label_response%%:*}"
  response="${label_response#*:}"
  assert_smoke_rejects "list $label" ORGAN_FAKE_LIST_RESPONSE "$response" \
    "$local_script" ORGAN_LOCAL_SMOKE_OK 'list --json'
done
assert_smoke_rejects 'list multiple JSON values' ORGAN_FAKE_LIST_RESPONSE \
  "$valid_list"$'\n'"$valid_list" "$local_script" ORGAN_LOCAL_SMOKE_OK 'list --json'

local_wrong_schema="$(jq -c '.schema_version = "2"' <<<"$valid_local_status")"
local_wrong_action="$(jq -c '.action = "read"' <<<"$valid_local_status")"
local_wrong_target="$(jq -c '.target = "other"' <<<"$valid_local_status")"
local_wrong_host="$(jq -c '.host = "remote.example"' <<<"$valid_local_status")"
local_wrong_delivery="$(jq -c '.delivery = "confirmed"' <<<"$valid_local_status")"
local_wrong_state="$(jq -c '.state = "bogus"' <<<"$valid_local_status")"
local_missing_data="$(jq -c 'del(.data)' <<<"$valid_local_status")"
local_protected_top="$(jq -c '.unexpected = {transcript:"synthetic-secret"}' <<<"$valid_local_status")"
local_protected_data="$(jq -c '.data.transcript = "synthetic-secret"' <<<"$valid_local_status")"
local_missing_error="$(jq -c 'del(.error)' <<<"$valid_local_unknown_error")"
local_incomplete_error="$(jq -c '.error = {code:"OUTSOURCERER_UNAVAILABLE"}' <<<"$valid_local_unknown_error")"

for label_response in \
  "wrong schema:$local_wrong_schema" \
  "wrong action:$local_wrong_action" \
  "wrong target:$local_wrong_target" \
  "wrong host:$local_wrong_host" \
  "wrong delivery:$local_wrong_delivery" \
  "wrong state:$local_wrong_state" \
  "missing data:$local_missing_data" \
  "protected top-level:$local_protected_top" \
  "protected data:$local_protected_data" \
  "missing error:$local_missing_error" \
  "incomplete error:$local_incomplete_error"; do
  label="${label_response%%:*}"
  response="${label_response#*:}"
  assert_smoke_rejects "local status $label" ORGAN_FAKE_LOCAL_STATUS "$response" \
    "$local_script" ORGAN_LOCAL_SMOKE_OK $'list --json\nstatus claude-onp --json'
done
assert_smoke_rejects 'local status multiple JSON values' ORGAN_FAKE_LOCAL_STATUS \
  "$valid_local_status"$'\n'"$valid_local_status" "$local_script" ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json'

remote_wrong_schema="$(jq -c '.schema_version = "2"' <<<"$valid_remote_status")"
remote_wrong_action="$(jq -c '.action = "read"' <<<"$valid_remote_status")"
remote_wrong_target="$(jq -c '.target = "other"' <<<"$valid_remote_status")"
remote_wrong_host="$(jq -c '.host = "local"' <<<"$valid_remote_status")"
remote_wrong_delivery="$(jq -c '.delivery = "confirmed"' <<<"$valid_remote_status")"
remote_wrong_state="$(jq -c '.state = "bogus"' <<<"$valid_remote_status")"
remote_missing_data="$(jq -c 'del(.data)' <<<"$valid_remote_status")"
remote_protected_top="$(jq -c '.unexpected = {transcript:"synthetic-secret"}' <<<"$valid_remote_status")"
remote_protected_data="$(jq -c '.data.transcript = "synthetic-secret"' <<<"$valid_remote_status")"
remote_missing_error="$(jq -c 'del(.error)' <<<"$valid_remote_unknown_error")"
remote_incomplete_error="$(jq -c '.error = {code:"REMOTE_UNREACHABLE"}' <<<"$valid_remote_unknown_error")"

for label_response in \
  "wrong schema:$remote_wrong_schema" \
  "wrong action:$remote_wrong_action" \
  "wrong target:$remote_wrong_target" \
  "wrong host:$remote_wrong_host" \
  "wrong delivery:$remote_wrong_delivery" \
  "wrong state:$remote_wrong_state" \
  "missing data:$remote_missing_data" \
  "protected top-level:$remote_protected_top" \
  "protected data:$remote_protected_data" \
  "missing error:$remote_missing_error" \
  "incomplete error:$remote_incomplete_error"; do
  label="${label_response%%:*}"
  response="${label_response#*:}"
  assert_smoke_rejects "remote status $label" ORGAN_FAKE_REMOTE_STATUS "$response" \
    "$remote_script" ORGAN_REMOTE_SMOKE_OK 'status remote-managed --json'
done
assert_smoke_rejects 'remote status multiple JSON values' ORGAN_FAKE_REMOTE_STATUS \
  "$valid_remote_status"$'\n'"$valid_remote_status" "$remote_script" ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json'

assert_fake_override_bytes ORGAN_FAKE_LIST_RESPONSE "$duplicate_list_targets_escaped" list --json
assert_fake_override_bytes ORGAN_FAKE_LOCAL_STATUS "$duplicate_local_status_data" status claude-onp --json
assert_fake_override_bytes ORGAN_FAKE_LOCAL_STATUS "$duplicate_local_status_error_escaped" status claude-onp --json
assert_fake_override_bytes ORGAN_FAKE_REMOTE_STATUS "$duplicate_remote_status_data" status remote-managed --json
assert_fake_override_bytes ORGAN_FAKE_REMOTE_STATUS "$duplicate_remote_status_error_escaped" status remote-managed --json
assert_fake_override_bytes ORGAN_FAKE_CLAIM_RESPONSE "$duplicate_claim_data" claim claude-onp --json
assert_fake_stdin_override_bytes ORGAN_FAKE_ASK_RESPONSE "$duplicate_ask_data" 0 ask claude-onp --stdin --json
assert_fake_override_bytes ORGAN_FAKE_RELEASE_RESPONSE "$duplicate_release_data" release claude-onp --json
: >"$TEST_TMP/state/released"
assert_fake_stdin_override_bytes ORGAN_FAKE_POST_RELEASE_ASK_RESPONSE \
  "$duplicate_post_release_error_escaped" 64 ask claude-onp --stdin --json
rm -f -- "$TEST_TMP/state/released"

assert_smoke_rejects_env 'list nested escaped duplicate key' ORGAN_LOCAL_SMOKE_OK \
  'list --json' \
  "ORGAN_FAKE_LIST_RESPONSE=$duplicate_list_targets_escaped" -- "$local_script"
assert_smoke_rejects_env 'local status duplicate data key' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "ORGAN_FAKE_LOCAL_STATUS=$duplicate_local_status_data" -- "$local_script"
assert_smoke_rejects_env 'local status nested escaped duplicate key' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "ORGAN_FAKE_LOCAL_STATUS=$duplicate_local_status_error_escaped" -- "$local_script"
assert_smoke_rejects_env 'remote status duplicate data key' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "ORGAN_FAKE_REMOTE_STATUS=$duplicate_remote_status_data" -- "$remote_script"
assert_smoke_rejects_env 'remote status nested escaped duplicate key' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "ORGAN_FAKE_REMOTE_STATUS=$duplicate_remote_status_error_escaped" -- "$remote_script"

assert_smoke_rejects_env 'local unknown envelope with rc0' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "ORGAN_FAKE_LOCAL_STATUS=$valid_local_unknown_error" ORGAN_FAKE_LOCAL_STATUS_RC=0 -- "$local_script"
assert_smoke_rejects_env 'remote unknown envelope with rc0' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "ORGAN_FAKE_REMOTE_STATUS=$valid_remote_unknown_error" ORGAN_FAKE_REMOTE_STATUS_RC=0 -- "$remote_script"
assert_smoke_rejects_env 'local success envelope with rc64' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "ORGAN_FAKE_LOCAL_STATUS=$valid_local_status" ORGAN_FAKE_LOCAL_STATUS_RC=64 -- "$local_script"
assert_smoke_rejects_env 'remote success envelope with rc64' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "ORGAN_FAKE_REMOTE_STATUS=$valid_remote_status" ORGAN_FAKE_REMOTE_STATUS_RC=64 -- "$remote_script"
assert_smoke_rejects_env 'local unknown envelope with unexpected rc65' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "ORGAN_FAKE_LOCAL_STATUS=$valid_local_unknown_error" ORGAN_FAKE_LOCAL_STATUS_RC=65 -- "$local_script"
assert_smoke_rejects_env 'remote unknown envelope with unexpected rc65' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "ORGAN_FAKE_REMOTE_STATUS=$valid_remote_unknown_error" ORGAN_FAKE_REMOTE_STATUS_RC=65 -- "$remote_script"
assert_smoke_rejects_env 'local command stderr' ORGAN_LOCAL_SMOKE_OK \
  'list --json' \
  ORGAN_FAKE_STDERR='synthetic diagnostic' -- "$local_script"
assert_smoke_rejects_env 'remote command stderr' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  ORGAN_FAKE_STDERR='synthetic diagnostic' -- "$remote_script"

assert_canary_rejects_override 'canary claim duplicate data key' ORGAN_FAKE_CLAIM_RESPONSE \
  "$duplicate_claim_data" $'list --json\nstatus claude-onp --json\nread claude-onp --json\nclaim claude-onp --json\nrelease claude-onp --json'
assert_canary_rejects_override 'canary ask duplicate data key' ORGAN_FAKE_ASK_RESPONSE \
  "$duplicate_ask_data" $'list --json\nstatus claude-onp --json\nread claude-onp --json\nclaim claude-onp --json\nask claude-onp --stdin --json\nrelease claude-onp --json'
assert_canary_rejects_override 'canary release duplicate data key' ORGAN_FAKE_RELEASE_RESPONSE \
  "$duplicate_release_data" $'list --json\nstatus claude-onp --json\nread claude-onp --json\nclaim claude-onp --json\nask claude-onp --stdin --json\nread claude-onp --json\nrelease claude-onp --json\nrelease claude-onp --json'
assert_canary_rejects_override 'canary post-release nested escaped duplicate key' \
  ORGAN_FAKE_POST_RELEASE_ASK_RESPONSE "$duplicate_post_release_error_escaped" \
  $'list --json\nstatus claude-onp --json\nread claude-onp --json\nclaim claude-onp --json\nask claude-onp --stdin --json\nread claude-onp --json\nrelease claude-onp --json\nask claude-onp --stdin --json'

archive_root="$TEST_TMP/archive-layout"
archive_entry="$TEST_TMP/archive-entry"
mkdir -p -- "$archive_root/scripts" "$archive_root/lib/organ" "$archive_entry"
cp -- "$local_script" "$archive_root/scripts/smoke-local.sh"
cp -- "$remote_script" "$archive_root/scripts/smoke-remote.sh"
cp -- "$REPO_ROOT/lib/organ/common.sh" "$archive_root/lib/organ/common.sh"
chmod 700 -- "$archive_root/scripts/smoke-local.sh" "$archive_root/scripts/smoke-remote.sh"
ln -s -- "$archive_root/scripts/smoke-local.sh" "$archive_entry/smoke-local.sh"
ln -s -- "$archive_root/scripts/smoke-remote.sh" "$archive_entry/smoke-remote.sh"
archive_local_script="$archive_entry/smoke-local.sh"
archive_remote_script="$archive_entry/smoke-remote.sh"

assert_smoke_accepts_env 'archive symlink local script with valid envelopes' ORGAN_LOCAL_SMOKE_OK \
  $'list --json\nstatus claude-onp --json' \
  "REPO_ROOT=$TEST_TMP/not-the-script-root" -- "$archive_local_script"
assert_smoke_accepts_env 'archive symlink remote script with valid envelope' ORGAN_REMOTE_SMOKE_OK \
  'status remote-managed --json' \
  "REPO_ROOT=$TEST_TMP/not-the-script-root" -- "$archive_remote_script"
assert_smoke_rejects_env 'archive symlink list duplicate data key' ORGAN_LOCAL_SMOKE_OK \
  'list --json' \
  "REPO_ROOT=$TEST_TMP/not-the-script-root" "ORGAN_FAKE_LIST_RESPONSE=$duplicate_list_data" -- \
  "$archive_local_script"

: >"$fake_log"
set +e
malformed_local_output="$(PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" ORGAN_FAKE_LOCAL_STATUS='not-json' "$local_script" 2>&1)"
malformed_local_rc=$?
set -e
[[ "$malformed_local_rc" -ne 0 ]] || {
  printf 'local smoke accepted malformed status JSON: %s\n' "$malformed_local_output" >&2
  exit 1
}
[[ "$malformed_local_output" != *'ORGAN_LOCAL_SMOKE_OK'* ]] || {
  printf 'local smoke printed success for malformed status JSON\n' >&2
  exit 1
}
assert_eq $'list --json\nstatus claude-onp --json' "$(<"$fake_log")"

: >"$fake_log"
set +e
malformed_remote_output="$(PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" ORGAN_FAKE_REMOTE_STATUS='not-json' "$remote_script" 2>&1)"
malformed_remote_rc=$?
set -e
[[ "$malformed_remote_rc" -ne 0 ]] || {
  printf 'remote smoke accepted malformed status JSON: %s\n' "$malformed_remote_output" >&2
  exit 1
}
[[ "$malformed_remote_output" != *'ORGAN_REMOTE_SMOKE_OK'* ]] || {
  printf 'remote smoke printed success for malformed status JSON\n' >&2
  exit 1
}
assert_eq 'status remote-managed --json' "$(<"$fake_log")"

: >"$fake_log"
set +e
noninteractive_output="$(run_smoke "$local_script" --canary 2>&1)"
noninteractive_rc=$?
set -e
assert_eq 64 "$noninteractive_rc"
[[ "$noninteractive_output" == *'canary requires an interactive terminal'* ]] || {
  printf 'canary did not reject noninteractive execution\n' >&2
  exit 1
}
assert_eq $'list --json\nstatus claude-onp --json' "$(<"$fake_log")"

: >"$fake_log"
rm -f -- "$TEST_TMP/state/read-count" "$TEST_TMP/state/released"
set +e
canary_output="$(printf 'YES\n' | PATH="$fake_bin:$PATH" ORGAN_FAKE_LOG="$fake_log" ORGAN_FAKE_STATE="$TEST_TMP/state" script -qefc "$local_script --canary" /dev/null)"
canary_rc=$?
set -e
if [[ "$canary_rc" -ne 0 || "$canary_output" != *'claude-onp'* ||
      "$canary_output" != *'ORGAN_LOCAL_SMOKE_OK'* ]]; then
  record_boundary_failure 'canary ordinary unknown delivery' \
    "expected success with target and summary; got rc=${canary_rc} output=${canary_output}"
fi
expected_canary_log=$'list --json\nstatus claude-onp --json\nread claude-onp --json\nclaim claude-onp --json\nask claude-onp --stdin --json\nread claude-onp --json\nrelease claude-onp --json\nask claude-onp --stdin --json'
if [[ "$(<"$fake_log")" != "$expected_canary_log" ]]; then
  record_boundary_failure 'canary ordinary unknown delivery' "unexpected command log=$(<"$fake_log")"
fi

# Exercise the canary through the production CLI. The only external boundary
# is the hermetic Outsourcerer/tmux pair: the ordinary reply has no receipt and
# therefore returns delivery=unknown, while the subsequent real read exposes
# the exact canary response.
real_bin="$TEST_TMP/real-cli-bin"
real_target_cwd="$TEST_TMP/real-target"
real_config="$TEST_TMP/real-targets.json"
real_state="$TEST_TMP/real-state"
real_tmux="$TEST_TMP/real-tmux"
real_tmux_count="$TEST_TMP/real-tmux-count"
real_tmux_log="$TEST_TMP/real-tmux.log"
real_adapter_log="$TEST_TMP/real-adapter.log"
real_command_log="$TEST_TMP/real-adapter-commands.log"
real_send_log="$TEST_TMP/real-send.log"
mkdir -p -- "$real_bin" "$real_target_cwd"
ln -s -- "$REPO_ROOT/bin/organ" "$real_bin/organ"
ln -s -- "$fake_bin/tmux" "$real_bin/tmux"
ln -s -- "$fake_bin/claude" "$real_bin/claude"
jq -cn --arg cwd "$real_target_cwd" '{schema_version:"1",targets:[
  {alias:"claude-onp",transport:"local",host:"local",cwd:$cwd,mode:"adopted",tmux_target:"tmux:1.3",claude_session_id:null}
]}' >"$real_config"
cat >"$real_tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q\0' "$@" >>"${ORGAN_REAL_SMOKE_TMUX_LOG:?}"
count=0
[[ ! -f "${ORGAN_REAL_SMOKE_TMUX_COUNT:?}" ]] || count="$(<"$ORGAN_REAL_SMOKE_TMUX_COUNT")"
count=$((count + 1))
printf '%s\n' "$count" >"$ORGAN_REAL_SMOKE_TMUX_COUNT"
case "$count" in
  1|2) printf '❯\n' ;;
  3) printf '%s\n' "${ORGAN_REAL_SMOKE_COMPOSER_OUTPUT:-❯}" ;;
  *)
    if [[ "${ORGAN_REAL_SMOKE_READ_FAIL:-0}" == 1 ]]; then
      exit 1
    fi
    printf '%s\n' "${ORGAN_REAL_SMOKE_RESPONSE:-ORGANOUN_LOCAL_CANARY_OK}"
    ;;
esac
EOF
chmod 700 -- "$real_tmux"

reset_real_canary() {
  rm -rf -- "$real_state"
  mkdir -p -- "$real_state"
  rm -f -- "$real_tmux_count"
  : >"$real_tmux_log"
  : >"$real_adapter_log"
  : >"$real_command_log"
  : >"$real_send_log"
}

run_real_canary() {
  local -a env_specs=("$@")
  printf 'YES\n' | env \
    PATH="$real_bin:$PATH" \
    ORGAN_CONFIG="$real_config" \
    ORGAN_STATE_HOME="$real_state" \
    ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh" \
    ORGAN_TMUX="$real_tmux" \
    ORGAN_FAKE_LOG="$real_adapter_log" \
    ORGAN_FAKE_COMMAND_LOG="$real_command_log" \
    ORGAN_FAKE_SEND_LOG="$real_send_log" \
    ORGAN_REAL_SMOKE_TMUX_LOG="$real_tmux_log" \
    ORGAN_REAL_SMOKE_TMUX_COUNT="$real_tmux_count" \
    "${env_specs[@]}" \
    script -qefc "$local_script --canary" /dev/null
}

reset_real_canary
set +e
real_canary_output="$(run_real_canary)"
real_canary_rc=$?
set -e
if [[ "$real_canary_rc" -ne 0 || "$real_canary_output" != *'ORGAN_LOCAL_SMOKE_OK'* ]]; then
  printf 'real CLI canary did not accept ordinary unknown delivery: rc=%s output=%s\n' \
    "$real_canary_rc" "$real_canary_output" >&2
  exit 1
fi
if [[ "$real_canary_output" == *'schema_version'* ||
      "$real_canary_output" == *'secret-claim-token'* ||
      "$real_canary_output" == *'ORGANOUN_LOCAL_CANARY_OK"'* ]]; then
  printf 'real CLI canary leaked a JSON envelope, claim token, or transcript\n' >&2
  exit 1
fi
assert_eq $'session claim claude-onp tmux:1.3\nsession reply claude-onp Responda exatamente ORGANOUN_LOCAL_CANARY_OK\nsession release claude-onp' "$(<"$real_command_log")"
assert_eq 1 "$(wc -l <"$real_send_log")"
assert_eq 4 "$(<"$real_tmux_count")"
assert_not_exists "$real_state/claims/claude-onp.json"
if grep -Fq 'session stop' "$real_command_log"; then
  printf 'local canary stopped an adopted session\n' >&2
  exit 1
fi

# Every failure after claim gets one bounded release attempt. None may replay
# the ask, print success, or retain the private claim record.
for failure_kind in ask-blocked read-failed response-mismatch; do
  reset_real_canary
  failure_env=()
  case "$failure_kind" in
    ask-blocked) failure_env+=(ORGAN_REAL_SMOKE_COMPOSER_OUTPUT=busy) ;;
    read-failed) failure_env+=(ORGAN_REAL_SMOKE_READ_FAIL=1) ;;
    response-mismatch) failure_env+=(ORGAN_REAL_SMOKE_RESPONSE=WRONG_RESPONSE) ;;
  esac
  set +e
  failure_output="$(run_real_canary "${failure_env[@]}" 2>&1)"
  failure_rc=$?
  set -e
  [[ "$failure_rc" -ne 0 && "$failure_output" != *'ORGAN_LOCAL_SMOKE_OK'* ]] || {
    printf 'real CLI canary accepted %s: rc=%s output=%s\n' "$failure_kind" "$failure_rc" "$failure_output" >&2
    exit 1
  }
  assert_eq 1 "$(grep -c '^session reply ' "$real_command_log")"
  assert_eq 1 "$(grep -c '^session release ' "$real_command_log")"
  if grep -Fq 'session stop' "$real_command_log"; then
    printf 'failed local canary stopped an adopted session: %s\n' "$failure_kind" >&2
    exit 1
  fi
  assert_not_exists "$real_state/claims/claude-onp.json"
done

if (( hostile_failures > 0 || boundary_failures > 0 )); then
  printf 'smoke envelope regression failures: %s\n' "$hostile_failures" >&2
  printf 'smoke JSON-boundary regression failures: %s\n' "$boundary_failures" >&2
  exit 1
fi

printf 'test_smoke PASS\n'
