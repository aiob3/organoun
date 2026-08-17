#!/usr/bin/env bash

organ_local() {
  local action="$1"
  local target_json="$2"
  local payload_file="$3"
  local options_json="${4:-}"
  local alias host adapter state data code message edit_payload guard_json guard_prompt_json

  [[ -n "$options_json" ]] || options_json='{}'

  alias="$(jq -r '.alias' <<<"$target_json")"
  host="$(jq -r '.host' <<<"$target_json")"
  if [[ "$action" == ask || "$action" == dispatch ]]; then
    if ! organ_text_file_valid "$payload_file"; then
      if [[ "$action" == ask ]]; then
        code=ASK_INVALID_TEXT
      else
        code=DISPATCH_INVALID_TEXT
      fi
      organ_emit_error "$action" "$alias" "$host" "$code" "$action payload must be NUL-free valid UTF-8 text"
      return 64
    fi
    if (( $(wc -c <"$payload_file") > ORGAN_MAX_ASK_BYTES )); then
      if [[ "$action" == ask ]]; then
        code=ASK_TOO_LARGE
      else
        code=DISPATCH_TOO_LARGE
      fi
      organ_emit_error "$action" "$alias" "$host" "$code" "$action payload exceeds byte limit"
      return 64
    fi
  fi
  if [[ "$action" == dispatch && "$(jq -r '.mode // "read"' <<<"$options_json")" == edit ]]; then
    guard_json="$(jq -c '.guard' <<<"$options_json")"
    guard_prompt_json="$(jq -c '{worktree,allow}' <<<"$guard_json")"
    umask 077
    edit_payload="$(mktemp "${TMPDIR:-/tmp}/organoun-edit-prompt.XXXXXX")" || {
      organ_emit_error "$action" "$alias" "$host" "DISPATCH_PREPARE_FAILED" "could not prepare guarded edit request"
      return 64
    }
    {
      printf '%s\n' 'Organoun guarded edit request.'
      printf 'Guard: %s\n' "$guard_prompt_json"
      printf '%s\n' 'Edit only the allowed relative paths in the explicit worktree. The controller will audit the Git diff and run verification.'
      printf '%s\n' 'Request:'
      cat -- "$payload_file"
    } >"$edit_payload"
    adapter="$(organ_osrc "$action" "$target_json" "$edit_payload" "$options_json")"
    rm -f -- "$edit_payload"
  else
    adapter="$(organ_osrc "$action" "$target_json" "$payload_file" "$options_json")"
  fi
  if [[ "$(jq -r '.ok' <<<"$adapter")" != true ]]; then
    code="$(jq -r '.code' <<<"$adapter")"
    message="$(jq -r '.message' <<<"$adapter")"
    organ_emit_error "$action" "$alias" "$host" "$code" "$message"
    return 64
  fi

  state="$(jq -r '.state' <<<"$adapter")"
  case "$action" in
    status)
      data='{}'
      ;;
    read)
      data="$(jq -c '{excerpt:.excerpt,truncated:.truncated}' <<<"$adapter")"
      ;;
    claim|ask|release|stop)
      data='{}'
      ;;
    dispatch)
      data="$(jq -c '{job_id:.job_id}' <<<"$adapter")"
      ;;
    *)
      organ_emit_error "$action" "$alias" "$host" "ACTION_UNAVAILABLE" "action is not available yet"
      return 64
      ;;
  esac
  if [[ "$action" == claim || "$action" == ask || "$action" == release || "$action" == dispatch ]]; then
    organ_emit_ok "$action" "$alias" "$host" "$state" "$(jq -r '.delivery' <<<"$adapter")" "$data"
  else
    organ_emit_ok "$action" "$alias" "$host" "$state" "not-applicable" "$data"
  fi
}

organ_route() {
  local action="$1"
  local target_json="$2"
  local payload_file="$3"
  local _options_json="$4"
  local transport alias host

  transport="$(jq -r '.transport' <<<"$target_json")"
  alias="$(jq -r '.alias' <<<"$target_json")"
  if organ_control_route_available "$alias"; then
    case "$action" in
      status|read|claim|ask|release) ;;
      *)
        host="$(jq -r '.host' <<<"$target_json")"
        organ_emit_error "$action" "$alias" "$host" VISIBLE_PROTOCOL_ACTION_REQUIRED 'use the visible reserve/enter/claim/ask/read/release/close protocol'
        return 64
        ;;
    esac
    organ_control_route "$action" "$target_json" "$payload_file" "$_options_json"
    return
  fi
  host="$(jq -r '.host' <<<"$target_json")"
  [[ "$transport" == local || "$transport" == ssh ]] || {
    organ_emit_error "$action" "$alias" "$host" TRANSPORT_UNAVAILABLE 'transport is not available'
    return 64
  }
  organ_emit_error "$action" "$alias" "$host" VISIBLE_PANE_REQUIRED 'reserve and enter an operator-visible local pane before using this endpoint'
  return 64
}

organ_local_verify_job() {
  local job_id="$1"
  local receipt target host state data

  receipt="$(organ_job_route verify "$job_id" '{}')" || return $?
  target="$(jq -r '.target' <<<"$receipt")"
  host="$(jq -r '.host' <<<"$receipt")"
  state="$(jq -r '.state' <<<"$receipt")"
  data="$(jq -c '{job_id:.job_id} + .verification + {artifacts:.artifacts}' <<<"$receipt")"
  organ_emit_ok verify "$target" "$host" "$state" not-applicable "$data"
}

organ_local_fetch_json() {
  local job_id="$1"
  local artifact_id="$2"
  local receipt metadata target host options

  receipt="$(organ_job_read "$job_id")" || return 64
  options="$(jq -cn --arg artifact_id "$artifact_id" '{artifact_id:$artifact_id,mode:"json"}')"
  metadata="$(organ_job_route fetch "$job_id" "$options")" || return $?
  target="$(jq -r '.target' <<<"$receipt")"
  host="$(jq -r '.host' <<<"$receipt")"
  organ_emit_ok fetch "$target" "$host" accepted not-applicable "$metadata"
}
