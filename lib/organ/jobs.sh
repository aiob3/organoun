#!/usr/bin/env bash

organ_job_id_valid() {
  [[ "$1" =~ ^(local|remote)\.job-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$ ]]
}

organ_job_route_class() {
  local job_id="$1"

  organ_job_id_valid "$job_id" || return 64
  printf '%s\n' "${job_id%%.*}"
}

organ_job_path() {
  local job_id="$1"

  organ_job_id_valid "$job_id" || return 64
  printf '%s/jobs/%s.json\n' "$ORGAN_STATE_HOME" "$job_id"
}

organ_job_normalize_legacy() {
  local record_json="$1"

  jq -ce '
    if type == "object" and .schema_version == "1" and .mode == "edit" and
       (has("dispatch_complete") | not)
    then
      . + {dispatch_complete:
        (if .verification != null then true
         elif .delivery == "confirmed" then true
         else false
         end)} |
      if .delivery == null then del(.delivery) else . end
    else
      .
    end
  ' <<<"$record_json"
}

organ_job_record_valid() {
  local record_json="$1"

  jq -e '
    def valid_relative_path:
      type == "string" and length > 0 and (startswith("/") | not) and . != "." and
      (split("/") | all(. != "" and . != "." and . != ".." and . != ".git"));
    def valid_state:
      . == "unknown" or . == "idle" or . == "working" or . == "waiting" or
      . == "done" or . == "stopped" or . == "unreachable" or
      . == "delivery-unknown" or . == "accepted" or . == "blocked-scope" or
      . == "blocked-verification";
    def valid_delivery:
      . == "not-applicable" or . == "confirmed" or . == "blocked" or . == "unknown";
    def valid_artifact:
      type == "object" and
      (keys_unsorted | sort) == ["artifact_id","commit","host","relative_path","size_bytes"] and
      (.artifact_id | type == "string" and test("^artifact-[a-f0-9]{12}$")) and
      (.host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$")) and
      (.relative_path | valid_relative_path) and
      (.size_bytes | type == "number" and . >= 0 and floor == .) and
      (.commit | type == "string" and test("^[0-9a-f]{40}$"));
    def valid_verification:
      type == "object" and
      (keys_unsorted | sort) == ["accepted","changed_paths","status","verify_exit","verify_output","verify_output_bytes","verify_output_truncated"] and
      (.status == "accepted" or .status == "blocked-scope" or .status == "blocked-verification") and
      (.accepted | type == "boolean") and
      (.changed_paths | type == "array" and all(.[]; valid_relative_path) and unique == .) and
      (.verify_output | type == "string" and utf8bytelength <= 65536) and
      (.verify_output_bytes | type == "number" and . >= 0 and floor == .) and
      (.verify_output_truncated | type == "boolean") and
      (if .status == "accepted" then
         .accepted == true and .verify_exit == 0
       elif .status == "blocked-scope" then
         .accepted == false and .verify_exit == null and .verify_output == "" and
         .verify_output_bytes == 0 and .verify_output_truncated == false
       else
         .accepted == false and (.verify_exit | type == "number" and . >= 1 and . <= 255 and floor == .)
       end) and
      (if .verify_output_truncated then .verify_output_bytes > 65536 else .verify_output_bytes <= 65536 end);
    . as $record |
    type == "object"
    and ((keys_unsorted - ["schema_version","job_id","target","route","host","mode","session_name","state","delivery","artifacts","base_sha","worktree","allow","verify_command","verification","dispatch_complete"]) | length == 0)
    and ((["schema_version","job_id","target","route","host","mode","session_name","state","artifacts"] - keys_unsorted) | length == 0)
    and .schema_version == "1"
    and (.job_id | type == "string" and test("^(local|remote)\\.job-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$"))
    and (.route == "local" or .route == "remote")
    and (.host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"))
    and ($record.job_id | startswith($record.route + ".job-"))
    and (if .route == "local" then .host == "local" else .host != "local" end)
    and (.target | type == "string" and test("^[A-Za-z0-9._-]+$"))
    and (.mode == "read" or .mode == "edit")
    and (.session_name | type == "string" and length > 0 and (test("[[:cntrl:]]") | not))
    and (.state | valid_state)
    and ((has("delivery") | not) or (.delivery | valid_delivery))
    and (.artifacts | type == "array" and all(.[]; valid_artifact))
    and ([.artifacts[].artifact_id] | unique | length) == (.artifacts | length)
    and ([.artifacts[].relative_path] | unique | length) == (.artifacts | length)
    and all(.artifacts[]; .host == $record.host and .commit == $record.base_sha)
    and (if .mode == "read" then
           ((keys_unsorted - ["schema_version","job_id","target","route","host","mode","session_name","state","delivery","artifacts"]) | length == 0) and
           .artifacts == []
         else
           ((["base_sha","worktree","allow","verify_command","verification","dispatch_complete"] - keys_unsorted) | length == 0) and
           (.base_sha | type == "string" and test("^[0-9a-f]{40}$")) and
           (.worktree | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not)) and
           (.allow | type == "array" and length > 0 and all(.[]; valid_relative_path) and unique == .) and
           (.verify_command | type == "string" and length > 0) and
           (.dispatch_complete | type == "boolean") and
           (.verification == null or (.verification | valid_verification)) and
           (if .verification == null then
              .state != "accepted" and .state != "blocked-scope" and .state != "blocked-verification" and .artifacts == []
            else
              .dispatch_complete == true and .state == .verification.status and
              (if .state == "accepted" then true else .artifacts == [] end)
            end)
         end)
  ' >/dev/null <<<"$record_json"
}

organ_job_new_id() {
  local route="$1"
  local timestamp nonce job_id job_path attempt=0

  [[ "$route" == local || "$route" == remote ]] || return 64
  organ_state_init_subdir jobs || return 64
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)" || return 64
  while (( attempt < 100 )); do
    ((attempt += 1))
    printf -v nonce '%04x%04x' "$RANDOM" "$RANDOM"
    job_id="$route.job-$timestamp-$nonce"
    job_path="$(organ_job_path "$job_id")" || return 64
    if [[ ! -e "$job_path" && ! -L "$job_path" ]]; then
      printf '%s\n' "$job_id"
      return 0
    fi
  done
  return 64
}

organ_job_create() {
  local receipt_json="$1"
  local job_id job_path job_dir temporary

  organ_job_record_valid "$receipt_json" || return 64
  job_id="$(jq -r '.job_id' <<<"$receipt_json")"
  organ_state_init_subdir jobs || return 64
  organ_state_subdir_safe jobs || return 64
  job_path="$(organ_job_path "$job_id")" || return 64
  if [[ -e "$job_path" || -L "$job_path" ]]; then
    return 73
  fi
  job_dir="${job_path%/*}"
  umask 077
  temporary="$(mktemp "$job_dir/.${job_id}.XXXXXX")" || return 64
  if ! printf '%s\n' "$receipt_json" >"$temporary"; then
    rm -f -- "$temporary"
    return 64
  fi
  chmod 600 -- "$temporary" || {
    rm -f -- "$temporary"
    return 64
  }
  organ_state_subdir_safe jobs || {
    rm -f -- "$temporary"
    return 64
  }
  if ln -- "$temporary" "$job_path" 2>/dev/null; then
    rm -f -- "$temporary"
    return 0
  fi
  if [[ -e "$job_path" || -L "$job_path" ]]; then
    rm -f -- "$temporary"
    return 73
  fi
  rm -f -- "$temporary"
  return 64
}

organ_job_create_read() {
  local target="$1"
  local host="$2"
  local session_name="$3"
  local route attempt=0 job_id receipt_json create_rc

  organ_alias_valid "$target" || return 64
  organ_deployment_host_valid "$host" || return 64
  if [[ "$host" == local ]]; then route=local; else route=remote; fi
  [[ -n "$session_name" && ! "$session_name" =~ [[:cntrl:]] ]] || return 64
  while (( attempt < 100 )); do
    ((attempt += 1))
    job_id="$(organ_job_new_id "$route")" || return 64
    receipt_json="$(jq -cn --arg job_id "$job_id" --arg target "$target" --arg route "$route" --arg host "$host" \
      --arg session_name "$session_name" \
      '{schema_version:"1",job_id:$job_id,target:$target,route:$route,host:$host,mode:"read",session_name:$session_name,state:"working",delivery:"unknown",artifacts:[]}')"
    if organ_job_create "$receipt_json"; then
      printf '%s\n' "$job_id"
      return 0
    else
      create_rc=$?
    fi
    [[ "$create_rc" -eq 73 ]] || return "$create_rc"
  done
  return 64
}

organ_job_create_edit() {
  local target="$1"
  local host="$2"
  local session_name="$3"
  local guard_json="$4"
  local route attempt=0 job_id receipt_json create_rc

  organ_alias_valid "$target" || return 64
  organ_deployment_host_valid "$host" || return 64
  if [[ "$host" == local ]]; then route=local; else route=remote; fi
  [[ -n "$session_name" && ! "$session_name" =~ [[:cntrl:]] ]] || return 64
  jq -e '
    type == "object" and
    (keys_unsorted | sort) == ["allow","base_sha","verify_command","worktree"] and
    (.base_sha | type == "string" and test("^[0-9a-f]{40}$")) and
    (.worktree | type == "string" and startswith("/")) and
    (.allow | type == "array" and length > 0) and
    (.verify_command | type == "string" and length > 0)
  ' >/dev/null <<<"$guard_json" || return 64
  while (( attempt < 100 )); do
    ((attempt += 1))
    job_id="$(organ_job_new_id "$route")" || return 64
    receipt_json="$(jq -cn --arg job_id "$job_id" --arg target "$target" --arg route "$route" --arg host "$host" \
      --arg session_name "$session_name" --argjson guard "$guard_json" \
      '{schema_version:"1",job_id:$job_id,target:$target,route:$route,host:$host,mode:"edit",session_name:$session_name,
        state:"working",delivery:"unknown",artifacts:[],base_sha:$guard.base_sha,worktree:$guard.worktree,
        allow:$guard.allow,verify_command:$guard.verify_command,verification:null,dispatch_complete:false}')"
    if organ_job_create "$receipt_json"; then
      printf '%s\n' "$job_id"
      return 0
    else
      create_rc=$?
    fi
    [[ "$create_rc" -eq 73 ]] || return "$create_rc"
  done
  return 64
}

organ_job_replace() {
  local receipt_json="$1"
  local job_id job_path job_dir temporary

  organ_job_record_valid "$receipt_json" || return 64
  job_id="$(jq -r '.job_id' <<<"$receipt_json")"
  organ_state_subdir_safe jobs || return 64
  job_path="$(organ_job_path "$job_id")" || return 64
  [[ -f "$job_path" && ! -L "$job_path" ]] || return 64
  job_dir="${job_path%/*}"
  umask 077
  temporary="$(mktemp "$job_dir/.${job_id}.XXXXXX")" || return 64
  if ! printf '%s\n' "$receipt_json" >"$temporary"; then
    rm -f -- "$temporary"
    return 64
  fi
  chmod 600 -- "$temporary" || {
    rm -f -- "$temporary"
    return 64
  }
  organ_state_subdir_safe jobs || {
    rm -f -- "$temporary"
    return 64
  }
  if ! mv -f -- "$temporary" "$job_path"; then
    rm -f -- "$temporary"
    return 64
  fi
}

organ_job_lock() {
  local job_id="$1"
  local lock_path

  organ_job_id_valid "$job_id" || return 64
  organ_state_init_subdir locks || return 64
  organ_state_subdir_safe locks || return 64
  lock_path="$ORGAN_STATE_HOME/locks/job-$job_id.lock"
  if [[ -e "$lock_path" || -L "$lock_path" ]]; then
    [[ -f "$lock_path" && ! -L "$lock_path" ]] || return 64
  else
    umask 077
    : >"$lock_path" || return 64
  fi
  chmod 600 -- "$lock_path" || return 64
  exec {ORGAN_JOB_LOCK_FD}<>"$lock_path" || return 64
  flock -x "$ORGAN_JOB_LOCK_FD" || {
    exec {ORGAN_JOB_LOCK_FD}>&-
    return 64
  }
}

organ_job_unlock() {
  if [[ -n "${ORGAN_JOB_LOCK_FD:-}" ]]; then
    exec {ORGAN_JOB_LOCK_FD}>&-
  fi
}

organ_job_read() {
  local job_id="$1"
  local job_path receipt_json

  job_path="$(organ_job_path "$job_id")" || return 64
  organ_state_subdir_safe jobs || return 64
  [[ -f "$job_path" && ! -L "$job_path" ]] || return 64
  [[ "$(stat -c '%a' -- "$job_path")" == 600 ]] || return 64
  receipt_json="$(jq -ce . "$job_path")" || return 64
  receipt_json="$(organ_job_normalize_legacy "$receipt_json")" || return 64
  organ_job_record_valid "$receipt_json" || return 64
  [[ "$(jq -r '.job_id' <<<"$receipt_json")" == "$job_id" ]] || return 64
  printf '%s\n' "$receipt_json"
}

organ_job_update() {
  local job_id="$1"
  local patch_json="$2"
  local receipt_json updated_json

  jq -e '
    type == "object"
    and ((keys_unsorted - ["state","delivery","artifacts","dispatch_complete"]) | length == 0)
    and length > 0
  ' >/dev/null <<<"$patch_json" || return 64
  organ_job_lock "$job_id" || return 64
  if ! receipt_json="$(organ_job_read "$job_id")"; then
    organ_job_unlock
    return 64
  fi
  if ! updated_json="$(jq -cn --argjson receipt "$receipt_json" --argjson patch "$patch_json" '$receipt + $patch')"; then
    organ_job_unlock
    return 64
  fi
  if ! organ_job_record_valid "$updated_json" || ! organ_job_replace "$updated_json"; then
    organ_job_unlock
    return 64
  fi
  organ_job_unlock
}

organ_job_verify() {
  local job_id="$1"
  local receipt_json verification artifacts status updated_json

  organ_job_lock "$job_id" || return 64
  if ! receipt_json="$(organ_job_read "$job_id")"; then
    organ_job_unlock
    return 64
  fi
  if [[ "$(jq -r '.mode' <<<"$receipt_json")" != edit ]]; then
    organ_job_unlock
    return 65
  fi
  if [[ "$(jq -r '.dispatch_complete' <<<"$receipt_json")" != true ]]; then
    organ_job_unlock
    return 67
  fi
  if [[ "$(jq -r '.verification == null' <<<"$receipt_json")" == true ]]; then
    if ! verification="$(organ_guard_verify "$receipt_json")"; then
      organ_job_unlock
      return 66
    fi
    status="$(jq -r '.status' <<<"$verification")"
    if [[ "$status" == accepted ]]; then
      if ! artifacts="$(organ_artifacts_manifest "$receipt_json" "$verification")"; then
        organ_job_unlock
        return 66
      fi
    else
      artifacts='[]'
    fi
    if ! updated_json="$(jq -cn --argjson receipt "$receipt_json" --arg status "$status" \
      --argjson verification "$verification" --argjson artifacts "$artifacts" \
      '$receipt + {state:$status,verification:$verification,artifacts:$artifacts}')" ||
       ! organ_job_record_valid "$updated_json" ||
       ! organ_job_replace "$updated_json"; then
      organ_job_unlock
      return 66
    fi
    receipt_json="$updated_json"
  fi
  organ_job_unlock
  printf '%s\n' "$receipt_json"
}

organ_job_route() {
  local action="$1"
  local job_id="$2"
  local options_json="$3"
  local route

  route="$(organ_job_route_class "$job_id")" || return 64
  case "$route:$action" in
    local:read)
      organ_job_read "$job_id"
      ;;
    local:update)
      organ_job_update "$job_id" "$options_json"
      ;;
    local:verify)
      [[ "$options_json" == '{}' ]] || return 64
      organ_job_verify "$job_id"
      ;;
    local:fetch)
      jq -e '
        type == "object" and (keys_unsorted | sort) == ["artifact_id","mode"] and
        (.artifact_id | type == "string") and (.mode == "stdout" or .mode == "json")
      ' >/dev/null <<<"$options_json" || return 64
      local receipt_json artifact_id mode
      receipt_json="$(organ_job_read "$job_id")" || return 64
      artifact_id="$(jq -r '.artifact_id' <<<"$options_json")"
      mode="$(jq -r '.mode' <<<"$options_json")"
      organ_artifact_fetch "$receipt_json" "$artifact_id" "$mode"
      ;;
    remote:verify|remote:fetch)
      return 69
      ;;
    remote:*)
      return 64
      ;;
    *)
      return 64
      ;;
  esac
}
