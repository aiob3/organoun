#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: stdin NUL or malformed UTF-8 crosses a local/SSH/final-hop
# adapter boundary, Bash silently drops bytes while constructing argv, a job is
# created for rejected text, or the exact 16-KiB UTF-8 boundary is refused or
# changed (including its trailing newline).
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
local_cwd="$TEST_TMP/local-cwd"
remote_cwd="$TEST_TMP/remote-cwd"
mkdir -p -- "$local_cwd" "$remote_cwd"
config="$TEST_TMP/targets.json"
jq -cn --arg local_cwd "$local_cwd" --arg remote_cwd "$remote_cwd" '{schema_version:"1",targets:[
  {alias:"local-adopted",transport:"local",host:"local",cwd:$local_cwd,mode:"adopted",tmux_target:"local:1.1",claude_session_id:null},
  {alias:"local-managed",transport:"local",host:"local",cwd:$local_cwd,mode:"managed",provider:"cc",session_name:"organoun-local-text",model:null},
  {alias:"remote-adopted",transport:"ssh",host:"remote.example",cwd:$remote_cwd,mode:"adopted",tmux_target:"remote:1.1",claude_session_id:null},
  {alias:"remote-managed",transport:"ssh",host:"remote.example",cwd:$remote_cwd,mode:"managed",provider:"cc",session_name:"organoun-remote-text",model:null}
]}' >"$config"

nul_payload="$TEST_TMP/nul-payload"
invalid_payload="$TEST_TMP/invalid-payload"
boundary_payload="$TEST_TMP/boundary-payload"
printf 'before\0after' >"$nul_payload"
printf 'before\377after' >"$invalid_payload"
head -c 16381 /dev/zero | tr '\0' a >"$boundary_payload"
printf 'é\n' >>"$boundary_payload"
assert_eq 16384 "$(wc -c <"$boundary_payload")"
iconv -f UTF-8 -t UTF-8 "$boundary_payload" >/dev/null

assert_text_failure() {
  local expected_action="$1"
  local expected_code="$2"
  local expected_rc="$3"
  local actual="$4"
  local actual_rc="$5"

  assert_eq "$expected_rc" "$actual_rc"
  jq -e -s --arg action "$expected_action" --arg code "$expected_code" '
    length == 1 and .[0].schema_version == "1" and .[0].ok == false and
    .[0].action == $action and .[0].error.code == $code and
    (.[0] | has("data") | not)
  ' <<<"$actual" >/dev/null
}

export ORGAN_CONFIG="$config"
export ORGAN_STATE_HOME="$TEST_TMP/local-state"
export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_PROC_ROOT="$TEST_TMP/local-proc"
export ORGAN_SESSION_POLL_INTERVAL=0
export ORGAN_FAKE_LOG="$TEST_TMP/local-osrc.log"
export ORGAN_FAKE_COMMAND_LOG="$TEST_TMP/local-command.log"
export ORGAN_FAKE_SEND_LOG="$TEST_TMP/local-send.log"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/local-tmux.log"
export ORGAN_FAKE_TMUX_STATE_FILE="$TEST_TMP/local-tmux-state.json"
export ORGAN_FAKE_TMUX_OUTPUT='❯'
export ORGAN_FAKE_PAYLOAD_FILE="$TEST_TMP/local-delivered"
export ORGAN_FAKE_PANE_ID='%82'
export ORGAN_FAKE_PANE_PID=8282
export ORGAN_FAKE_PID_START=982
mkdir -p -- "$ORGAN_PROC_ROOT"
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_COMMAND_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
jq -cn '{exists:false}' >"$ORGAN_FAKE_TMUX_STATE_FILE"

"$REPO_ROOT/bin/organ" claim local-adopted --json >/dev/null
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_COMMAND_LOG"

for payload_kind in nul invalid-utf8; do
  if [[ "$payload_kind" == nul ]]; then
    payload_file="$nul_payload"
  else
    payload_file="$invalid_payload"
  fi

  set +e
  actual="$("$REPO_ROOT/bin/organ" ask local-adopted --stdin --json <"$payload_file" 2>&1)"
  rc=$?
  set -e
  assert_text_failure ask ASK_INVALID_TEXT 64 "$actual" "$rc"
  [[ ! -s "$ORGAN_FAKE_LOG" && ! -s "$ORGAN_FAKE_COMMAND_LOG" ]] || {
    printf 'invalid local ask reached the adapter: %s\n' "$payload_kind" >&2
    exit 1
  }

  set +e
  actual="$("$REPO_ROOT/bin/organ" dispatch local-managed --mode read --stdin --json <"$payload_file" 2>&1)"
  rc=$?
  set -e
  assert_text_failure dispatch DISPATCH_INVALID_TEXT 64 "$actual" "$rc"
  [[ ! -s "$ORGAN_FAKE_LOG" && ! -s "$ORGAN_FAKE_COMMAND_LOG" ]] || {
    printf 'invalid local dispatch reached the adapter: %s\n' "$payload_kind" >&2
    exit 1
  }
  [[ ! -d "$ORGAN_STATE_HOME/jobs" && ! -d "$ORGAN_STATE_HOME/sessions" ]] || {
    printf 'invalid local dispatch created managed state: %s\n' "$payload_kind" >&2
    exit 1
  }
done

rm -f -- "$ORGAN_FAKE_PAYLOAD_FILE"
boundary_ask="$("$REPO_ROOT/bin/organ" ask local-adopted --stdin --json <"$boundary_payload")"
assert_jq "$boundary_ask" '.ok == true and .delivery == "unknown"'
cmp -- "$boundary_payload" "$ORGAN_FAKE_PAYLOAD_FILE"

rm -f -- "$ORGAN_FAKE_PAYLOAD_FILE"
boundary_dispatch="$("$REPO_ROOT/bin/organ" dispatch local-managed --mode read --stdin --json <"$boundary_payload")"
assert_jq "$boundary_dispatch" '.ok == true and .delivery == "unknown" and (.data.job_id | startswith("local.job-"))'
cmp -- "$boundary_payload" "$ORGAN_FAKE_PAYLOAD_FILE"

# The CLI must reject the same invalid bytes before opening SSH.
counting_ssh="$TEST_TMP/counting-ssh"
ssh_called="$TEST_TMP/ssh-called"
cat >"$counting_ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: >"${ORGAN_TEXT_TEST_SSH_CALLED:?}"
exit 70
EOF
chmod 700 -- "$counting_ssh"
export ORGAN_SSH="$counting_ssh"
export ORGAN_TEXT_TEST_SSH_CALLED="$ssh_called"
for payload_kind in nul invalid-utf8; do
  if [[ "$payload_kind" == nul ]]; then
    payload_file="$nul_payload"
  else
    payload_file="$invalid_payload"
  fi
  rm -f -- "$ssh_called"
  set +e
  actual="$("$REPO_ROOT/bin/organ" ask remote-adopted --stdin --json <"$payload_file" 2>&1)"
  rc=$?
  set -e
  assert_text_failure ask ASK_INVALID_TEXT 64 "$actual" "$rc"
  assert_not_exists "$ssh_called"

  set +e
  actual="$("$REPO_ROOT/bin/organ" dispatch remote-managed --mode read --stdin --json <"$payload_file" 2>&1)"
  rc=$?
  set -e
  assert_text_failure dispatch DISPATCH_INVALID_TEXT 64 "$actual" "$rc"
  assert_not_exists "$ssh_called"
done
unset ORGAN_SSH ORGAN_TEXT_TEST_SSH_CALLED

# Exercise the installed remote helper directly. A JSON \u0000 decodes to NUL
# at its private payload file, and malformed raw UTF-8 is rejected by the strict
# request normalizer. Neither may reach the final local adapter.
remote_state="$TEST_TMP/remote-state"
remote_osrc_log="$TEST_TMP/remote-osrc.log"
remote_command_log="$TEST_TMP/remote-command.log"
remote_send_log="$TEST_TMP/remote-send.log"
remote_tmux_log="$TEST_TMP/remote-tmux.log"
remote_tmux_state="$TEST_TMP/remote-tmux-state.json"
remote_proc="$TEST_TMP/remote-proc"
remote_delivered="$TEST_TMP/remote-delivered"
mkdir -p -- "$remote_proc"
: >"$remote_osrc_log"
: >"$remote_command_log"
: >"$remote_send_log"
: >"$remote_tmux_log"
jq -cn '{exists:false}' >"$remote_tmux_state"
remote_env=(
  ORGAN_CONFIG="$config"
  ORGAN_STATE_HOME="$remote_state"
  ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
  ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
  ORGAN_PROC_ROOT="$remote_proc"
  ORGAN_SESSION_POLL_INTERVAL=0
  ORGAN_FAKE_LOG="$remote_osrc_log"
  ORGAN_FAKE_COMMAND_LOG="$remote_command_log"
  ORGAN_FAKE_SEND_LOG="$remote_send_log"
  ORGAN_FAKE_TMUX_LOG="$remote_tmux_log"
  ORGAN_FAKE_TMUX_STATE_FILE="$remote_tmux_state"
  ORGAN_FAKE_TMUX_OUTPUT='❯'
  ORGAN_FAKE_PAYLOAD_FILE="$remote_delivered"
  ORGAN_FAKE_PANE_ID='%83'
  ORGAN_FAKE_PANE_PID=8383
  ORGAN_FAKE_PID_START=983
)

claim_request="$TEST_TMP/remote-claim.json"
jq -cn '{schema_version:"1",action:"claim",alias:"remote-adopted",options:{},payload:""}' >"$claim_request"
remote_claim="$(env "${remote_env[@]}" "$REPO_ROOT/remote/organ-remote" <"$claim_request")"
assert_jq "$remote_claim" '.ok == true and .delivery == "confirmed"'
: >"$remote_osrc_log"
: >"$remote_command_log"

for action in ask dispatch; do
  if [[ "$action" == ask ]]; then
    alias=remote-adopted
    options='{}'
  else
    alias=remote-managed
    options='{"mode":"read"}'
  fi
  for payload_kind in nul invalid-utf8; do
    request_file="$TEST_TMP/remote-$action-$payload_kind.json"
    if [[ "$payload_kind" == nul ]]; then
      printf '{"schema_version":"1","action":"%s","alias":"%s","options":%s,"payload":"before\\u0000after"}\n' \
        "$action" "$alias" "$options" >"$request_file"
      expected_public_action="$action"
    else
      printf '{"schema_version":"1","action":"%s","alias":"%s","options":%s,"payload":"before\377after"}\n' \
        "$action" "$alias" "$options" >"$request_file"
      expected_public_action=unknown
    fi
    set +e
    actual="$(env "${remote_env[@]}" "$REPO_ROOT/remote/organ-remote" <"$request_file" 2>&1)"
    rc=$?
    set -e
    assert_text_failure "$expected_public_action" REMOTE_REQUEST_INVALID 64 "$actual" "$rc"
    [[ ! -s "$remote_osrc_log" && ! -s "$remote_command_log" ]] || {
      printf 'invalid remote-helper %s reached the adapter: %s\n' "$action" "$payload_kind" >&2
      exit 1
    }
    [[ ! -d "$remote_state/jobs" && ! -d "$remote_state/sessions" ]] || {
      printf 'invalid remote-helper dispatch created managed state: %s\n' "$payload_kind" >&2
      exit 1
    }
  done
done

remote_ask_request="$TEST_TMP/remote-ask-boundary.json"
jq -cn --rawfile payload "$boundary_payload" \
  '{schema_version:"1",action:"ask",alias:"remote-adopted",options:{},payload:$payload}' >"$remote_ask_request"
rm -f -- "$remote_delivered"
remote_boundary_ask="$(env "${remote_env[@]}" "$REPO_ROOT/remote/organ-remote" <"$remote_ask_request")"
assert_jq "$remote_boundary_ask" '.ok == true and .delivery == "unknown"'
cmp -- "$boundary_payload" "$remote_delivered"

remote_dispatch_request="$TEST_TMP/remote-dispatch-boundary.json"
jq -cn --rawfile payload "$boundary_payload" \
  '{schema_version:"1",action:"dispatch",alias:"remote-managed",options:{mode:"read"},payload:$payload}' >"$remote_dispatch_request"
rm -f -- "$remote_delivered"
remote_boundary_dispatch="$(env "${remote_env[@]}" "$REPO_ROOT/remote/organ-remote" <"$remote_dispatch_request")"
assert_jq "$remote_boundary_dispatch" '.ok == true and .delivery == "unknown" and (.data.job_id | startswith("remote.job-"))'
cmp -- "$boundary_payload" "$remote_delivered"

printf 'payload text tests passed\n'
