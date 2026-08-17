#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: adopted sessions can be written without a private claim, a
# secret can cross the public CLI boundary, or a blocked/unknown delivery can
# be mistaken for a confirmed message and replayed.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
cwd="$TEST_TMP/target-cwd"
mkdir -p -- "$cwd"
config="$TEST_TMP/targets.json"
jq -cn --arg cwd "$cwd" '
  {schema_version:"1",targets:[
    {alias:"claude-onp",transport:"local",host:"local",cwd:$cwd,mode:"adopted",tmux_target:"tmux:1.3",claude_session_id:null},
    {alias:"claude-managed",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-managed"}
  ]}' >"$config"

export ORGAN_CONFIG="$config"
export ORGAN_STATE_HOME="$TEST_TMP/private-state"
export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_FAKE_LOG="$TEST_TMP/outsourcerer.log"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/tmux.log"
export ORGAN_FAKE_ENV_LOG="$TEST_TMP/adapter-env.log"
export ORGAN_FAKE_SEND_LOG="$TEST_TMP/send.log"
export ORGAN_FAKE_TMUX_OUTPUT='❯'
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
: >"$ORGAN_FAKE_ENV_LOG"
: >"$ORGAN_FAKE_SEND_LOG"

set +e
actual="$(printf 'without claim' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"

set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-managed --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "ADOPTED_TARGET_REQUIRED"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"

oversize="$TEST_TMP/oversize.txt"
head -c 16385 /dev/zero | tr '\0' x >"$oversize"
set +e
actual="$("$REPO_ROOT/bin/organ" ask claude-onp --stdin --json <"$oversize" 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "ASK_TOO_LARGE"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"

export OSRC_EXTERNAL_SEND='ambient-send'
export OSRC_CONTROLLER_ID='ambient-controller'
export OSRC_SESSION_CLAIM_TOKEN='ambient-token'
export OSRC_EXTERNAL_COMPOSER_PROBE='/bin/true'
export OSRC_EXTERNAL_RECEIPT_PROBE='/bin/true'
claim_json="$("$REPO_ROOT/bin/organ" claim claude-onp --json)"
unset OSRC_EXTERNAL_SEND
unset OSRC_CONTROLLER_ID
unset OSRC_SESSION_CLAIM_TOKEN
unset OSRC_EXTERNAL_COMPOSER_PROBE
unset OSRC_EXTERNAL_RECEIPT_PROBE
assert_jq "$claim_json" '.ok == true and .delivery == "confirmed"'
assert_mode 700 "$ORGAN_STATE_HOME"
assert_mode 700 "$ORGAN_STATE_HOME/claims"
assert_mode 600 "$ORGAN_STATE_HOME/claims/claude-onp.json"
assert_jq "$(<"$ORGAN_STATE_HOME/claims/claude-onp.json")" '
  . == {schema_version:"1",alias:"claude-onp",external_id:"claude-onp",controller_id:"organ:claude-onp",endpoint:"tmux:1.3",token:"secret-claim-token"}'
if printf '%s' "$claim_json" | grep -q 'secret-claim-token'; then
  printf 'public claim response leaked token\n' >&2
  exit 1
fi
assert_eq 'session claim claude-onp tmux:1.3 ' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq 'send=<1> controller=<organ:claude-onp> token=<unset> composer=<unset> receipt=<unset>' "$(<"$ORGAN_FAKE_ENV_LOG")"
[[ -z "${OSRC_EXTERNAL_SEND:-}" ]] || { printf 'child scope leaked external-send\n' >&2; exit 1; }

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_ENV_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
reply_json="$(printf 'Qual commit você gerou?' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
assert_jq "$reply_json" '.ok == true and .delivery == "unknown"'
assert_eq 'session reply claude-onp Qual\ commit\ você\ gerou\? ' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
grep -Fqx "send=<1> controller=<organ:claude-onp> token=<secret-claim-token> composer=<$REPO_ROOT/probes/claude-composer-empty> receipt=<unset>" "$ORGAN_FAKE_ENV_LOG"

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_ENV_LOG"
export OSRC_EXTERNAL_RECEIPT_PROBE=''
empty_receipt_json="$(printf 'No ambient receipt' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
unset OSRC_EXTERNAL_RECEIPT_PROBE
assert_jq "$empty_receipt_json" '.ok == true and .delivery == "unknown"'
grep -Fqx "send=<1> controller=<organ:claude-onp> token=<secret-claim-token> composer=<$REPO_ROOT/probes/claude-composer-empty> receipt=<unset>" "$ORGAN_FAKE_ENV_LOG"

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_ENV_LOG"
export OSRC_EXTERNAL_RECEIPT_PROBE='/bin/true'
ambient_receipt_json="$(printf 'No implicit receipt' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
unset OSRC_EXTERNAL_RECEIPT_PROBE
assert_jq "$ambient_receipt_json" '.ok == true and .delivery == "unknown"'
grep -Fqx "send=<1> controller=<organ:claude-onp> token=<secret-claim-token> composer=<$REPO_ROOT/probes/claude-composer-empty> receipt=<unset>" "$ORGAN_FAKE_ENV_LOG"

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
export ORGAN_FAKE_TMUX_OUTPUT='❯'
export ORGAN_FAKE_REPLY_OUTPUT='delivery unknown: message was not blocked'
incidental_blocked_json="$(printf 'Do not misclassify' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
unset ORGAN_FAKE_REPLY_OUTPUT
assert_jq "$incidental_blocked_json" '.ok == true and .delivery == "unknown"'
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
export ORGAN_FAKE_REPLY_OUTPUT='composer unknown after message was sent'
incidental_composer_json="$(printf 'Do not misclassify either' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
unset ORGAN_FAKE_REPLY_OUTPUT
assert_jq "$incidental_composer_json" '.ok == true and .delivery == "unknown"'
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
export ORGAN_FAKE_TMUX_OUTPUT='working reply'
blocked_json="$(printf 'Não envie' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
assert_jq "$blocked_json" '.ok == true and .delivery == "blocked"'
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
assert_eq 'session reply claude-onp Não\ envie ' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"

: >"$ORGAN_FAKE_LOG"
export ORGAN_CLAUDE_COMPOSER_PROBE='relative-probe'
set +e
actual="$(printf 'invalid probe' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json 2>&1)"
rc=$?
set -e
unset ORGAN_CLAUDE_COMPOSER_PROBE
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "COMPOSER_PROBE_INVALID"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"

: >"$ORGAN_FAKE_LOG"
export ORGAN_FAKE_TMUX_OUTPUT='❯ Try a concise prompt'
export ORGAN_EXTERNAL_RECEIPT_PROBE="$REPO_ROOT/tests/fixtures/fake-receipt.sh"
receipt_json="$(printf 'Canary' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json)"
unset ORGAN_EXTERNAL_RECEIPT_PROBE
assert_jq "$receipt_json" '.ok == true and .delivery == "confirmed"'
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

: >"$ORGAN_FAKE_LOG"
export ORGAN_FAKE_RELEASE_OUTPUT='release unknown'
set +e
actual="$("$REPO_ROOT/bin/organ" release claude-onp --json 2>&1)"
rc=$?
set -e
unset ORGAN_FAKE_RELEASE_OUTPUT
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "RELEASE_UNCONFIRMED"'
[[ -f "$ORGAN_STATE_HOME/claims/claude-onp.json" ]] || { printf 'unconfirmed release deleted claim\n' >&2; exit 1; }

for release_output in $'release\nconfirmed' $'release confirmed\n\n' $'release confirmed\n\n\n' 'prefix release confirmed' 'release confirmed suffix' $'release confirmed\nrelease confirmed'; do
  export ORGAN_FAKE_RELEASE_OUTPUT="$release_output"
  set +e
  actual="$("$REPO_ROOT/bin/organ" release claude-onp --json 2>&1)"
  rc=$?
  set -e
  assert_eq 64 "$rc"
  assert_jq "$actual" '.error.code == "RELEASE_UNCONFIRMED"'
  [[ -f "$ORGAN_STATE_HOME/claims/claude-onp.json" ]] || { printf 'ambiguous release deleted claim\n' >&2; exit 1; }
done
unset ORGAN_FAKE_RELEASE_OUTPUT

export OSRC_EXTERNAL_SEND='ambient-send'
export OSRC_CONTROLLER_ID='ambient-controller'
export OSRC_SESSION_CLAIM_TOKEN='ambient-token'
export OSRC_EXTERNAL_COMPOSER_PROBE='/bin/true'
export OSRC_EXTERNAL_RECEIPT_PROBE='/bin/true'
: >"$ORGAN_FAKE_ENV_LOG"
release_json="$("$REPO_ROOT/bin/organ" release claude-onp --json)"
unset OSRC_EXTERNAL_SEND
unset OSRC_CONTROLLER_ID
unset OSRC_SESSION_CLAIM_TOKEN
unset OSRC_EXTERNAL_COMPOSER_PROBE
unset OSRC_EXTERNAL_RECEIPT_PROBE
assert_jq "$release_json" '.ok == true and .delivery == "confirmed"'
assert_not_exists "$ORGAN_STATE_HOME/claims/claude-onp.json"
assert_eq 'send=<1> controller=<organ:claude-onp> token=<secret-claim-token> composer=<unset> receipt=<unset>' "$(<"$ORGAN_FAKE_ENV_LOG")"

outside_state="$TEST_TMP/outside-state"
state_link="$TEST_TMP/state-link"
mkdir -p -- "$outside_state"
ln -s -- "$outside_state" "$state_link"
export ORGAN_STATE_HOME="$state_link"
set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_STORE_FAILED"'
assert_not_exists "$outside_state/claims"

outside_claim_directory="$TEST_TMP/outside-claim-directory"
claims_link_state="$TEST_TMP/claims-link-state"
mkdir -p -- "$outside_claim_directory" "$claims_link_state"
ln -s -- "$outside_claim_directory" "$claims_link_state/claims"
export ORGAN_STATE_HOME="$claims_link_state"
set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_STORE_FAILED"'
assert_not_exists "$outside_claim_directory/claude-onp.json"

outside_claims="$TEST_TMP/outside-claims"
redirected_state="$TEST_TMP/redirected-state"
mkdir -p -- "$outside_claims" "$redirected_state"
jq -cn '
  {schema_version:"1",alias:"claude-onp",external_id:"claude-onp",controller_id:"organ:claude-onp",endpoint:"tmux:1.3",token:"outside-secret"}' >"$outside_claims/claude-onp.json"
ln -s -- "$outside_claims" "$redirected_state/claims"
outside_claim_before="$(<"$outside_claims/claude-onp.json")"
export ORGAN_STATE_HOME="$redirected_state"
: >"$ORGAN_FAKE_LOG"
set +e
actual="$(printf 'Do not read redirected state' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq "$outside_claim_before" "$(<"$outside_claims/claude-onp.json")"

set +e
actual="$("$REPO_ROOT/bin/organ" release claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq "$outside_claim_before" "$(<"$outside_claims/claude-onp.json")"

ancestor_outside="$TEST_TMP/ancestor-outside"
ancestor_link="$TEST_TMP/ancestor-link"
mkdir -p -- "$ancestor_outside"
ln -s -- "$ancestor_outside" "$ancestor_link"
export ORGAN_STATE_HOME="$ancestor_link/new-state"
set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_STORE_FAILED"'
assert_not_exists "$ancestor_outside/new-state"

ancestor_existing="$TEST_TMP/ancestor-existing"
ancestor_existing_link="$TEST_TMP/ancestor-existing-link"
mkdir -p -- "$ancestor_existing/state/claims"
jq -cn '
  {schema_version:"1",alias:"claude-onp",external_id:"claude-onp",controller_id:"organ:claude-onp",endpoint:"tmux:1.3",token:"ancestor-secret"}' >"$ancestor_existing/state/claims/claude-onp.json"
chmod 755 -- "$ancestor_existing/state" "$ancestor_existing/state/claims"
chmod 600 -- "$ancestor_existing/state/claims/claude-onp.json"
ln -s -- "$ancestor_existing" "$ancestor_existing_link"
ancestor_record_before="$(<"$ancestor_existing/state/claims/claude-onp.json")"
ancestor_modes_before="$(stat -c '%a %a %a' -- "$ancestor_existing/state" "$ancestor_existing/state/claims" "$ancestor_existing/state/claims/claude-onp.json")"
export ORGAN_STATE_HOME="$ancestor_existing_link/state"
set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_STORE_FAILED"'
assert_eq "$ancestor_record_before" "$(<"$ancestor_existing/state/claims/claude-onp.json")"
assert_eq "$ancestor_modes_before" "$(stat -c '%a %a %a' -- "$ancestor_existing/state" "$ancestor_existing/state/claims" "$ancestor_existing/state/claims/claude-onp.json")"
: >"$ORGAN_FAKE_LOG"
set +e
actual="$(printf 'Do not read ancestor state' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq "$ancestor_record_before" "$(<"$ancestor_existing/state/claims/claude-onp.json")"
assert_eq "$ancestor_modes_before" "$(stat -c '%a %a %a' -- "$ancestor_existing/state" "$ancestor_existing/state/claims" "$ancestor_existing/state/claims/claude-onp.json")"

set +e
actual="$("$REPO_ROOT/bin/organ" release claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq "$ancestor_record_before" "$(<"$ancestor_existing/state/claims/claude-onp.json")"
assert_eq "$ancestor_modes_before" "$(stat -c '%a %a %a' -- "$ancestor_existing/state" "$ancestor_existing/state/claims" "$ancestor_existing/state/claims/claude-onp.json")"

newline_outside="$TEST_TMP/newline-outside"
newline_link="$TEST_TMP/"$'create-link\nsuffix'
mkdir -p -- "$newline_outside"
ln -s -- "$newline_outside" "$newline_link"
export ORGAN_STATE_HOME="$newline_link/new-state"
set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_STORE_FAILED"'
assert_not_exists "$newline_outside/new-state"

newline_existing="$TEST_TMP/newline-existing"
newline_existing_link="$TEST_TMP/"$'existing-link\nsuffix'
mkdir -p -- "$newline_existing/state/claims"
jq -cn '
  {schema_version:"1",alias:"claude-onp",external_id:"claude-onp",controller_id:"organ:claude-onp",endpoint:"tmux:1.3",token:"newline-secret"}' >"$newline_existing/state/claims/claude-onp.json"
chmod 755 -- "$newline_existing/state" "$newline_existing/state/claims"
chmod 600 -- "$newline_existing/state/claims/claude-onp.json"
ln -s -- "$newline_existing" "$newline_existing_link"
newline_record_before="$(<"$newline_existing/state/claims/claude-onp.json")"
newline_modes_before="$(stat -c '%a %a %a' -- "$newline_existing/state" "$newline_existing/state/claims" "$newline_existing/state/claims/claude-onp.json")"
export ORGAN_STATE_HOME="$newline_existing_link/state"
set +e
actual="$("$REPO_ROOT/bin/organ" claim claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_STORE_FAILED"'
assert_eq "$newline_record_before" "$(<"$newline_existing/state/claims/claude-onp.json")"
assert_eq "$newline_modes_before" "$(stat -c '%a %a %a' -- "$newline_existing/state" "$newline_existing/state/claims" "$newline_existing/state/claims/claude-onp.json")"

: >"$ORGAN_FAKE_LOG"
set +e
actual="$(printf 'Do not read newline state' | "$REPO_ROOT/bin/organ" ask claude-onp --stdin --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq '' "$(tr '\0' ' ' <"$ORGAN_FAKE_LOG")"
assert_eq "$newline_record_before" "$(<"$newline_existing/state/claims/claude-onp.json")"
assert_eq "$newline_modes_before" "$(stat -c '%a %a %a' -- "$newline_existing/state" "$newline_existing/state/claims" "$newline_existing/state/claims/claude-onp.json")"

set +e
actual="$("$REPO_ROOT/bin/organ" release claude-onp --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "CLAIM_REQUIRED"'
assert_eq "$newline_record_before" "$(<"$newline_existing/state/claims/claude-onp.json")"
assert_eq "$newline_modes_before" "$(stat -c '%a %a %a' -- "$newline_existing/state" "$newline_existing/state/claims" "$newline_existing/state/claims/claude-onp.json")"

set +e
actual="$("$REPO_ROOT/bin/organ" claim '../escape' --json 2>&1)"
rc=$?
set -e
assert_eq 64 "$rc"
assert_jq "$actual" '.error.code == "TARGET_NOT_FOUND"'
assert_not_exists "$ORGAN_STATE_HOME/claims/../escape.json"
