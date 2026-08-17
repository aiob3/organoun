#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: edit dispatch can start before validating its Git boundary,
# persist the prompt, audit paths with line-oriented or string-prefix logic,
# execute verification from status or before scope rejection, rerun a terminal
# result, silently expand verification output, or redispatch after a failure.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
fixture_repo="$TEST_TMP/fixture-repo"
submodule_repo="$TEST_TMP/submodule-repo"
nested_repo="$TEST_TMP/nested-submodule-repo"
worktree="$TEST_TMP/edit worktree;touch injected"
submodule_worktree="$worktree/deps/hidden"
nested_worktree="$submodule_worktree/nested modules/odd;name"
mkdir -p -- "$fixture_repo" "$submodule_repo" "$nested_repo"
git -C "$nested_repo" init -q
git -C "$nested_repo" config user.name 'Organoun Test'
git -C "$nested_repo" config user.email 'organoun@example.invalid'
printf 'nested original\n' >"$nested_repo/nested.txt"
git -C "$nested_repo" add nested.txt
git -C "$nested_repo" commit -qm base
git -C "$submodule_repo" init -q
git -C "$submodule_repo" config user.name 'Organoun Test'
git -C "$submodule_repo" config user.email 'organoun@example.invalid'
printf 'submodule original\n' >"$submodule_repo/value.txt"
git -C "$submodule_repo" add value.txt
git -C "$submodule_repo" commit -qm base
git -C "$submodule_repo" -c protocol.file.allow=always submodule add -q \
  "$nested_repo" 'nested modules/odd;name'
git -C "$submodule_repo" commit -qam 'add nested submodule'
git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.name 'Organoun Test'
git -C "$fixture_repo" config user.email 'organoun@example.invalid'
mkdir -p -- "$fixture_repo/src" "$fixture_repo/tests"
printf 'original\n' >"$fixture_repo/src/value.txt"
cat >"$fixture_repo/tests/value_test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${ORGAN_TEST_VERIFY_MARKER:?}"
printf 'run\n' >>"$ORGAN_TEST_VERIFY_MARKER"
grep -qx 'changed' src/value.txt
EOF
cat >"$fixture_repo/tests/output_test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
head -c 70000 /dev/zero | tr '\0' x
exit "${ORGAN_TEST_VERIFY_EXIT:-0}"
EOF
cat >"$fixture_repo/tests/credential_output_test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' \
  'BEARER verifycredential987654' \
  'bAsIc verifystandalonebasic987654' \
  'AUTHORIZATION: Basic dmVyaWZ5OnNlY3JldA==' \
  'Proxy-Authorization: Bearer verifyproxy987654' \
  'Cookie: session=verifycookie987654; Secure' \
  'Set-Cookie: auth=verifysetcookie987654; HttpOnly' \
  'X-API-Key: verifyheader987654' \
  'token: verify-lower-token-987654' \
  'password=verify-lower-password-987654'
EOF
git -C "$fixture_repo" -c protocol.file.allow=always submodule add -q "$submodule_repo" deps/hidden
git -C "$fixture_repo" add src tests
git -C "$fixture_repo" commit -qm base
base_sha="$(git -C "$fixture_repo" rev-parse HEAD)"
git -C "$fixture_repo" worktree add -q -b organoun-test-worker "$worktree" HEAD
git -C "$worktree" -c protocol.file.allow=always submodule update -q --init --recursive
git -C "$worktree" config submodule.deps/hidden.ignore all

config="$TEST_TMP/targets.json"
jq -cn --arg cwd "$worktree" '{schema_version:"1",targets:[
  {alias:"claude-managed",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-guard",model:null}
]}' >"$config"

export ORGAN_CONFIG="$config"
export ORGAN_STATE_HOME="$TEST_TMP/private-state"
export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_PROC_ROOT="$TEST_TMP/proc"
export ORGAN_SESSION_POLL_INTERVAL=0
export ORGAN_FAKE_LOG="$TEST_TMP/outsourcerer-argv.log"
export ORGAN_FAKE_COMMAND_LOG="$TEST_TMP/outsourcerer-command.log"
export ORGAN_FAKE_MANAGED_ENV_LOG="$TEST_TMP/outsourcerer-managed-env.log"
export ORGAN_FAKE_CWD_LOG="$TEST_TMP/outsourcerer-cwd.log"
export ORGAN_FAKE_SEND_LOG="$TEST_TMP/send.log"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/tmux.log"
export ORGAN_FAKE_TMUX_STATE_FILE="$TEST_TMP/tmux-state.json"
export ORGAN_FAKE_PAYLOAD_FILE="$TEST_TMP/delivered-edit-prompt"
export ORGAN_FAKE_PANE_ID='%52'
export ORGAN_FAKE_PANE_PID=5252
export ORGAN_FAKE_PID_START=852
export ORGAN_TEST_VERIFY_MARKER="$TEST_TMP/verify-marker"
mkdir -p -- "$ORGAN_PROC_ROOT"
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_COMMAND_LOG"
: >"$ORGAN_FAKE_MANAGED_ENV_LOG"
: >"$ORGAN_FAKE_CWD_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
jq -cn '{exists:false}' >"$ORGAN_FAKE_TMUX_STATE_FILE"

reset_worktree() {
  git -C "$worktree" update-index --no-assume-unchanged tests/value_test.sh src/value.txt
  git -C "$worktree" update-index --no-skip-worktree tests/value_test.sh src/value.txt
  git -C "$submodule_worktree" update-index --no-assume-unchanged value.txt
  git -C "$submodule_worktree" update-index --no-skip-worktree value.txt
  git -C "$nested_worktree" update-index --no-assume-unchanged nested.txt
  git -C "$nested_worktree" update-index --no-skip-worktree nested.txt
  git -C "$nested_worktree" reset -q --hard
  git -C "$nested_worktree" clean -qfd
  git -C "$submodule_worktree" reset -q --hard
  git -C "$submodule_worktree" clean -qfd
  git -C "$worktree" reset -q --hard "$base_sha"
  git -C "$worktree" clean -qfd
  git -C "$worktree" -c protocol.file.allow=always submodule update -q --init --recursive --force
}

set_recursive_hidden_flag() {
  local hidden_kind="$1"

  case "$hidden_kind" in
    submodule-assume)
      git -C "$submodule_worktree" update-index --assume-unchanged value.txt
      printf 'hidden local assume\n' >>"$submodule_worktree/value.txt"
      ;;
    submodule-skip)
      git -C "$submodule_worktree" update-index --skip-worktree value.txt
      printf 'hidden local skip\n' >>"$submodule_worktree/value.txt"
      ;;
    nested-assume)
      git -C "$nested_worktree" update-index --assume-unchanged nested.txt
      printf 'hidden nested assume\n' >>"$nested_worktree/nested.txt"
      ;;
    nested-skip)
      git -C "$nested_worktree" update-index --skip-worktree nested.txt
      printf 'hidden nested skip\n' >>"$nested_worktree/nested.txt"
      ;;
    *) return 64 ;;
  esac
}

wait_for_path() {
  local path="$1"
  local attempt

  for ((attempt = 0; attempt < 500; attempt += 1)); do
    [[ -e "$path" ]] && return 0
    sleep 0.01
  done
  printf 'timed out waiting for %s\n' "$path" >&2
  return 1
}

latest_job_file() {
  find "$ORGAN_STATE_HOME/jobs" -maxdepth 1 -type f -name 'local.job-*.json' -printf '%T@ %p\n' |
    sort -n | tail -n 1 | cut -d ' ' -f 2-
}

dispatch_edit() {
  local prompt="$1"
  shift
  printf '%s' "$prompt" | "$REPO_ROOT/bin/organ" dispatch claude-managed \
    --mode edit --worktree "$worktree" "$@" --stdin --json
}

assert_edit_error() {
  local expected_code="$1"
  shift
  local actual rc
  set +e
  actual="$(printf 'must not send' | "$REPO_ROOT/bin/organ" dispatch claude-managed "$@" 2>&1)"
  rc=$?
  set -e
  assert_eq 64 "$rc"
  jq -e --arg code "$expected_code" '.ok == false and .error.code == $code' <<<"$actual" >/dev/null
}

# Every preflight failure happens before session lifecycle or dispatch.
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow '' --verify true --stdin --json
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow /src --verify true --stdin --json
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow . --verify true --stdin --json
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow ../src --verify true --stdin --json
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow src/../tests --verify true --stdin --json
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow src/ --verify true --stdin --json
assert_edit_error ALLOW_INVALID --mode edit --worktree "$worktree" --allow src --allow src --verify true --stdin --json
assert_edit_error WORKTREE_INVALID --mode edit --worktree relative/worktree --allow src --verify true --stdin --json
mkdir -p -- "$TEST_TMP/not-git"
assert_edit_error WORKTREE_INVALID --mode edit --worktree "$TEST_TMP/not-git" --allow src --verify true --stdin --json
assert_edit_error WORKTREE_INVALID --mode edit --worktree "$worktree/src" --allow src --verify true --stdin --json
printf 'dirty\n' >>"$worktree/src/value.txt"
assert_edit_error WORKTREE_DIRTY --mode edit --worktree "$worktree" --allow src --verify true --stdin --json
reset_worktree

# Git configuration and index flags cannot hide dirty tracked content from
# edit preflight, even when the hidden path is outside the allowlist.
printf 'submodule dirty\n' >>"$worktree/deps/hidden/value.txt"
assert_edit_error WORKTREE_DIRTY --mode edit --worktree "$worktree" --allow src --verify true --stdin --json
reset_worktree
git -C "$worktree" update-index --assume-unchanged tests/value_test.sh
printf '# assume hidden\n' >>"$worktree/tests/value_test.sh"
assert_edit_error WORKTREE_DIRTY --mode edit --worktree "$worktree" --allow src --verify true --stdin --json
reset_worktree
git -C "$worktree" update-index --skip-worktree tests/value_test.sh
printf '# skip hidden\n' >>"$worktree/tests/value_test.sh"
assert_edit_error WORKTREE_DIRTY --mode edit --worktree "$worktree" --allow src --verify true --stdin --json
reset_worktree
for hidden_kind in submodule-assume submodule-skip nested-assume nested-skip; do
  set_recursive_hidden_flag "$hidden_kind"
  assert_edit_error WORKTREE_DIRTY --mode edit --worktree "$worktree" --allow src --verify true --stdin --json
  reset_worktree
done
assert_eq 0 "$(wc -l <"$ORGAN_FAKE_COMMAND_LOG")"

# A valid relative component scope is captured before the one worker send.
prompt='change value -- private prompt 6b31a39f'
actual="$(dispatch_edit "$prompt" --allow src --verify 'bash tests/value_test.sh')"
assert_jq "$actual" '.ok == true and .action == "dispatch" and .state == "working" and .data.job_id != null'
job_id="$(jq -r '.data.job_id' <<<"$actual")"
receipt="$ORGAN_STATE_HOME/jobs/$job_id.json"
assert_mode 600 "$receipt"
jq -e --arg base "$base_sha" --arg worktree "$worktree" '
  .mode == "edit" and .base_sha == $base and (.base_sha | test("^[0-9a-f]{40}$")) and
  .worktree == $worktree and .allow == ["src"] and
  .verify_command == "bash tests/value_test.sh" and .verification == null and .artifacts == []
' "$receipt" >/dev/null
if grep -FRq -- "$prompt" "$ORGAN_STATE_HOME"; then
  printf 'private state persisted the edit prompt\n' >&2
  exit 1
fi
grep -Fq -- "$prompt" "$ORGAN_FAKE_PAYLOAD_FILE"
grep -Fq -- "$worktree" "$ORGAN_FAKE_PAYLOAD_FILE"
grep -Fq -- '"allow":["src"]' "$ORGAN_FAKE_PAYLOAD_FILE"
if grep -Fq -- 'verify_command' "$ORGAN_FAKE_PAYLOAD_FILE" || grep -Fq -- "$base_sha" "$ORGAN_FAKE_PAYLOAD_FILE"; then
  printf 'worker prompt exposed controller-only guard fields\n' >&2
  exit 1
fi
assert_eq 1 "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
assert_not_exists "$TEST_TMP/injected"

# Status is observational even when the worktree has become dirty.
printf 'changed\n' >"$worktree/src/value.txt"
"$REPO_ROOT/bin/organ" status claude-managed --json >/dev/null
assert_not_exists "$ORGAN_TEST_VERIFY_MARKER"
send_count="$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

# Accepted verification runs exactly once from the explicit worktree, stores a
# terminal result, and a second call returns that same result without sending.
verified_once="$("$REPO_ROOT/bin/organ" verify "$job_id" --json)"
assert_jq "$verified_once" '
  .ok == true and .state == "accepted" and .data.accepted == true and
  .data.status == "accepted" and .data.changed_paths == ["src/value.txt"] and
  .data.verify_exit == 0 and .data.verify_output_bytes == 0 and
  .data.verify_output_truncated == false
'
assert_eq 1 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
verified_twice="$("$REPO_ROOT/bin/organ" verify "$job_id" --json)"
assert_eq "$verified_once" "$verified_twice"
assert_eq 1 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
assert_eq "$send_count" "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

# All allow orders normalize to the same deterministic receipt, while the
# duplicate rejection above remains an edit-preflight failure.
for allow_order in tests-first src-first; do
  reset_worktree
  if [[ "$allow_order" == tests-first ]]; then
    ordered="$(dispatch_edit 'ordered allow paths' --allow tests --allow src --verify true)"
  else
    ordered="$(dispatch_edit 'ordered allow paths' --allow src --allow tests --verify true)"
  fi
  ordered_job="$(jq -r '.data.job_id' <<<"$ordered")"
  jq -e '.allow == ["src","tests"] and .dispatch_complete == true' \
    "$ORGAN_STATE_HOME/jobs/$ordered_job.json" >/dev/null
done

# Preflight is revalidated after managed readiness and immediately before job
# publication/send. Both dirtiness and a clean HEAD movement fail without a job.
for stale_kind in dirty head-moved; do
  reset_worktree
  read_gate="$TEST_TMP/read-gate-$stale_kind"
  dispatch_output="$TEST_TMP/stale-$stale_kind.json"
  prompt_file="$TEST_TMP/stale-$stale_kind.prompt"
  printf 'stale preflight' >"$prompt_file"
  export ORGAN_FAKE_READ_GATE="$read_gate"
  jobs_before="$(find "$ORGAN_STATE_HOME/jobs" -maxdepth 1 -type f | wc -l)"
  sends_before="$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
  "$REPO_ROOT/bin/organ" dispatch claude-managed --mode edit --worktree "$worktree" \
    --allow src --verify true --stdin --json <"$prompt_file" >"$dispatch_output" &
  stale_pid=$!
  wait_for_path "$read_gate/entered"
  if [[ "$stale_kind" == dirty ]]; then
    printf 'became dirty\n' >"$worktree/src/value.txt"
  else
    printf 'new clean head\n' >"$worktree/src/value.txt"
    git -C "$worktree" add src/value.txt
    git -C "$worktree" commit -qm 'move head during readiness'
  fi
  touch "$read_gate/release"
  set +e
  wait "$stale_pid"
  stale_rc=$?
  set -e
  unset ORGAN_FAKE_READ_GATE
  assert_eq 64 "$stale_rc"
  assert_jq "$(<"$dispatch_output")" '.error.code == "EDIT_WORKTREE_STALE"'
  assert_eq "$jobs_before" "$(find "$ORGAN_STATE_HOME/jobs" -maxdepth 1 -type f | wc -l)"
  assert_eq "$sends_before" "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
done

# A receipt visible while the one send is blocked is explicitly incomplete and
# cannot terminally verify an empty diff. Once send returns, a real edit verifies.
reset_worktree
: >"$ORGAN_TEST_VERIFY_MARKER"
send_gate="$TEST_TMP/send-gate"
dispatch_output="$TEST_TMP/blocked-send.json"
prompt_file="$TEST_TMP/blocked-send.prompt"
printf 'blocked send' >"$prompt_file"
export ORGAN_FAKE_SEND_GATE="$send_gate"
"$REPO_ROOT/bin/organ" dispatch claude-managed --mode edit --worktree "$worktree" \
  --allow src --verify 'bash tests/value_test.sh' --stdin --json <"$prompt_file" >"$dispatch_output" &
blocked_send_pid=$!
wait_for_path "$send_gate/entered"
incomplete_receipt="$(latest_job_file)"
incomplete_job="${incomplete_receipt##*/}"
incomplete_job="${incomplete_job%.json}"
jq -e '.mode == "edit" and .dispatch_complete == false and .verification == null' "$incomplete_receipt" >/dev/null
set +e
incomplete_verify="$("$REPO_ROOT/bin/organ" verify "$incomplete_job" --json 2>&1)"
incomplete_rc=$?
set -e
assert_eq 64 "$incomplete_rc"
assert_jq "$incomplete_verify" '.error.code == "DISPATCH_INCOMPLETE"'
assert_eq 0 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
jq -e '.dispatch_complete == false and .verification == null' "$incomplete_receipt" >/dev/null
touch "$send_gate/release"
wait "$blocked_send_pid"
unset ORGAN_FAKE_SEND_GATE
assert_jq "$(<"$dispatch_output")" '.ok == true'
jq -e '.dispatch_complete == true and .verification == null' "$incomplete_receipt" >/dev/null
printf 'changed\n' >"$worktree/src/value.txt"
post_send_verify="$("$REPO_ROOT/bin/organ" verify "$incomplete_job" --json)"
assert_jq "$post_send_verify" '.state == "accepted" and .data.accepted == true'

# Sender death leaves the published receipt permanently nonverifiable and does
# not retry or synthesize a completed delivery.
reset_worktree
death_gate="$TEST_TMP/death-send-gate"
death_output="$TEST_TMP/death-send.json"
death_prompt="$TEST_TMP/death-send.prompt"
printf 'sender death' >"$death_prompt"
export ORGAN_FAKE_SEND_GATE="$death_gate"
setsid "$REPO_ROOT/bin/organ" dispatch claude-managed --mode edit --worktree "$worktree" \
  --allow src --verify true --stdin --json <"$death_prompt" >"$death_output" 2>&1 &
death_pid=$!
wait_for_path "$death_gate/entered"
death_receipt="$(latest_job_file)"
death_job="${death_receipt##*/}"
death_job="${death_job%.json}"
kill -TERM -- "-$death_pid"
set +e
wait "$death_pid"
death_rc=$?
set -e
unset ORGAN_FAKE_SEND_GATE
[[ "$death_rc" -ne 0 ]] || {
  printf 'killed sender exited successfully\n' >&2
  exit 1
}
jq -e '.dispatch_complete == false and .verification == null' "$death_receipt" >/dev/null
set +e
death_verify="$("$REPO_ROOT/bin/organ" verify "$death_job" --json 2>&1)"
death_verify_rc=$?
set -e
assert_eq 64 "$death_verify_rc"
assert_jq "$death_verify" '.error.code == "DISPATCH_INCOMPLETE"'

# Hidden tracked changes introduced only after dispatch block scope without
# running the verifier, including submodule ignore and both index flags.
for hidden_kind in submodule assume skip; do
  reset_worktree
  : >"$ORGAN_TEST_VERIFY_MARKER"
  hidden_dispatch="$(dispatch_edit "hidden $hidden_kind" --allow src --verify 'bash tests/value_test.sh')"
  hidden_job="$(jq -r '.data.job_id' <<<"$hidden_dispatch")"
  case "$hidden_kind" in
    submodule) printf 'hidden verify\n' >>"$worktree/deps/hidden/value.txt" ;;
    assume)
      git -C "$worktree" update-index --assume-unchanged tests/value_test.sh
      printf '# hidden verify\n' >>"$worktree/tests/value_test.sh"
      ;;
    skip)
      git -C "$worktree" update-index --skip-worktree tests/value_test.sh
      printf '# hidden verify\n' >>"$worktree/tests/value_test.sh"
      ;;
  esac
  hidden_verify="$("$REPO_ROOT/bin/organ" verify "$hidden_job" --json)"
  assert_jq "$hidden_verify" '.state == "blocked-scope" and .data.accepted == false and .data.verify_exit == null'
  assert_eq 0 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
done

# Index flags inside initialized submodules and nested submodules are audited
# recursively after dispatch. Each one blocks before the verifier even though
# the entire submodule tree is outside the allowlist and configured ignore=all.
for hidden_kind in submodule-assume submodule-skip nested-assume nested-skip; do
  reset_worktree
  : >"$ORGAN_TEST_VERIFY_MARKER"
  recursive_dispatch="$(dispatch_edit "recursive hidden $hidden_kind" --allow src --verify 'bash tests/value_test.sh')"
  recursive_job="$(jq -r '.data.job_id' <<<"$recursive_dispatch")"
  set_recursive_hidden_flag "$hidden_kind"
  recursive_verify="$("$REPO_ROOT/bin/organ" verify "$recursive_job" --json)"
  assert_jq "$recursive_verify" '.state == "blocked-scope" and .data.accepted == false and .data.verify_exit == null'
  assert_eq 0 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
done

# Invalid UTF-8 path bytes never enter jq metadata or collide after replacement;
# one or multiple such paths terminally block before scope/verifier/manifest.
for invalid_case in one multiple; do
  reset_worktree
  : >"$ORGAN_TEST_VERIFY_MARKER"
  invalid_dispatch="$(dispatch_edit "invalid utf8 $invalid_case" --allow src --verify 'bash tests/value_test.sh')"
  invalid_job="$(jq -r '.data.job_id' <<<"$invalid_dispatch")"
  if [[ "$invalid_case" == one ]]; then
    invalid_path=$'src/invalid-\377.txt'
    printf 'invalid\n' >"$worktree/$invalid_path"
  else
    invalid_path_a=$'src/collision-\376.txt'
    invalid_path_b=$'src/collision-\377.txt'
    printf 'invalid a\n' >"$worktree/$invalid_path_a"
    printf 'invalid b\n' >"$worktree/$invalid_path_b"
    printf 'valid replacement-like\n' >"$worktree/src/collision-�.txt"
  fi
  invalid_verify="$("$REPO_ROOT/bin/organ" verify "$invalid_job" --json)"
  assert_jq "$invalid_verify" '.state == "blocked-scope" and .data.accepted == false and .data.verify_exit == null and .data.artifacts == []'
  assert_eq 0 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
done

# A tracked change outside the component boundary blocks before verification.
reset_worktree
: >"$ORGAN_TEST_VERIFY_MARKER"
actual="$(dispatch_edit 'tracked scope failure' --allow src --verify 'bash tests/value_test.sh')"
scope_job="$(jq -r '.data.job_id' <<<"$actual")"
printf '# outside\n' >>"$worktree/tests/value_test.sh"
send_count="$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
blocked_scope="$("$REPO_ROOT/bin/organ" verify "$scope_job" --json)"
assert_jq "$blocked_scope" '
  .state == "blocked-scope" and .data.accepted == false and
  .data.status == "blocked-scope" and .data.changed_paths == ["tests/value_test.sh"] and
  .data.verify_exit == null and .data.verify_output == ""
'
assert_eq 0 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
assert_eq "$send_count" "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

# Untracked paths, embedded newlines, and lookalike prefixes remain distinct.
reset_worktree
actual="$(dispatch_edit 'untracked scope failure' --allow src --verify 'bash tests/value_test.sh')"
untracked_job="$(jq -r '.data.job_id' <<<"$actual")"
mkdir -p -- "$worktree/src-other"
unusual_outside=$'src-other/odd\nname.txt'
printf 'outside\n' >"$worktree/$unusual_outside"
blocked_untracked="$("$REPO_ROOT/bin/organ" verify "$untracked_job" --json)"
if ! jq -e --arg path "$unusual_outside" '
  .state == "blocked-scope" and .data.changed_paths == [$path] and .data.verify_exit == null
' <<<"$blocked_untracked" >/dev/null; then
  printf 'unusual outside path was not preserved in blocked result\n' >&2
  exit 1
fi
assert_eq 0 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"

# NUL-delimited collection also accepts an unusual filename inside scope.
reset_worktree
actual="$(dispatch_edit 'unusual allowed filename' --allow src --verify 'bash tests/value_test.sh')"
unusual_job="$(jq -r '.data.job_id' <<<"$actual")"
printf 'changed\n' >"$worktree/src/value.txt"
unusual_inside=$'src/odd\nname.txt'
printf 'allowed\n' >"$worktree/$unusual_inside"
accepted_unusual="$("$REPO_ROOT/bin/organ" verify "$unusual_job" --json)"
if ! jq -e --arg odd "$unusual_inside" '
  .state == "accepted" and (.data.changed_paths | index("src/value.txt") != null) and
  (.data.changed_paths | index($odd) != null)
' <<<"$accepted_unusual" >/dev/null; then
  printf 'unusual allowed path was not preserved in accepted result\n' >&2
  exit 1
fi

# A failed command is terminal, recorded once, and never causes redispatch.
reset_worktree
: >"$ORGAN_TEST_VERIFY_MARKER"
actual="$(dispatch_edit 'verification failure' --allow src --verify 'bash tests/value_test.sh')"
failed_job="$(jq -r '.data.job_id' <<<"$actual")"
printf 'wrong\n' >"$worktree/src/value.txt"
send_count="$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
failed_once="$("$REPO_ROOT/bin/organ" verify "$failed_job" --json)"
assert_jq "$failed_once" '.state == "blocked-verification" and .data.accepted == false and .data.verify_exit != 0'
failed_twice="$("$REPO_ROOT/bin/organ" verify "$failed_job" --json)"
assert_eq "$failed_once" "$failed_twice"
assert_eq 1 "$(wc -l <"$ORGAN_TEST_VERIFY_MARKER")"
assert_eq "$send_count" "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

# The verifier shares the public redaction boundary with read output. Its
# public envelope may retain labels, but never the concrete credential values.
reset_worktree
actual="$(dispatch_edit 'credential-bearing verification output' --allow src --verify 'bash tests/credential_output_test.sh')"
credential_job="$(jq -r '.data.job_id' <<<"$actual")"
printf 'changed\n' >"$worktree/src/value.txt"
credential_verified="$("$REPO_ROOT/bin/organ" verify "$credential_job" --json)"
assert_jq "$credential_verified" '
  .state == "accepted" and .data.accepted == true and
  (.data.verify_output | contains("BEARER [REDACTED]")) and
  (.data.verify_output | contains("bAsIc [REDACTED]")) and
  (.data.verify_output | contains("AUTHORIZATION: [REDACTED]")) and
  (.data.verify_output | contains("Proxy-Authorization: [REDACTED]")) and
  (.data.verify_output | contains("Cookie: [REDACTED]")) and
  (.data.verify_output | contains("Set-Cookie: [REDACTED]")) and
  (.data.verify_output | contains("X-API-Key: [REDACTED]")) and
  (.data.verify_output | contains("token: [REDACTED]")) and
  (.data.verify_output | contains("password=[REDACTED]"))
'
for leaked_credential in \
  verifycredential987654 verifystandalonebasic987654 dmVyaWZ5OnNlY3JldA== \
  verifyproxy987654 verifycookie987654 verifysetcookie987654 \
  verifyheader987654 verify-lower-token-987654 verify-lower-password-987654; do
  if grep -Fq -- "$leaked_credential" <<<"$credential_verified"; then
    printf 'public verifier output leaked credential: %s\n' "$leaked_credential" >&2
    exit 1
  fi
done

# Raw command output is privately bounded to 64 KiB with explicit truncation
# metadata; the nonzero exit remains the verification outcome.
reset_worktree
export ORGAN_TEST_VERIFY_EXIT=9
actual="$(dispatch_edit 'bounded verification output' --allow src --verify 'bash tests/output_test.sh')"
bounded_job="$(jq -r '.data.job_id' <<<"$actual")"
printf 'changed\n' >"$worktree/src/value.txt"
bounded="$("$REPO_ROOT/bin/organ" verify "$bounded_job" --json)"
unset ORGAN_TEST_VERIFY_EXIT
assert_jq "$bounded" '
  .state == "blocked-verification" and .data.verify_exit == 9 and
  .data.verify_output_bytes == 70000 and .data.verify_output_truncated == true
'
decoded_output="$TEST_TMP/verify-output"
jq -j '.data.verify_output' <<<"$bounded" >"$decoded_output"
assert_eq 65536 "$(wc -c <"$decoded_output")"

# Remote verification is host-routed and treats a hermetic transport failure as
# an ambiguous mutation. It never inspects local job state or retries.
export ORGAN_SSH=/bin/false
set +e
remote_verify="$("$REPO_ROOT/bin/organ" verify remote.job-20260816T120000Z-a1b2c3d4 --json 2>&1)"
remote_verify_rc=$?
set -e
unset ORGAN_SSH
assert_eq 69 "$remote_verify_rc"
assert_jq "$remote_verify" '
  .host == "remote.example" and .state == "delivery-unknown" and .delivery == "unknown" and
  .error.code == "REMOTE_DELIVERY_UNKNOWN"'

printf 'guard tests passed\n'
