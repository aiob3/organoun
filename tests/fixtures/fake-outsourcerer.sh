#!/usr/bin/env bash
set -euo pipefail

fake_env_value() {
  local name="$1"
  if [[ -v "$name" ]]; then
    printf '<%s>' "$(printenv "$name")"
  else
    printf '<unset>'
  fi
}

printf '%q\0' "$@" >>"$ORGAN_FAKE_LOG"
if [[ -n "${ORGAN_FAKE_COMMAND_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$ORGAN_FAKE_COMMAND_LOG"
fi
if [[ -n "${ORGAN_FAKE_ENV_LOG:-}" ]]; then
  printf 'send=%s controller=%s token=%s composer=%s receipt=%s\n' \
    "$(fake_env_value OSRC_EXTERNAL_SEND)" \
    "$(fake_env_value OSRC_CONTROLLER_ID)" \
    "$(fake_env_value OSRC_SESSION_CLAIM_TOKEN)" \
    "$(fake_env_value OSRC_EXTERNAL_COMPOSER_PROBE)" \
    "$(fake_env_value OSRC_EXTERNAL_RECEIPT_PROBE)" >>"$ORGAN_FAKE_ENV_LOG"
fi
if [[ -n "${ORGAN_FAKE_MANAGED_ENV_LOG:-}" ]]; then
  printf 'tmux=%s send=%s controller=%s token=%s composer=%s receipt=%s osrc_provider=%s osrc_model=%s osrc_default_provider=%s osrc_default_model=%s provider=%s model=%s default_provider=%s default_model=%s claude_model=%s anthropic_model=%s\n' \
    "$(fake_env_value OUTSOURCERER_TMUX)" \
    "$(fake_env_value OSRC_EXTERNAL_SEND)" \
    "$(fake_env_value OSRC_CONTROLLER_ID)" \
    "$(fake_env_value OSRC_SESSION_CLAIM_TOKEN)" \
    "$(fake_env_value OSRC_EXTERNAL_COMPOSER_PROBE)" \
    "$(fake_env_value OSRC_EXTERNAL_RECEIPT_PROBE)" \
    "$(fake_env_value OSRC_PROVIDER)" \
    "$(fake_env_value OSRC_MODEL)" \
    "$(fake_env_value OSRC_DEFAULT_PROVIDER)" \
    "$(fake_env_value OSRC_DEFAULT_MODEL)" \
    "$(fake_env_value OUTSOURCERER_PROVIDER)" \
    "$(fake_env_value OUTSOURCERER_MODEL)" \
    "$(fake_env_value OUTSOURCERER_DEFAULT_PROVIDER)" \
    "$(fake_env_value OUTSOURCERER_DEFAULT_MODEL)" \
    "$(fake_env_value CLAUDE_MODEL)" \
    "$(fake_env_value ANTHROPIC_MODEL)" >>"$ORGAN_FAKE_MANAGED_ENV_LOG"
fi
if [[ -n "${ORGAN_FAKE_CWD_LOG:-}" ]]; then
  printf '%s\n' "$PWD" >>"$ORGAN_FAKE_CWD_LOG"
fi

fake_managed_state_write() {
  local exists="$1"
  local temporary

  [[ -n "${ORGAN_FAKE_TMUX_STATE_FILE:-}" ]] || return 0
  temporary="$(mktemp "${ORGAN_FAKE_TMUX_STATE_FILE}.XXXXXX")"
  if [[ "$exists" == true ]]; then
    jq -cn --arg session_name "${ORGAN_FAKE_LIVE_SESSION_NAME:-$OUTSOURCERER_TMUX}" \
      --arg cwd "${ORGAN_FAKE_LIVE_CWD:-$PWD}" \
      --arg pane_id "${ORGAN_FAKE_PANE_ID:-%12}" --argjson pane_pid "${ORGAN_FAKE_PANE_PID:-4242}" \
      '{exists:true,session_name:$session_name,cwd:$cwd,pane_id:$pane_id,pane_pid:$pane_pid}' >"$temporary"
  else
    jq -cn '{exists:false}' >"$temporary"
  fi
  mv -f -- "$temporary" "$ORGAN_FAKE_TMUX_STATE_FILE"
}

fake_proc_start_write() {
  local pid="${ORGAN_FAKE_PANE_PID:-4242}"
  local marker="${ORGAN_FAKE_PID_START:-777}"

  [[ -n "${ORGAN_PROC_ROOT:-}" ]] || return 0
  mkdir -p -- "$ORGAN_PROC_ROOT/$pid"
  {
    printf '%s (fake-claude) S' "$pid"
    printf ' 0%.0s' {4..21}
    printf ' %s\n' "$marker"
  } >"$ORGAN_PROC_ROOT/$pid/stat"
}

fake_wait_gate() {
  local gate="$1"

  [[ -n "$gate" ]] || return 0
  mkdir -p -- "$gate"
  touch "$gate/entered"
  while [[ ! -e "$gate/release" ]]; do
    sleep 0.01
  done
}

if [[ "$*" =~ ^--provider\ cc(\ -m\ [^[:space:]]+)?\ session\ start$ ]]; then
  if [[ -n "${ORGAN_FAKE_START_GATE:-}" ]]; then
    touch "$ORGAN_FAKE_START_GATE/entered"
    while [[ ! -e "$ORGAN_FAKE_START_GATE/release" ]]; do
      sleep 0.01
    done
  fi
  if [[ "${ORGAN_FAKE_START_CREATES_SESSION:-1}" == 1 ]]; then
    fake_managed_state_write true
    fake_proc_start_write
  fi
  printf '%s\n' "${ORGAN_FAKE_START_OUTPUT:-Session started: $OUTSOURCERER_TMUX}"
  exit 0
fi

case "$*" in
  "fleet ls --json") printf '%s\n' '{"items":[{"session_id":"cc-1","state":"working"}]}' ;;
  "fleet show cc-1 --json")
    if [[ -n "${ORGAN_FAKE_FLEET_SHOW_OUTPUT:-}" ]]; then
      printf '%s\n' "$ORGAN_FAKE_FLEET_SHOW_OUTPUT"
    else
      printf '%s\n' '{"session_id":"cc-1","state":"idle","cwd":"/workspace/project"}'
    fi
    ;;
  "session read --state")
    fake_wait_gate "${ORGAN_FAKE_READ_GATE:-}"
    if [[ -n "${ORGAN_FAKE_READ_RC:-}" ]]; then
      printf '%s\n' "${ORGAN_FAKE_READ_ERROR:-fake managed read failed}" >&2
      exit "$ORGAN_FAKE_READ_RC"
    fi
    jq -cn --arg state "${ORGAN_FAKE_READ_STATE:-idle}" '{state:$state,evidence:"fake managed state"}'
    if [[ "${ORGAN_FAKE_MUTATE_AFTER_READ:-0}" == 1 ]]; then
      ORGAN_FAKE_PANE_PID="${ORGAN_FAKE_MUTATE_PANE_PID:-5252}"
      ORGAN_FAKE_PID_START="${ORGAN_FAKE_MUTATE_PID_START:-852}"
      fake_managed_state_write true
      fake_proc_start_write
    fi
    ;;
  "session send "*)
    fake_wait_gate "${ORGAN_FAKE_SEND_GATE:-}"
    if [[ -n "${ORGAN_FAKE_PAYLOAD_FILE:-}" ]]; then
      printf '%s' "${3-}" >"$ORGAN_FAKE_PAYLOAD_FILE"
    fi
    if [[ -n "${ORGAN_FAKE_SEND_LOG:-}" ]]; then
      printf 'sent\n' >>"$ORGAN_FAKE_SEND_LOG"
    fi
    printf '%s\n' "${ORGAN_FAKE_SEND_OUTPUT:-keys delivered, not independently verified}"
    ;;
  "session stop")
    if [[ "${ORGAN_FAKE_STOP_KEEPS_SESSION:-0}" != 1 ]]; then
      fake_managed_state_write false
    fi
    printf '%s\n' "${ORGAN_FAKE_STOP_OUTPUT:-Session stopped: $OUTSOURCERER_TMUX}"
    ;;
  "session claim "*) printf 'claim token: %s\n' "${ORGAN_FAKE_CLAIM_TOKEN:-secret-claim-token}" ;;
  "session reply "*)
    probe_state="${OSRC_EXTERNAL_COMPOSER_PROBE:+$("$OSRC_EXTERNAL_COMPOSER_PROBE" "${ORGAN_FAKE_REPLY_PANE:-tmux:1.3}")}" || probe_state=unknown
    if [[ "$probe_state" != empty ]]; then
      printf '%s\n' "${ORGAN_FAKE_REPLY_BLOCKED_OUTPUT:-composer unavailable}"
      exit 0
    fi
    if [[ -n "${ORGAN_FAKE_PAYLOAD_FILE:-}" ]]; then
      printf '%s' "${4-}" >"$ORGAN_FAKE_PAYLOAD_FILE"
    fi
    if [[ -n "${ORGAN_FAKE_SEND_LOG:-}" ]]; then
      printf 'sent\n' >>"$ORGAN_FAKE_SEND_LOG"
    fi
    if [[ -n "${OSRC_EXTERNAL_RECEIPT_PROBE:-}" ]]; then
      "$OSRC_EXTERNAL_RECEIPT_PROBE" >/dev/null
      printf '%s\n' "${ORGAN_FAKE_REPLY_RECEIPT_OUTPUT:-receipt: fake-receipt}"
    else
      printf '%s\n' "${ORGAN_FAKE_REPLY_OUTPUT:-delivery unknown}"
    fi
    ;;
  "session release "*)
    if [[ -v ORGAN_FAKE_RELEASE_OUTPUT ]]; then
      printf '%s\n' "$ORGAN_FAKE_RELEASE_OUTPUT"
    else
      printf "claim released for '%s'\n" "${3-}"
    fi
    ;;
  *) printf 'unexpected fake call: %s\n' "$*" >&2; exit 70 ;;
esac
