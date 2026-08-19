#!/usr/bin/env bash
set -euo pipefail

# Break caught: Organoun accepts effects without first binding the exact local,
# operator-visible tmux owner pane that is allowed to originate dispatch.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env

control_config="$TEST_TMP/targets.json"
jq '(.targets[] | select(.alias == "remote-managed") | .cwd) = "/workspace/remote"' \
  "$REPO_ROOT/tests/fixtures/targets.json" >"$control_config"

tmux_state="$TEST_TMP/tmux-state.json"
tmux_log="$TEST_TMP/tmux.log"
: >"$tmux_log"
jq -cn '{
  session_id:"$1",
  session_name:"organoun-test",
  window_id:"@1",
  window_index:"0",
  window_zoomed_flag:0,
  window_layout:"layout-a",
  owner_pane:{id:"%1",pid:41001,cwd:"/workspace/project"},
  respawn_pid:42002,
  next_pane:{id:"%2",index:"1",pid:41002,dead:0,current_command:"bash",cwd:"/workspace/project",output:""},
  panes:[{id:"%1",index:"0",pid:41001,dead:0,current_command:"bash",cwd:"/workspace/project",output:"owner"}],
  clients:[{session_id:"$1",window_id:"@1",tty:"/dev/pts/9",control_mode:0,readonly:0}]
}' >"$tmux_state"

export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-control-tmux.sh"
export ORGAN_FAKE_CONTROL_TMUX_STATE="$tmux_state"
export ORGAN_FAKE_CONTROL_TMUX_LOG="$tmux_log"
export ORGAN_STATE_HOME="$XDG_STATE_HOME/organoun"
export ORGAN_CONFIG="$control_config"
export ORGAN_SSH=/bin/false
export TMUX='/tmp/tmux-test/default,41000,0'
export TMUX_PANE='%1'

set +e
output="$("$REPO_ROOT/bin/organ" init --json)"
init_rc=$?
set -e
assert_eq 0 "$init_rc"
# shellcheck disable=SC2016
assert_jq "$output" '
  .schema_version == "1"
  and .ok == true
  and .action == "init"
  and .state == "initialized"
  and .delivery == "not-applicable"
  and (.data.owner_id | test("^owner-[0-9a-f]{16}$"))
  and .data.session_id == "$1"
  and .data.window_id == "@1"
  and .data.pane_id == "%1"
  and .data.operator_client_id == "/dev/pts/9"'

owner_record="$ORGAN_STATE_HOME/control/owner.json"
[[ -f "$owner_record" && ! -L "$owner_record" ]] || {
  printf 'owner receipt was not created safely\n' >&2
  exit 1
}
assert_mode 700 "$ORGAN_STATE_HOME"
assert_mode 700 "$ORGAN_STATE_HOME/control"
assert_mode 600 "$owner_record"
# shellcheck disable=SC2016
assert_jq "$(<"$owner_record")" '
  .schema_version == "1"
  and .owner_id == ("owner-" + .identity_digest[0:16])
  and .session_id == "$1"
  and .window_id == "@1"
  and .pane_id == "%1"
  and .pane_pid == 41001
  and .operator_client_id == "/dev/pts/9"'

# Reserving layout may create only a local, visible, empty pane. It must not
# start Claude, SSH, a helper, or any endpoint-side process.
set +e
reserve_output="$("$REPO_ROOT/bin/organ" reserve remote-managed --json)"
reserve_rc=$?
set -e
assert_eq 0 "$reserve_rc"
# shellcheck disable=SC2016
assert_jq "$reserve_output" '
  .ok == true
  and .action == "reserve"
  and .target == "remote-managed"
  and .host == "remote.example"
  and .state == "reserved"
  and .data.pane_id == "%2"
  and (.data.operation_id | test("^op-[0-9a-f]{16}$"))
  and (.data.attestation_nonce | test("^[0-9a-f]{32}$"))
  and (.data.layout_digest | test("^[0-9a-f]{64}$"))'

pane_record="$ORGAN_STATE_HOME/control/panes/remote-managed.json"
assert_mode 700 "$ORGAN_STATE_HOME/control/panes"
assert_mode 600 "$pane_record"
# shellcheck disable=SC2016
assert_jq "$(<"$pane_record")" '
  .schema_version == "1"
  and .alias == "remote-managed"
  and .owner_id == ("owner-" + .owner_identity_digest[0:16])
  and .transport == "ssh"
  and .host == "remote.example"
  and .endpoint_cwd == "/workspace/remote"
  and .pane_id == "%2"
  and .pane_pid == 41002
  and .state == "reserved"
  and .pending_action == "session.enter"'
assert_jq "$(<"$tmux_state")" '
  (.panes | length) == 2
  and (.panes[] | select(.id == "%2") | .current_command) == "bash"'
tmux_calls="$(tr '\0' '\n' <"$tmux_log")"
[[ "$tmux_calls" == *split-window* ]] || { printf 'reserve did not split the owner window\n' >&2; exit 1; }
for forbidden in respawn-pane ssh claude organ-remote; do
  [[ "$tmux_calls" != *"$forbidden"* ]] || {
    printf 'reserve caused forbidden endpoint effect: %s\n' "$forbidden" >&2
    exit 1
  }
done

# Entering the endpoint must consume the operator-visible nonce exactly once
# and may affect only the pane reserved above. For SSH targets the remote side
# receives only cwd + Claude; it never receives Organoun, tmux, or a helper.
attestation_nonce="$(jq -r '.data.attestation_nonce' <<<"$reserve_output")"
wrong_nonce='00000000000000000000000000000000'
set +e
wrong_enter_output="$("$REPO_ROOT/bin/organ" enter remote-managed --attest "$wrong_nonce" --json)"
wrong_enter_rc=$?
set -e
assert_eq 64 "$wrong_enter_rc"
assert_jq "$wrong_enter_output" '.ok == false and .error.code == "OPERATOR_ATTESTATION_INVALID"'
assert_jq "$(<"$tmux_state")" '(.panes[] | select(.id == "%2") | .current_command) == "bash"'

set +e
enter_output="$("$REPO_ROOT/bin/organ" enter remote-managed --attest "$attestation_nonce" --json)"
enter_rc=$?
set -e
assert_eq 0 "$enter_rc"
# shellcheck disable=SC2016
assert_jq "$enter_output" '
  .ok == true
  and .action == "enter"
  and .target == "remote-managed"
  and .host == "remote.example"
  and .state == "entered"
  and .delivery == "not-applicable"
  and .data.pane_id == "%2"
  and .data.transport == "ssh"
  and .data.endpoint_cwd == "/workspace/remote"'
assert_jq "$(<"$pane_record")" '
  .state == "entered"
  and .pending_action == null
  and .attestation_nonce == null
  and .pane_id == "%2"
  and .pane_pid == 42002'
assert_jq "$(<"$tmux_state")" '
  (.panes[] | select(.id == "%2") | .current_command) == "ssh"
  and .last_respawn.target == "%2"
  and .last_respawn.cwd == "/workspace/project"
  and .last_respawn.command == "exec ssh -tt -- remote.example '\''unset CLAUDE_MODEL ANTHROPIC_MODEL && cd -- /workspace/remote && exec claude'\''"'

set +e
replay_output="$("$REPO_ROOT/bin/organ" enter remote-managed --attest "$attestation_nonce" --json)"
replay_rc=$?
set -e
assert_eq 64 "$replay_rc"
assert_jq "$replay_output" '.ok == false and .error.code == "OPERATOR_ATTESTATION_INVALID"'
respawn_calls="$(tr '\0' '\n' <"$tmux_log" | grep -c '^respawn-pane$' || true)"
assert_eq 1 "$respawn_calls"

# Once entered, observation and messaging remain local to the visible pane.
# A remote control/helper route must never be consulted, and a delivery-unknown
# send is an attempted obligation that cannot be replayed.
tmux_stage="${tmux_state}.output"
jq '(.panes[] | select(.id == "%2") | .output) = "Claude ready\n❯"' \
  "$tmux_state" >"$tmux_stage"
mv -f -- "$tmux_stage" "$tmux_state"

set +e
read_output="$("$REPO_ROOT/bin/organ" read remote-managed --json)"
read_rc=$?
set -e
assert_eq 0 "$read_rc"
assert_jq "$read_output" '.ok == true and .action == "read" and .host == "remote.example" and (.data.excerpt | contains("Claude ready"))'

export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_FAKE_LOG="$TEST_TMP/outsourcerer.log"
export ORGAN_FAKE_ENV_LOG="$TEST_TMP/outsourcerer-env.log"
export ORGAN_FAKE_SEND_LOG="$TEST_TMP/send.log"
export ORGAN_FAKE_PAYLOAD_FILE="$TEST_TMP/payload.txt"
export ORGAN_FAKE_REPLY_PANE='organoun-test:0.1'
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_ENV_LOG"
: >"$ORGAN_FAKE_SEND_LOG"

claim_output="$("$REPO_ROOT/bin/organ" claim remote-managed --json)"
assert_jq "$claim_output" '.ok == true and .action == "claim" and .host == "remote.example" and .delivery == "confirmed"'
assert_eq 'session claim remote-managed organoun-test:0.1 ' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"

: >"$ORGAN_FAKE_LOG"
ask_output="$(printf 'Analise o contrato visível.' | "$REPO_ROOT/bin/organ" ask remote-managed --stdin --json)"
assert_jq "$ask_output" '.ok == true and .action == "ask" and .host == "remote.example" and .delivery == "unknown"'
assert_eq 'Analise o contrato visível.' "$(<"$ORGAN_FAKE_PAYLOAD_FILE")"
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
assert_jq "$(<"$pane_record")" '
  .send_attempted == true
  and .send_delivery == "unknown"
  and (.message_digest | test("^[0-9a-f]{64}$"))'

: >"$ORGAN_FAKE_LOG"
set +e
replay_ask_output="$(printf 'Analise o contrato visível.' | "$REPO_ROOT/bin/organ" ask remote-managed --stdin --json)"
replay_ask_rc=$?
set -e
assert_eq 64 "$replay_ask_rc"
assert_jq "$replay_ask_output" '.ok == false and .error.code == "MESSAGE_ALREADY_ATTEMPTED"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

# A pane with an active external-session claim is not yet safe to close.
set +e
active_close_output="$("$REPO_ROOT/bin/organ" close remote-managed --json)"
active_close_rc=$?
set -e
assert_eq 64 "$active_close_rc"
assert_jq "$active_close_output" '.ok == false and .error.code == "CLAIM_ACTIVE"'
assert_jq "$(<"$tmux_state")" '(.panes | length) == 2'

release_output="$("$REPO_ROOT/bin/organ" release remote-managed --json)"
assert_jq "$release_output" '.ok == true and .action == "release" and .host == "remote.example" and .delivery == "confirmed"'

# Closing may remove only the exact pane proven by the private receipt. The
# owner pane and owner receipt remain, while replay cannot kill anything else.
close_output="$("$REPO_ROOT/bin/organ" close remote-managed --json)"
assert_jq "$close_output" '
  .ok == true
  and .action == "close"
  and .target == "remote-managed"
  and .host == "remote.example"
  and .state == "closed"
  and .data.pane_id == "%2"'
assert_not_exists "$pane_record"
[[ -f "$owner_record" ]] || { printf 'close removed the owner receipt\n' >&2; exit 1; }
assert_jq "$(<"$tmux_state")" '
  (.panes | length) == 1
  and .panes[0].id == "%1"
  and .panes[0].pid == 41001'
kill_calls="$(tr '\0' '\n' <"$tmux_log" | grep -c '^kill-pane$' || true)"
assert_eq 1 "$kill_calls"

set +e
close_replay_output="$("$REPO_ROOT/bin/organ" close remote-managed --json)"
close_replay_rc=$?
set -e
assert_eq 64 "$close_replay_rc"
assert_jq "$close_replay_output" '.ok == false and .error.code == "MANAGED_PANE_NOT_FOUND"'
kill_calls="$(tr '\0' '\n' <"$tmux_log" | grep -c '^kill-pane$' || true)"
assert_eq 1 "$kill_calls"

printf 'control plane tests passed\n'
