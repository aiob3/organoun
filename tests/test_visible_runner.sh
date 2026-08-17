#!/usr/bin/env bash
set -euo pipefail

# Break caught: a test or operational gate can execute outside an attached,
# operator-visible tmux pane, or continue after that visibility is lost.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env

runner="$REPO_ROOT/scripts/run-visible.sh"
[[ -x "$runner" ]] || {
  printf 'visible runner is missing or not executable: %s\n' "$runner" >&2
  exit 1
}

tmux_state="$TEST_TMP/tmux-state.json"
tmux_log="$TEST_TMP/tmux.log"
: >"$tmux_log"
jq -cn '{
  session_id:"$1",
  session_name:"organoun-visible-test",
  window_id:"@1",
  window_index:"0",
  window_zoomed_flag:0,
  window_layout:"layout-visible",
  owner_pane:{id:"%1",pid:51001,cwd:"/workspace/project"},
  panes:[{id:"%1",index:"0",pid:51001,dead:0,current_command:"bash",cwd:"/workspace/project",output:"runner"}],
  clients:[{session_id:"$1",window_id:"@1",tty:"/dev/pts/9",control_mode:0,readonly:0}]
}' >"$tmux_state"

export ORGAN_VISIBLE_TMUX="$REPO_ROOT/tests/fixtures/fake-control-tmux.sh"
export ORGAN_FAKE_CONTROL_TMUX_STATE="$tmux_state"
export ORGAN_FAKE_CONTROL_TMUX_LOG="$tmux_log"

hidden_marker="$TEST_TMP/hidden-ran"
set +e
# shellcheck disable=SC2016 # Positional parameter expands in the inner shell.
hidden_output="$(env -u TMUX -u TMUX_PANE "$runner" -- bash -c ': >"$1"' _ "$hidden_marker" 2>&1)"
hidden_rc=$?
set -e
assert_eq 64 "$hidden_rc"
assert_not_exists "$hidden_marker"
[[ "$hidden_output" == *VISIBLE_RUNNER_REFUSED* ]] || { printf 'hidden run lacked refusal marker\n' >&2; exit 1; }

export TMUX='/tmp/tmux-test/default,51000,0'
export TMUX_PANE='%1'
visible_marker="$TEST_TMP/visible-ran"
# shellcheck disable=SC2016 # Environment and positional parameter expand in the inner shell.
visible_output="$("$runner" -- bash -c 'printf "%s|%s\n" "$ORGAN_OPERATOR_VISIBLE" "$ORGAN_OPERATOR_PANE" >"$1"; printf "child-visible\n"' _ "$visible_marker")"
assert_eq '1|%1' "$(<"$visible_marker")"
[[ "$visible_output" == *VISIBLE_RUNNER_START* && "$visible_output" == *child-visible* && "$visible_output" == *VISIBLE_RUNNER_END* ]] || {
  printf 'visible run lacked lifecycle markers\n' >&2
  exit 1
}

readonly_state="${tmux_state}.readonly"
jq '(.clients[0].readonly) = 1' "$tmux_state" >"$readonly_state"
mv -f -- "$readonly_state" "$tmux_state"
readonly_marker="$TEST_TMP/readonly-ran"
set +e
# shellcheck disable=SC2016 # Positional parameter expands in the inner shell.
readonly_output="$("$runner" -- bash -c ': >"$1"' _ "$readonly_marker" 2>&1)"
readonly_rc=$?
set -e
assert_eq 64 "$readonly_rc"
assert_not_exists "$readonly_marker"
[[ "$readonly_output" == *VISIBLE_RUNNER_REFUSED* ]] || { printf 'readonly run lacked refusal marker\n' >&2; exit 1; }

# Visibility is continuously enforced: detaching the last eligible client
# terminates the complete command process group before it can finish.
jq '(.clients[0].readonly) = 0' "$tmux_state" >"${tmux_state}.attached"
mv -f -- "${tmux_state}.attached" "$tmux_state"
entered="$TEST_TMP/entered"
completed="$TEST_TMP/completed"
set +e
# shellcheck disable=SC2016 # Positional parameters expand in the inner shell.
"$runner" -- bash -c ': >"$1"; while :; do sleep 0.05; done; : >"$2"' _ "$entered" "$completed" >"$TEST_TMP/lost.out" 2>&1 &
runner_pid=$!
set -e
for _attempt in {1..100}; do
  [[ -e "$entered" ]] && break
  sleep 0.02
done
[[ -e "$entered" ]] || { printf 'watched child did not start\n' >&2; kill "$runner_pid" 2>/dev/null || true; exit 1; }
jq '.clients = []' "$tmux_state" >"${tmux_state}.detached"
mv -f -- "${tmux_state}.detached" "$tmux_state"
set +e
wait "$runner_pid"
lost_rc=$?
set -e
assert_eq 66 "$lost_rc"
assert_not_exists "$completed"
grep -Fq VISIBLE_RUNNER_LOST "$TEST_TMP/lost.out" || { printf 'visibility loss lacked terminal marker\n' >&2; exit 1; }

printf 'visible runner tests passed\n'
