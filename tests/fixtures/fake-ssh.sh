#!/usr/bin/env bash
set -euo pipefail

umask 077

: "${ORGAN_FAKE_SSH_COUNT:?}"
: "${ORGAN_FAKE_SSH_ARGV:?}"
: "${ORGAN_FAKE_SSH_REQUEST:?}"

count=0
if [[ -f "$ORGAN_FAKE_SSH_COUNT" ]]; then
  count="$(<"$ORGAN_FAKE_SSH_COUNT")"
fi
printf '%s\n' "$((count + 1))" >"$ORGAN_FAKE_SSH_COUNT"
printf '%s\0' "$@" >"$ORGAN_FAKE_SSH_ARGV"

request_file="$ORGAN_FAKE_SSH_REQUEST"
response_file="${ORGAN_FAKE_SSH_REQUEST}.response"
trap 'rm -f -- "$response_file"' EXIT
cat >"$request_file"

[[ "$#" -eq 8 ]] || exit 70
[[ "$1" == -T && "$2" == -o && "$3" == BatchMode=yes ]] || exit 70
[[ "$4" == -o && "$5" == ConnectTimeout=10 && "$6" == -- ]] || exit 70
[[ "$7" == remote.example ]] || exit 70
[[ "$8" == "${ORGAN_REMOTE_HELPER:?}" ]] || exit 70

case "${ORGAN_FAKE_SSH_MODE:-execute}" in
  fail-before)
    exit 255
    ;;
  hang-no-output|ceiling-then-hang)
    if [[ "${ORGAN_FAKE_SSH_MODE}" == ceiling-then-hang ]]; then
      set +e
      head -c 2097153 /dev/zero | tr '\0' x
      set -e
    fi
    trap '' TERM
    parent_stat="$(<"/proc/$BASHPID/stat")"
    parent_stat="${parent_stat##*) }"
    read -r -a parent_fields <<<"$parent_stat"
    printf '%s %s\n' "$BASHPID" "${parent_fields[19]}" >"${ORGAN_FAKE_SSH_PARENT_PID_FILE:?}"
    # shellcheck disable=SC2016 # Process identity expands in the inner shell.
    setsid -- bash -c '
      trap "" TERM
      child_stat=$(<"/proc/$BASHPID/stat")
      child_stat=${child_stat##*) }
      read -r -a child_fields <<<"$child_stat"
      printf "%s %s\n" "$BASHPID" "${child_fields[19]}" >"$1"
      exec sleep 600
    ' fake-ssh-escaped "${ORGAN_FAKE_SSH_CHILD_PID_FILE:?}" &
    wait
    ;;
  multiline-comm-hang)
    trap '' TERM
    parent_stat="$(<"/proc/$BASHPID/stat")"
    parent_stat="${parent_stat##*) }"
    read -r -a parent_fields <<<"$parent_stat"
    printf '%s %s\n' "$BASHPID" "${parent_fields[19]}" >"${ORGAN_FAKE_SSH_PARENT_PID_FILE:?}"
    setsid -- "${ORGAN_FAKE_SSH_MULTILINE_HELPER:?}" \
      "${ORGAN_FAKE_SSH_CHILD_PID_FILE:?}" &
    wait
    ;;
esac

remote_env=(
  ORGAN_CONFIG="${ORGAN_FAKE_REMOTE_CONFIG:?}"
  ORGAN_STATE_HOME="${ORGAN_FAKE_REMOTE_STATE:?}"
  ORGAN_OUTSOURCERER="${ORGAN_FAKE_REMOTE_OUTSOURCERER:?}"
  ORGAN_TMUX="${ORGAN_FAKE_REMOTE_TMUX:?}"
  ORGAN_PROC_ROOT="${ORGAN_FAKE_REMOTE_PROC_ROOT:?}"
  ORGAN_SESSION_POLL_INTERVAL=0
  ORGAN_FAKE_LOG="${ORGAN_FAKE_REMOTE_OSRC_LOG:?}"
  ORGAN_FAKE_COMMAND_LOG="${ORGAN_FAKE_REMOTE_COMMAND_LOG:?}"
  ORGAN_FAKE_SEND_LOG="${ORGAN_FAKE_REMOTE_SEND_LOG:?}"
  ORGAN_FAKE_TMUX_LOG="${ORGAN_FAKE_REMOTE_TMUX_LOG:?}"
  ORGAN_FAKE_TMUX_STATE_FILE="${ORGAN_FAKE_REMOTE_TMUX_STATE:?}"
  ORGAN_FAKE_PANE_ID="${ORGAN_FAKE_REMOTE_PANE_ID:-%82}"
  ORGAN_FAKE_PANE_PID="${ORGAN_FAKE_REMOTE_PANE_PID:-8282}"
  ORGAN_FAKE_PID_START="${ORGAN_FAKE_REMOTE_PID_START:-982}"
  ORGAN_FAKE_CLAIM_TOKEN="${ORGAN_FAKE_REMOTE_CLAIM_TOKEN:-remote-secret-claim-token}"
  ORGAN_FAKE_TMUX_OUTPUT="${ORGAN_FAKE_REMOTE_TMUX_OUTPUT:-❯}"
)

set +e
env "${remote_env[@]}" "$8" <"$request_file" >"$response_file"
helper_rc=$?
set -e

case "${ORGAN_FAKE_SSH_MODE:-execute}" in
  execute)
    cat -- "$response_file"
    exit "$helper_rc"
    ;;
  valid-nonzero)
    cat -- "$response_file"
    exit 255
    ;;
  fail-after)
    exit 255
    ;;
  prefix)
    printf 'untrusted-prefix'
    cat -- "$response_file"
    exit 0
    ;;
  suffix)
    cat -- "$response_file"
    printf 'untrusted-suffix'
    exit 0
    ;;
  multiple)
    cat -- "$response_file" "$response_file"
    exit 0
    ;;
  malformed)
    printf '{not-json}\n'
    exit 0
    ;;
  invalid-schema)
    printf '{}\n'
    exit 0
    ;;
  duplicate-top)
    sed 's/^{/{"schema_version":"0",/' "$response_file"
    exit 0
    ;;
  duplicate-error)
    printf '%s\n' '{"schema_version":"1","ok":false,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","error":{"\u0063ode":"IGNORED","code":"REMOTE_TEST_ERROR","message":"duplicate error key"}}'
    exit 64
    ;;
  invalid-utf8-error)
    printf '{"schema_version":"1","ok":false,"action":"stop","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","error":{"code":"REMOTE_TEST_ERROR","message":"invalid\377utf8"}}\n'
    exit 64
    ;;
  invalid-utf8-status)
    printf '{"schema_version":"1","ok":false,"action":"status","target":"remote-managed","host":"remote.example","state":"unknown","delivery":"not-applicable","error":{"code":"REMOTE_TEST_ERROR","message":"invalid\377utf8"}}\n'
    exit 64
    ;;
  duplicate-dispatch-data)
    printf '%s\n' '{"schema_version":"1","ok":true,"action":"dispatch","target":"remote-managed","host":"remote.example","state":"working","delivery":"unknown","data":{"\u006aob_id":"remote.job-20260816T120000Z-deadbeef","job_id":"remote.job-20260816T120000Z-deadbeef"}}'
    exit 0
    ;;
  duplicate-verify-artifact)
    sed 's/"host":"remote.example"/"\\u0068ost":"remote.example","host":"remote.example"/2' "$response_file"
    exit 0
    ;;
  duplicate-frame-header)
    sed '1s/^{/{"\\u0068ost":"remote.example",/' "$response_file"
    exit 0
    ;;
  invalid-utf8-frame)
    printf '{"host":"invalid\377","host":"remote.example",'
    tail -c +2 -- "$response_file"
    exit 0
    ;;
  wrong-job)
    jq -c '.data.job_id = "remote.job-20260816T120000Z-deadbeef"' "$response_file"
    exit 0
    ;;
  wrong-artifact)
    jq -c '.data.artifact_id = "artifact-deadbeefcafe"' "$response_file"
    exit 0
    ;;
  oversized)
    head -c 2097153 /dev/zero | tr '\0' x
    exit 0
    ;;
  *)
    exit 70
    ;;
esac
