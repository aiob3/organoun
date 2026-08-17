#!/usr/bin/env bash
set -euo pipefail

# Break caught: an SSH target can invoke a hidden remote helper or create a
# second control plane when no operator-visible local pane receipt exists.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env

config="$TEST_TMP/targets.json"
jq -cn '{schema_version:"1",targets:[
  {alias:"remote-managed",transport:"ssh",host:"remote.example",cwd:"/workspace/remote",mode:"managed",provider:"cc",session_name:"organoun-remote",model:null}
]}' >"$config"

export ORGAN_CONFIG="$config"
export ORGAN_STATE_HOME="$XDG_STATE_HOME/organoun"
export ORGAN_SSH="$REPO_ROOT/tests/fixtures/forbidden-ssh.sh"
export ORGAN_FORBIDDEN_SSH_LOG="$TEST_TMP/ssh.log"
export ORGAN_REMOTE_HELPER="$HOME/.local/libexec/organoun/organ-remote"
: >"$ORGAN_FORBIDDEN_SSH_LOG"

assert_visible_refusal() {
  local action="$1"
  shift
  local output refusal_rc

  set +e
  output="$("$@" 2>&1)"
  refusal_rc=$?
  set -e
  assert_eq 64 "$refusal_rc"
  if ! jq -e --arg action "$action" \
    '.ok == false and .action == $action and .target == "remote-managed" and .host == "remote.example" and .error.code == "VISIBLE_PANE_REQUIRED"' \
    >/dev/null <<<"$output"; then
    printf 'unexpected remote refusal for %s: %s\n' "$action" "$output" >&2
    return 1
  fi
  assert_eq '' "$(<"$ORGAN_FORBIDDEN_SSH_LOG")"
}

for observation_action in status read claim release stop; do
  assert_visible_refusal "$observation_action" "$REPO_ROOT/bin/organ" "$observation_action" remote-managed --json
done

set +e
ask_output="$(printf 'não abra transporte oculto' | "$REPO_ROOT/bin/organ" ask remote-managed --stdin --json 2>&1)"
ask_rc=$?
set -e
assert_eq 64 "$ask_rc"
assert_jq "$ask_output" '.ok == false and .action == "ask" and .target == "remote-managed" and .host == "remote.example" and .error.code == "VISIBLE_PANE_REQUIRED"'
assert_eq '' "$(<"$ORGAN_FORBIDDEN_SSH_LOG")"

set +e
dispatch_output="$(printf 'não crie controle remoto' | "$REPO_ROOT/bin/organ" dispatch remote-managed --mode read --stdin --json 2>&1)"
dispatch_rc=$?
set -e
assert_eq 64 "$dispatch_rc"
assert_jq "$dispatch_output" '.ok == false and .action == "dispatch" and .target == "remote-managed" and .host == "remote.example" and .error.code == "VISIBLE_PANE_REQUIRED"'
assert_eq '' "$(<"$ORGAN_FORBIDDEN_SSH_LOG")"

printf 'ssh boundary tests passed\n'
