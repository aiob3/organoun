#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: fetch can accept raw/cross-job paths, expose absolute roots,
# follow a replaced symlink, return oversized files, or route a remote job into
# local state. The fixture uses real Git worktrees and byte-for-byte files.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
fixture_repo="$TEST_TMP/artifact-repo"
worktree="$TEST_TMP/artifact-worktree"
mkdir -p -- "$fixture_repo"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" config user.name 'Organoun Test'
git -C "$fixture_repo" config user.email 'organoun@example.invalid'
mkdir -p -- "$fixture_repo/src"
printf 'original\n' >"$fixture_repo/src/value.bin"
git -C "$fixture_repo" add src/value.bin
git -C "$fixture_repo" commit -qm base
base_sha="$(git -C "$fixture_repo" rev-parse HEAD)"
git -C "$fixture_repo" worktree add -q -b organoun-artifact-worker "$worktree" HEAD

config="$TEST_TMP/targets.json"
jq -cn --arg cwd "$worktree" '{schema_version:"1",targets:[
  {alias:"claude-managed",transport:"local",host:"local",cwd:$cwd,mode:"managed",provider:"cc",session_name:"organoun-artifacts",model:null}
]}' >"$config"
export ORGAN_CONFIG="$config"
export ORGAN_STATE_HOME="$TEST_TMP/private-state"
export ORGAN_OUTSOURCERER="$REPO_ROOT/tests/fixtures/fake-outsourcerer.sh"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_PROC_ROOT="$TEST_TMP/proc"
export ORGAN_SESSION_POLL_INTERVAL=0
export ORGAN_FAKE_LOG="$TEST_TMP/outsourcerer-argv.log"
export ORGAN_FAKE_COMMAND_LOG="$TEST_TMP/outsourcerer-command.log"
export ORGAN_FAKE_SEND_LOG="$TEST_TMP/send.log"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/tmux.log"
export ORGAN_FAKE_TMUX_STATE_FILE="$TEST_TMP/tmux-state.json"
export ORGAN_FAKE_PANE_ID='%62'
export ORGAN_FAKE_PANE_PID=6262
export ORGAN_FAKE_PID_START=962
mkdir -p -- "$ORGAN_PROC_ROOT"
: >"$ORGAN_FAKE_LOG"
: >"$ORGAN_FAKE_COMMAND_LOG"
: >"$ORGAN_FAKE_SEND_LOG"
: >"$ORGAN_FAKE_TMUX_LOG"
jq -cn '{exists:false}' >"$ORGAN_FAKE_TMUX_STATE_FILE"

dispatch_artifact_job() {
  printf 'produce the declared artifact' | "$REPO_ROOT/bin/organ" dispatch claude-managed \
    --mode edit --worktree "$worktree" --allow src --verify true --stdin --json
}

assert_fetch_error() {
  local expected_code="$1"
  shift
  local actual rc
  set +e
  actual="$("$REPO_ROOT/bin/organ" fetch "$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    printf 'fetch unexpectedly succeeded: %s\n' "$*" >&2
    exit 1
  fi
  jq -e --arg code "$expected_code" '.ok == false and .error.code == $code' <<<"$actual" >/dev/null
}

write_job_receipt() {
  local job_id="$1"
  local receipt_json="$2"
  local receipt_path="$ORGAN_STATE_HOME/jobs/$job_id.json"

  mkdir -p -- "$ORGAN_STATE_HOME/jobs"
  printf '%s\n' "$receipt_json" >"$receipt_path"
  chmod 600 -- "$receipt_path"
}

read_job_receipt() {
  local job_id="$1"

  bash -c '
    source "$1/lib/organ/common.sh"
    source "$1/lib/organ/sessions.sh"
    source "$1/lib/organ/guard.sh"
    source "$1/lib/organ/artifacts.sh"
    source "$1/lib/organ/jobs.sh"
    organ_job_read "$2"
  ' organ-job-read "$REPO_ROOT" "$job_id"
}

# Verification manifests only the changed regular file and derives an opaque
# deterministic identifier scoped to the exact accepted job.
dispatch="$(dispatch_artifact_job)"
job_id="$(jq -r '.data.job_id' <<<"$dispatch")"
expected_file="$TEST_TMP/expected-artifact"
printf 'artifact\0bytes\n' >"$expected_file"
cp -- "$expected_file" "$worktree/src/value.bin"
secret="$TEST_TMP/secret"
printf 'do not expose\n' >"$secret"
ln -s -- "$secret" "$worktree/src/escape"
verified="$("$REPO_ROOT/bin/organ" verify "$job_id" --json)"
assert_jq "$verified" '.ok == true and .state == "accepted" and (.data.artifacts | length) == 1'
artifact_id="$(jq -r '.data.artifacts[0].artifact_id' <<<"$verified")"
expected_id="artifact-$({ printf '%s\0%s' "$job_id" 'src/value.bin'; } | sha256sum | cut -c1-12)"
assert_eq "$expected_id" "$artifact_id"
[[ "$artifact_id" =~ ^artifact-[a-f0-9]{12}$ ]] || {
  printf 'artifact id is not opaque: %s\n' "$artifact_id" >&2
  exit 1
}
if [[ "$artifact_id" == *src* || "$artifact_id" == *value* ]]; then
  printf 'artifact id exposed its relative path: %s\n' "$artifact_id" >&2
  exit 1
fi
receipt="$ORGAN_STATE_HOME/jobs/$job_id.json"
jq -e --arg id "$artifact_id" '
  .state == "accepted" and .verification.status == "accepted" and
  .artifacts == [{artifact_id:$id,host:"local",relative_path:"src/value.bin",size_bytes:15,commit:.base_sha}]
' "$receipt" >/dev/null

# A terminal schema-v1 receipt written before dispatch_complete existed remains
# readable and fetchable. Read-time normalization must infer completion from the
# terminal verification without weakening explicit false on current receipts.
legacy_accepted="$(jq -c 'del(.dispatch_complete)' "$receipt")"
write_job_receipt "$job_id" "$legacy_accepted"
assert_jq "$(read_job_receipt "$job_id")" '.dispatch_complete == true and .state == "accepted"'
legacy_terminal_verify="$("$REPO_ROOT/bin/organ" verify "$job_id" --json)"
legacy_terminal_verify_twice="$("$REPO_ROOT/bin/organ" verify "$job_id" --json)"
assert_eq "$legacy_terminal_verify" "$legacy_terminal_verify_twice"
assert_jq "$legacy_terminal_verify" '.state == "accepted" and .data.accepted == true and (.data.artifacts | length) == 1'
assert_eq "$legacy_accepted" "$(<"$receipt")"

# Stdout is the file and nothing else, including embedded NUL and final newline.
fetched="$TEST_TMP/fetched-artifact"
"$REPO_ROOT/bin/organ" fetch "$job_id" "$artifact_id" --stdout >"$fetched"
cmp -s -- "$expected_file" "$fetched" || {
  printf 'fetch --stdout changed artifact bytes\n' >&2
  exit 1
}

# JSON metadata exposes only the required relative metadata, not worktree,
# command, prompt, canonical path, or file contents.
metadata="$("$REPO_ROOT/bin/organ" fetch "$job_id" "$artifact_id" --json)"
if ! jq -e --arg id "$artifact_id" --arg base "$base_sha" '
  .ok == true and .action == "fetch" and .host == "local" and
  .data.artifact_id == $id and .data.relative_path == "src/value.bin" and
  .data.size_bytes == 15 and .data.commit == $base and
  (.data | keys | sort) == ["artifact_id","commit","relative_path","size_bytes"]
' <<<"$metadata" >/dev/null; then
  printf 'fetch JSON metadata did not match the safe public contract\n' >&2
  exit 1
fi
for unsafe in "$worktree" 'produce the declared artifact' 'artifact\u0000bytes'; do
  if grep -Fq -- "$unsafe" <<<"$metadata"; then
    printf 'fetch metadata leaked unsafe data: %s\n' "$unsafe" >&2
    exit 1
  fi
done

# Raw paths, undeclared opaque IDs, and an artifact from another nonterminal
# job never become filesystem selectors.
assert_fetch_error ARTIFACT_ID_INVALID "$job_id" ../secret --json
undeclared='artifact-000000000000'
[[ "$undeclared" != "$artifact_id" ]] || undeclared='artifact-111111111111'
assert_fetch_error ARTIFACT_NOT_DECLARED "$job_id" "$undeclared" --json
git -C "$worktree" reset -q --hard "$base_sha"
git -C "$worktree" clean -qfd
other_dispatch="$(dispatch_artifact_job)"
other_job="$(jq -r '.data.job_id' <<<"$other_dispatch")"
assert_fetch_error JOB_NOT_ACCEPTED "$other_job" "$artifact_id" --json

# Replacing the declared regular file with a symlink cannot pivot the receipt
# to a secret outside the canonical authorized root.
rm -- "$worktree/src/value.bin"
ln -s -- "$secret" "$worktree/src/value.bin"
assert_fetch_error ARTIFACT_CONTAINMENT "$job_id" "$artifact_id" --json
assert_fetch_error ARTIFACT_CONTAINMENT "$job_id" "$artifact_id" --stdout

# The fixed local fetch cap is 1 MiB. An accepted larger artifact remains in
# the manifest but cannot be read through either public mode.
git -C "$worktree" reset -q --hard "$base_sha"
git -C "$worktree" clean -qfd
large_dispatch="$(dispatch_artifact_job)"
large_job="$(jq -r '.data.job_id' <<<"$large_dispatch")"
head -c 1048577 /dev/zero >"$worktree/src/value.bin"
large_verified="$("$REPO_ROOT/bin/organ" verify "$large_job" --json)"
large_artifact="$(jq -r '.data.artifacts[0].artifact_id' <<<"$large_verified")"
assert_jq "$large_verified" '.state == "accepted" and .data.artifacts[0].size_bytes == 1048577'
assert_fetch_error ARTIFACT_TOO_LARGE "$large_job" "$large_artifact" --json
assert_fetch_error ARTIFACT_TOO_LARGE "$large_job" "$large_artifact" --stdout

# Missing dispatch_complete is normalized only for legacy schema-v1 edit
# receipts. Unknown/null delivery cannot distinguish pre-send from post-send,
# while confirmed delivery proves the old single send returned.
git -C "$worktree" reset -q --hard "$base_sha"
git -C "$worktree" clean -qfd
compat_sends_before="$(wc -l <"$ORGAN_FAKE_SEND_LOG")"
legacy_pending_unknown='local.job-20260816T130000Z-a1b2c3d4'
legacy_pending_unknown_json="$(jq -cn --arg job_id "$legacy_pending_unknown" --arg base "$base_sha" --arg worktree "$worktree" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"edit",
   session_name:"organoun-artifacts",state:"working",delivery:"unknown",artifacts:[],base_sha:$base,worktree:$worktree,
   allow:["src"],verify_command:"true",verification:null}
')"
write_job_receipt "$legacy_pending_unknown" "$legacy_pending_unknown_json"
assert_jq "$(read_job_receipt "$legacy_pending_unknown")" '.dispatch_complete == false and .delivery == "unknown"'
set +e
legacy_unknown_verify="$("$REPO_ROOT/bin/organ" verify "$legacy_pending_unknown" --json 2>&1)"
legacy_unknown_rc=$?
set -e
assert_eq 64 "$legacy_unknown_rc"
assert_jq "$legacy_unknown_verify" '.error.code == "DISPATCH_INCOMPLETE"'
assert_eq "$legacy_pending_unknown_json" "$(<"$ORGAN_STATE_HOME/jobs/$legacy_pending_unknown.json")"

legacy_pending_null='local.job-20260816T130001Z-b1b2c3d4'
legacy_pending_null_json="$(jq -cn --arg job_id "$legacy_pending_null" --arg base "$base_sha" --arg worktree "$worktree" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"edit",
   session_name:"organoun-artifacts",state:"working",delivery:null,artifacts:[],base_sha:$base,worktree:$worktree,
   allow:["src"],verify_command:"true",verification:null}
')"
write_job_receipt "$legacy_pending_null" "$legacy_pending_null_json"
assert_jq "$(read_job_receipt "$legacy_pending_null")" '.dispatch_complete == false and (has("delivery") | not)'
set +e
legacy_null_verify="$("$REPO_ROOT/bin/organ" verify "$legacy_pending_null" --json 2>&1)"
legacy_null_rc=$?
set -e
assert_eq 64 "$legacy_null_rc"
assert_jq "$legacy_null_verify" '.error.code == "DISPATCH_INCOMPLETE"'
assert_eq "$legacy_pending_null_json" "$(<"$ORGAN_STATE_HOME/jobs/$legacy_pending_null.json")"

legacy_pending_confirmed='local.job-20260816T130002Z-c1b2c3d4'
legacy_pending_confirmed_json="$(jq -cn --arg job_id "$legacy_pending_confirmed" --arg base "$base_sha" --arg worktree "$worktree" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"edit",
   session_name:"organoun-artifacts",state:"working",delivery:"confirmed",artifacts:[],base_sha:$base,worktree:$worktree,
   allow:["src"],verify_command:"true",verification:null}
')"
write_job_receipt "$legacy_pending_confirmed" "$legacy_pending_confirmed_json"
legacy_confirmed_read="$(read_job_receipt "$legacy_pending_confirmed")"
assert_jq "$legacy_confirmed_read" '.dispatch_complete == true and .delivery == "confirmed"'
assert_eq "$legacy_pending_confirmed_json" "$(<"$ORGAN_STATE_HOME/jobs/$legacy_pending_confirmed.json")"
printf 'legacy artifact\n' >"$worktree/src/value.bin"
legacy_confirmed_verify="$("$REPO_ROOT/bin/organ" verify "$legacy_pending_confirmed" --json)"
assert_jq "$legacy_confirmed_verify" '.state == "accepted" and .data.accepted == true and (.data.artifacts | length) == 1'
jq -e '.dispatch_complete == true and .state == "accepted"' \
  "$ORGAN_STATE_HOME/jobs/$legacy_pending_confirmed.json" >/dev/null

# A legacy blocked terminal remains readable and idempotent even when its old
# delivery is ambiguous. Terminal verification is sufficient evidence, it has
# no artifacts, and reads/repeated verification never rewrite the raw receipt.
legacy_blocked='local.job-20260816T130003Z-d1b2c3d4'
legacy_blocked_json="$(jq -cn --arg job_id "$legacy_blocked" --arg base "$base_sha" --arg worktree "$worktree" '
  {schema_version:"1",job_id:$job_id,target:"claude-managed",host:"local",mode:"edit",
   session_name:"organoun-artifacts",state:"blocked-scope",delivery:"unknown",artifacts:[],base_sha:$base,worktree:$worktree,
   allow:["src"],verify_command:"true",
   verification:{status:"blocked-scope",accepted:false,changed_paths:["tests/outside.txt"],verify_exit:null,
                 verify_output:"",verify_output_bytes:0,verify_output_truncated:false}}
')"
write_job_receipt "$legacy_blocked" "$legacy_blocked_json"
assert_jq "$(read_job_receipt "$legacy_blocked")" '.dispatch_complete == true and .state == "blocked-scope"'
legacy_blocked_once="$("$REPO_ROOT/bin/organ" verify "$legacy_blocked" --json)"
legacy_blocked_twice="$("$REPO_ROOT/bin/organ" verify "$legacy_blocked" --json)"
assert_eq "$legacy_blocked_once" "$legacy_blocked_twice"
assert_jq "$legacy_blocked_once" '.state == "blocked-scope" and .data.accepted == false and .data.artifacts == []'
assert_eq "$legacy_blocked_json" "$(<"$ORGAN_STATE_HOME/jobs/$legacy_blocked.json")"

# A current explicit false remains authoritative even with confirmed delivery.
explicit_false='local.job-20260816T130004Z-e1b2c3d4'
explicit_false_json="$(jq -cn --argjson receipt "$legacy_pending_confirmed_json" --arg job_id "$explicit_false" \
  '$receipt + {job_id:$job_id,dispatch_complete:false}')"
write_job_receipt "$explicit_false" "$explicit_false_json"
assert_jq "$(read_job_receipt "$explicit_false")" '.dispatch_complete == false and .delivery == "confirmed"'
set +e
explicit_false_verify="$("$REPO_ROOT/bin/organ" verify "$explicit_false" --json 2>&1)"
explicit_false_rc=$?
set -e
assert_eq 64 "$explicit_false_rc"
assert_jq "$explicit_false_verify" '.error.code == "DISPATCH_INCOMPLETE"'
assert_eq "$explicit_false_json" "$(<"$ORGAN_STATE_HOME/jobs/$explicit_false.json")"
assert_eq "$compat_sends_before" "$(wc -l <"$ORGAN_FAKE_SEND_LOG")"

# Compatibility never repairs malformed or contradictory receipts. In
# particular, an explicit false terminal record cannot borrow legacy inference,
# and a missing field does not make an invalid persisted delivery valid.
malformed_terminal='local.job-20260816T130005Z-f1b2c3d4'
malformed_terminal_json="$(jq -cn --argjson receipt "$legacy_accepted" --arg job_id "$malformed_terminal" \
  '$receipt + {job_id:$job_id,dispatch_complete:false}')"
write_job_receipt "$malformed_terminal" "$malformed_terminal_json"
if read_job_receipt "$malformed_terminal" >/dev/null 2>&1; then
  printf 'read accepted an explicit incomplete terminal receipt\n' >&2
  exit 1
fi
assert_fetch_error JOB_NOT_FOUND "$malformed_terminal" "$artifact_id" --json

malformed_delivery='local.job-20260816T130006Z-a2b3c4d5'
malformed_delivery_json="$(jq -cn --argjson receipt "$legacy_pending_unknown_json" --arg job_id "$malformed_delivery" \
  '$receipt + {job_id:$job_id,delivery:"ambiguous"}')"
write_job_receipt "$malformed_delivery" "$malformed_delivery_json"
if read_job_receipt "$malformed_delivery" >/dev/null 2>&1; then
  printf 'read accepted an invalid legacy delivery value\n' >&2
  exit 1
fi
set +e
malformed_verify="$("$REPO_ROOT/bin/organ" verify "$malformed_delivery" --json 2>&1)"
malformed_verify_rc=$?
set -e
assert_eq 64 "$malformed_verify_rc"
assert_jq "$malformed_verify" '.error.code == "JOB_NOT_FOUND"'

# A hermetic failed remote fetch is observationally unreachable and never falls
# through to local artifact state.
remote_job='remote.job-20260816T120000Z-a1b2c3d4'
export ORGAN_SSH=/bin/false
set +e
remote="$("$REPO_ROOT/bin/organ" fetch "$remote_job" artifact-0123456789ab --json 2>&1)"
remote_rc=$?
set -e
unset ORGAN_SSH
assert_eq 69 "$remote_rc"
assert_jq "$remote" '
  .ok == false and .host == "remote.example" and .state == "unreachable" and
  .error.code == "REMOTE_UNREACHABLE"'

printf 'artifact tests passed\n'
