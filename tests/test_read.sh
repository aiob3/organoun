#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: session/pane observations expose credentials or claim tokens,
# ignore a session ID, select a non-configured pane, miscount a terminal newline,
# or use a local adapter for managed/SSH targets that must fail closed.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
cwd="$TEST_TMP/target-cwd"
mkdir -p -- "$cwd"
config="$TEST_TMP/targets.json"
jq -cn --arg cwd "$cwd" '
  {schema_version:"1",targets:[
    {alias:"linked",transport:"local",host:"local",cwd:$cwd,mode:"adopted",tmux_target:"ignored:9",claude_session_id:"cc-1"},
    {alias:"fallback",transport:"local",host:"local",cwd:$cwd,mode:"adopted",tmux_target:"only-this-pane.4",claude_session_id:null},
    {alias:"managed",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-managed"},
    {alias:"remote",transport:"ssh",host:"remote.example",cwd:"/srv/organoun",mode:"managed",provider:"cc",session_name:"organoun-remote"}
  ]}' >"$config"

export ORGAN_CONFIG="$config"
export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_FAKE_LOG="$TEST_TMP/outsourcerer.log"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/tmux.log"
export ORGAN_FAKE_CWD_LOG="$TEST_TMP/outsourcerer-cwd.log"
export ORGAN_FAKE_TMUX_CWD_LOG="$TEST_TMP/tmux-cwd.log"
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
: >"$ORGAN_FAKE_CWD_LOG"
: >"$ORGAN_FAKE_TMUX_CWD_LOG"

export ORGAN_FAKE_FLEET_SHOW_OUTPUT='{"session_id":"cc-1","state":"idle","claim_token":"claim-secret-token-012345","api_key":"sk-test-credential-987654"}'
actual="$("$REPO_ROOT/bin/organ" read linked --json)"
assert_jq "$actual" '.ok == true and .state == "idle" and .data.excerpt == "state: idle" and .data.truncated == false'
assert_jq "$actual" 'tostring | contains("claim-secret-token-012345") | not'
assert_jq "$actual" 'tostring | contains("sk-test-credential-987654") | not'
assert_eq 'fleet show cc-1 --json ' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq "$cwd" "$(head -n 1 "$ORGAN_FAKE_CWD_LOG")"

actual="$("$REPO_ROOT/bin/organ" status linked --json)"
assert_jq "$actual" '.ok == true and .state == "idle" and .data == {}'

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
export ORGAN_FAKE_TMUX_OUTPUT='claim token: claim-secret-token-012345 API_KEY=sk-test-credential-987654 prompt: preserve this private instruction'
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
assert_jq "$actual" '.ok == true and .state == "unknown" and .data.excerpt == "claim token: [REDACTED] API_KEY=[REDACTED] prompt: [REDACTED]\n" and .data.truncated == false'
assert_jq "$actual" 'tostring | contains("claim-secret-token-012345") | not'
assert_jq "$actual" 'tostring | contains("sk-test-credential-987654") | not'
assert_jq "$actual" 'tostring | contains("preserve this private instruction") | not'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq 'capture-pane -p -t only-this-pane.4 -S -120 ' "$(tr '\0' ' ' <"$ORGAN_FAKE_TMUX_LOG")"
assert_eq "$cwd" "$(head -n 1 "$ORGAN_FAKE_TMUX_CWD_LOG")"

# Public pane excerpts must redact concrete HTTP authentication and credential
# header boundaries regardless of case, while retaining the non-secret labels.
credential_output="$TEST_TMP/credential-pane.txt"
printf '%s\n' \
  'BEARER opaquecredential987654' \
  'bAsIc standalonebasiccredential987654' \
  'AUTHORIZATION: Basic dXNlcjpwYXNz' \
  'proxy-authorization: bearer proxycredential987654' \
  'Cookie: session=cookiecredential987654; theme=dark' \
  'set-cookie: auth=setcookiecredential987654; Path=/; HttpOnly' \
  'X-API-Key: headercredential987654' \
  'x-auth-token: authtokencredential987654' \
  'token: lower-token-credential-987654' \
  'password=lower-password-credential-987654' >"$credential_output"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$credential_output"
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
assert_jq "$actual" '
  .ok == true and .data.truncated == false and
  (.data.excerpt | contains("BEARER [REDACTED]")) and
  (.data.excerpt | contains("bAsIc [REDACTED]")) and
  (.data.excerpt | contains("AUTHORIZATION: [REDACTED]")) and
  (.data.excerpt | contains("proxy-authorization: [REDACTED]")) and
  (.data.excerpt | contains("Cookie: [REDACTED]")) and
  (.data.excerpt | contains("set-cookie: [REDACTED]")) and
  (.data.excerpt | contains("X-API-Key: [REDACTED]")) and
  (.data.excerpt | contains("x-auth-token: [REDACTED]")) and
  (.data.excerpt | contains("token: [REDACTED]")) and
  (.data.excerpt | contains("password=[REDACTED]"))
'
for leaked_credential in \
  opaquecredential987654 standalonebasiccredential987654 dXNlcjpwYXNz proxycredential987654 \
  cookiecredential987654 setcookiecredential987654 headercredential987654 \
  authtokencredential987654 lower-token-credential-987654 \
  lower-password-credential-987654; do
  if grep -Fq -- "$leaked_credential" <<<"$actual"; then
    printf 'public read leaked credential: %s\n' "$leaked_credential" >&2
    exit 1
  fi
done

exact_output="$TEST_TMP/exact-pane.txt"
head -c 65536 /dev/zero | tr '\0' x >"$exact_output"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$exact_output"
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
assert_jq "$actual" '.data.truncated == false and (.data.excerpt | length) == 65536'

printf '\n' >>"$exact_output"
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
assert_jq "$actual" '.data.truncated == true and (.data.excerpt | length) == 65536 and (.data.excerpt | endswith("\n"))'

cross_boundary_output="$TEST_TMP/cross-boundary-pane.txt"
printf '%s' 'xclaim token: claim-secret-token-012345' >"$cross_boundary_output"
head -c 65506 /dev/zero | tr '\0' x >>"$cross_boundary_output"
assert_eq "65545" "$(wc -c <"$cross_boundary_output")"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$cross_boundary_output"
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
assert_jq "$actual" 'tostring | contains("claim-secret-token-012345") | not'

redacted_boundary_output="$TEST_TMP/redacted-boundary-pane.txt"
printf '%s' 'prompt: ' >"$redacted_boundary_output"
head -c 65528 /dev/zero | tr '\0' x >>"$redacted_boundary_output"
printf '\n' >>"$redacted_boundary_output"
assert_eq "65537" "$(wc -c <"$redacted_boundary_output")"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$redacted_boundary_output"
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
assert_jq "$actual" '.data.truncated == true and .data.excerpt == "prompt: [REDACTED]\n"'

capture_tmp="$TEST_TMP/private-capture"
capture_size_file="$TEST_TMP/private-capture-size"
capture_stop="$TEST_TMP/private-capture-stop"
mkdir -p -- "$capture_tmp"
private_capture_max=69632
watch_private_capture() {
  local path size max_seen=0
  while [[ ! -e "$capture_stop" ]]; do
    for path in "$capture_tmp"/organoun-*; do
      [[ -f "$path" ]] || continue
      if ! size="$(stat -c %s -- "$path" 2>/dev/null)"; then
        continue
      fi
      if (( size > max_seen )); then
        max_seen="$size"
      fi
    done
  done
  printf '%s\n' "$max_seen" >"$capture_size_file"
}
large_output="$TEST_TMP/large-pane.txt"
head -c 1048576 /dev/zero | tr '\0' x >"$large_output"
export TMPDIR="$capture_tmp"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$large_output"
export ORGAN_FAKE_TMUX_CHUNK_BYTES=4096
export ORGAN_FAKE_TMUX_CHUNK_DELAY=0.002
watch_private_capture &
watcher_pid=$!
actual="$("$REPO_ROOT/bin/organ" read fallback --json)"
touch "$capture_stop"
wait "$watcher_pid"
max_seen="$(<"$capture_size_file")"
(( max_seen <= private_capture_max )) || {
  printf 'private capture exceeded %s bytes: %s\n' "$private_capture_max" "$max_seen" >&2
  exit 1
}
assert_jq "$actual" '.data.truncated == true and .data.excerpt == "[output omitted: exceeds private read limit]"'

unset ORGAN_FAKE_TMUX_OUTPUT_FILE
unset ORGAN_FAKE_TMUX_CHUNK_BYTES
unset ORGAN_FAKE_TMUX_CHUNK_DELAY
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
set +e
actual="$("$REPO_ROOT/bin/organ" read managed --json 2>&1)"
rc=$?
set -e
assert_eq "64" "$rc"
assert_jq "$actual" '.error.code == "MANAGED_READ_UNAVAILABLE"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_TMUX_LOG")"

export ORGAN_SSH=/bin/false
set +e
actual="$("$REPO_ROOT/bin/organ" read remote --json 2>&1)"
rc=$?
set -e
unset ORGAN_SSH
assert_eq "69" "$rc"
assert_jq "$actual" '.state == "unreachable" and .error.code == "REMOTE_UNREACHABLE"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_TMUX_LOG")"
