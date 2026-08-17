#!/usr/bin/env bash

organ_control_capture() (
  local stdout_file stderr_file command_rc
  local capture_dir

  capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-control-capture.XXXXXX")" || return 64
  chmod 700 -- "$capture_dir" || {
    rmdir -- "$capture_dir"
    return 64
  }
  trap 'rm -rf -- "$capture_dir"' EXIT
  stdout_file="$capture_dir/stdout"
  stderr_file="$capture_dir/stderr"

  if ! organ_tmux_capture_bounded "$stdout_file" "$stderr_file" "$(organ_tmux_bin)" "$@"; then
    return 64
  fi
  command_rc="$ORGAN_TMUX_CAPTURE_COMMAND_RC"
  [[ "$command_rc" -eq 0 ]] || return 64
  organ_tmux_empty_file_valid "$stderr_file" || return 64
  if LC_ALL=C grep -a -q $'[^\t -~]' -- "$stdout_file" 2>/dev/null; then
    return 64
  fi
  cat -- "$stdout_file"
)

organ_control_owner_record_valid() {
  local record_file="$1"

  [[ -f "$record_file" && ! -L "$record_file" && -r "$record_file" ]] || return 64
  jq -e '
    type == "object"
    and ((keys_unsorted - ["schema_version","owner_id","identity_digest","deployment_digest","session_id","session_name","window_id","window_index","pane_id","pane_pid","pane_cwd","operator_client_id","layout_digest"]) | length == 0)
    and .schema_version == "1"
    and (.owner_id | type == "string" and test("^owner-[0-9a-f]{16}$"))
    and (.identity_digest | type == "string" and test("^[0-9a-f]{64}$"))
    and .owner_id == ("owner-" + .identity_digest[0:16])
    and (.deployment_digest | type == "string" and test("^[0-9a-f]{64}$"))
    and (.session_id | type == "string" and test("^\\$[0-9]+$"))
    and (.session_name | type == "string" and test("^[A-Za-z0-9._-]+$"))
    and (.window_id | type == "string" and test("^@[0-9]+$"))
    and (.window_index | type == "string" and test("^[0-9]+$"))
    and (.pane_id | type == "string" and test("^%[0-9]+$"))
    and (.pane_pid | type == "number" and . > 0 and floor == .)
    and (.pane_cwd | type == "string" and startswith("/"))
    and (.operator_client_id | type == "string" and startswith("/dev/"))
    and (.layout_digest | type == "string" and test("^[0-9a-f]{64}$"))
  ' "$record_file" >/dev/null 2>&1
}

organ_control_owner_write() (
  local record_json="$1"
  local control_dir owner_file lock_dir stage existing_digest new_digest
  local existing_deployment_digest new_deployment_digest

  organ_state_init_subdir control || return 64
  control_dir="$ORGAN_STATE_HOME/control"
  owner_file="$control_dir/owner.json"
  lock_dir="$control_dir/.owner.lock"
  if ! mkdir -- "$lock_dir"; then
    return 64
  fi
  trap 'rm -f -- "${stage:-}"; rmdir -- "$lock_dir" 2>/dev/null || true' EXIT

  new_digest="$(jq -er '.identity_digest' <<<"$record_json")" || return 64
  new_deployment_digest="$(jq -er '.deployment_digest' <<<"$record_json")" || return 64
  if [[ -e "$owner_file" || -L "$owner_file" ]]; then
    organ_control_owner_record_valid "$owner_file" || return 64
    existing_digest="$(jq -er '.identity_digest' "$owner_file")" || return 64
    existing_deployment_digest="$(jq -er '.deployment_digest' "$owner_file")" || return 64
    [[ "$existing_digest" == "$new_digest" &&
      "$existing_deployment_digest" == "$new_deployment_digest" ]] || return 65
    cat -- "$owner_file"
    return 0
  fi

  stage="$(mktemp "$control_dir/.owner.XXXXXX")" || return 64
  chmod 600 -- "$stage" || return 64
  printf '%s\n' "$record_json" >"$stage" || return 64
  organ_control_owner_record_valid "$stage" || return 64
  mv -T -- "$stage" "$owner_file" || return 64
  stage=''
  cat -- "$owner_file"
)

organ_control_init() {
  local deployment_digest="$1"
  local display clients panes client_line owner_record write_rc
  local session_id session_name window_id window_index pane_id pane_pid pane_cwd zoomed layout extra
  local client_session client_window client_tty client_control client_readonly client_extra
  local operator_client_id='' identity_digest owner_id layout_digest data

  [[ "$deployment_digest" =~ ^[0-9a-f]{64}$ ]] || {
    organ_emit_error init "" local ONBOARD_REQUIRED 'a valid project deployment is required before init'
    return 64
  }

  [[ -n "${TMUX:-}" && "${TMUX_PANE:-}" =~ ^%[0-9]+$ ]] || {
    organ_emit_error init "" local CONTROLLER_OWNERSHIP_REQUIRED 'run init from the visible local tmux owner pane'
    return 64
  }

  display="$(organ_control_capture display-message -p -t "$TMUX_PANE" \
    $'#{session_id}\t#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_path}\t#{window_zoomed_flag}\t#{window_layout}')" || {
    organ_emit_error init "" local CONTROLLER_OWNERSHIP_REQUIRED 'could not resolve the local tmux owner identity'
    return 64
  }
  [[ "$display" != *$'\n'* ]] || {
    organ_emit_error init "" local CONTROLLER_OWNERSHIP_REQUIRED 'tmux owner identity was ambiguous'
    return 64
  }
  IFS=$'\t' read -r session_id session_name window_id window_index pane_id pane_pid pane_cwd zoomed layout extra <<<"$display"
  [[ -z "$extra" && "$session_id" =~ ^\$[0-9]+$ && "$session_name" =~ ^[A-Za-z0-9._-]+$ ]] || return 64
  [[ "$window_id" =~ ^@[0-9]+$ && "$window_index" =~ ^[0-9]+$ ]] || return 64
  [[ "$pane_id" == "$TMUX_PANE" && "$pane_pid" =~ ^[0-9]+$ && "$pane_pid" -gt 0 ]] || return 64
  [[ "$pane_cwd" == /* && ! "$pane_cwd" =~ [[:cntrl:]] && "$zoomed" == 0 && -n "$layout" ]] || {
    organ_emit_error init "" local CONTROLLER_PANE_NOT_VISIBLE 'owner pane must be in an attached, non-zoomed tmux window'
    return 64
  }

  clients="$(organ_control_capture list-clients -F \
    $'#{session_id}\t#{window_id}\t#{client_tty}\t#{client_control_mode}\t#{client_readonly}')" || {
    organ_emit_error init "" local OPERATOR_CLIENT_NOT_ATTACHED 'no readable tmux client is attached'
    return 64
  }
  while IFS= read -r client_line; do
    IFS=$'\t' read -r client_session client_window client_tty client_control client_readonly client_extra <<<"$client_line"
    if [[ -z "$client_extra" && "$client_session" == "$session_id" && "$client_window" == "$window_id" &&
      "$client_tty" == /dev/* && "$client_control" == 0 && "$client_readonly" == 0 ]]; then
      operator_client_id="$client_tty"
      break
    fi
  done <<<"$clients"
  [[ -n "$operator_client_id" ]] || {
    organ_emit_error init "" local OPERATOR_CLIENT_NOT_ATTACHED 'operator client is not attached to the owner window'
    return 64
  }

  panes="$(organ_control_capture list-panes -t "$window_id" -F \
    $'#{pane_id}\t#{pane_pid}\t#{pane_dead}\t#{pane_current_command}\t#{pane_current_path}')" || return 64
  printf '%s\n' "$panes" | LC_ALL=C grep -Fq -- "$pane_id" || return 64
  layout_digest="$(printf '%s\n%s\n%s\n' "$session_id" "$layout" "$panes" | sha256sum | awk '{print $1}')"
  identity_digest="$(printf '%s\n' "$TMUX" "$session_id" "$window_id" "$pane_id" "$pane_pid" "$operator_client_id" | sha256sum | awk '{print $1}')"
  owner_id="owner-${identity_digest:0:16}"
  owner_record="$(jq -cn \
    --arg owner_id "$owner_id" --arg identity_digest "$identity_digest" \
    --arg deployment_digest "$deployment_digest" \
    --arg session_id "$session_id" --arg session_name "$session_name" \
    --arg window_id "$window_id" --arg window_index "$window_index" \
    --arg pane_id "$pane_id" --argjson pane_pid "$pane_pid" --arg pane_cwd "$pane_cwd" \
    --arg operator_client_id "$operator_client_id" --arg layout_digest "$layout_digest" \
    '{schema_version:"1",owner_id:$owner_id,identity_digest:$identity_digest,deployment_digest:$deployment_digest,session_id:$session_id,session_name:$session_name,window_id:$window_id,window_index:$window_index,pane_id:$pane_id,pane_pid:$pane_pid,pane_cwd:$pane_cwd,operator_client_id:$operator_client_id,layout_digest:$layout_digest}')"
  if owner_record="$(organ_control_owner_write "$owner_record")"; then
    :
  else
    write_rc=$?
    if [[ "$write_rc" -eq 65 ]]; then
      organ_emit_error init "" local CONTROLLER_OWNERSHIP_MISMATCH 'a different owner is already registered'
    else
      organ_emit_error init "" local CONTROLLER_OWNERSHIP_REQUIRED 'could not persist the owner receipt'
    fi
    return 64
  fi
  data="$(jq -c '{owner_id,session_id,window_id,pane_id,operator_client_id}' <<<"$owner_record")"
  organ_emit_ok init "" local initialized not-applicable "$data"
}

organ_control_owner_live() {
  local owner_file owner display clients panes client_line
  local session_id session_name window_id window_index pane_id pane_pid pane_cwd zoomed layout extra
  local client_session client_window client_tty client_control client_readonly client_extra
  local expected_session expected_window expected_pane expected_pid expected_client layout_digest
  local expected_deployment_digest current_deployment_digest

  owner_file="$ORGAN_STATE_HOME/control/owner.json"
  organ_control_owner_record_valid "$owner_file" || return 64
  owner="$(<"$owner_file")"
  expected_deployment_digest="$(jq -er '.deployment_digest' <<<"$owner")" || return 64
  current_deployment_digest="$(organ_runtime_config_digest)" || return 64
  [[ "$current_deployment_digest" == "$expected_deployment_digest" ]] || return 65
  expected_session="$(jq -er '.session_id' <<<"$owner")" || return 64
  expected_window="$(jq -er '.window_id' <<<"$owner")" || return 64
  expected_pane="$(jq -er '.pane_id' <<<"$owner")" || return 64
  expected_pid="$(jq -er '.pane_pid' <<<"$owner")" || return 64
  expected_client="$(jq -er '.operator_client_id' <<<"$owner")" || return 64
  [[ "${TMUX_PANE:-}" == "$expected_pane" ]] || return 65

  display="$(organ_control_capture display-message -p -t "$expected_pane" \
    $'#{session_id}\t#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_path}\t#{window_zoomed_flag}\t#{window_layout}')" || return 64
  [[ "$display" != *$'\n'* ]] || return 64
  IFS=$'\t' read -r session_id session_name window_id window_index pane_id pane_pid pane_cwd zoomed layout extra <<<"$display"
  [[ -z "$extra" && "$session_id" == "$expected_session" && "$window_id" == "$expected_window" ]] || return 65
  [[ "$pane_id" == "$expected_pane" && "$pane_pid" == "$expected_pid" && "$zoomed" == 0 ]] || return 65
  [[ "$session_name" =~ ^[A-Za-z0-9._-]+$ && "$window_index" =~ ^[0-9]+$ ]] || return 64
  [[ "$pane_cwd" == /* && ! "$pane_cwd" =~ [[:cntrl:]] && -n "$layout" ]] || return 64

  clients="$(organ_control_capture list-clients -F \
    $'#{session_id}\t#{window_id}\t#{client_tty}\t#{client_control_mode}\t#{client_readonly}')" || return 66
  while IFS= read -r client_line; do
    IFS=$'\t' read -r client_session client_window client_tty client_control client_readonly client_extra <<<"$client_line"
    if [[ -z "$client_extra" && "$client_session" == "$expected_session" && "$client_window" == "$expected_window" &&
      "$client_tty" == "$expected_client" && "$client_control" == 0 && "$client_readonly" == 0 ]]; then
      expected_client=''
      break
    fi
  done <<<"$clients"
  [[ -z "$expected_client" ]] || return 66

  panes="$(organ_control_capture list-panes -t "$expected_window" -F \
    $'#{pane_id}\t#{pane_pid}\t#{pane_dead}\t#{pane_current_command}\t#{pane_current_path}')" || return 64
  LC_ALL=C awk -F '\t' -v pane="$expected_pane" -v pid="$expected_pid" \
    '$1 == pane && $2 == pid && $3 == 0 { found=1 } END { exit !found }' <<<"$panes" || return 65
  layout_digest="$(printf '%s\n%s\n%s\n' "$expected_session" "$layout" "$panes" | sha256sum | awk '{print $1}')"
  jq -cn --argjson owner "$owner" --arg layout_digest "$layout_digest" --arg panes "$panes" \
    --arg current_owner_cwd "$pane_cwd" \
    '$owner + {current_layout_digest:$layout_digest,current_panes:$panes,current_owner_cwd:$current_owner_cwd}'
}

organ_control_panes_init() (
  local control_dir panes_dir

  organ_state_init_subdir control || return 64
  control_dir="$ORGAN_STATE_HOME/control"
  panes_dir="$control_dir/panes"
  [[ -d "$control_dir" && ! -L "$control_dir" ]] || return 64
  if [[ -e "$panes_dir" || -L "$panes_dir" ]]; then
    [[ -d "$panes_dir" && ! -L "$panes_dir" ]] || return 64
  else
    umask 077
    mkdir -- "$panes_dir" || return 64
  fi
  chmod 700 -- "$panes_dir"
)

organ_control_nonce() {
  local nonce

  nonce="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')" || return 64
  [[ "$nonce" =~ ^[0-9a-f]{32}$ ]] || return 64
  printf '%s\n' "$nonce"
}

organ_control_pane_record_valid() {
  local alias="$1"
  local record_file="$2"

  [[ -f "$record_file" && ! -L "$record_file" && -r "$record_file" ]] || return 64
  jq -e --arg alias "$alias" '
    type == "object"
    and ((keys_unsorted - ["schema_version","alias","owner_id","owner_identity_digest","target_digest","transport","host","endpoint_cwd","provider","model_policy","pane_id","pane_pid","state","pending_action","operation_id","attestation_nonce","layout_digest","send_attempted","send_delivery","message_digest"]) | length == 0)
    and .schema_version == "1"
    and .alias == $alias
    and (.owner_id | test("^owner-[0-9a-f]{16}$"))
    and (.owner_identity_digest | test("^[0-9a-f]{64}$"))
    and .owner_id == ("owner-" + .owner_identity_digest[0:16])
    and (.target_digest | test("^[0-9a-f]{64}$"))
    and (.transport == "local" or .transport == "ssh")
    and (.host | type == "string" and length > 0)
    and (.endpoint_cwd | type == "string" and startswith("/"))
    and .provider == "cc"
    and (.model_policy | type == "string" and length > 0)
    and (.pane_id | test("^%[0-9]+$"))
    and (.pane_pid | type == "number" and . > 0 and floor == .)
    and (.operation_id | test("^op-[0-9a-f]{16}$"))
    and (.layout_digest | test("^[0-9a-f]{64}$"))
    and (.send_attempted | type == "boolean")
    and (
      (
        .send_attempted == false
        and .send_delivery == null
        and .message_digest == null
      )
      or
      (
        .send_attempted == true
        and (.send_delivery == "pending" or .send_delivery == "unknown" or .send_delivery == "confirmed" or .send_delivery == "blocked" or .send_delivery == "failed")
        and (.message_digest | test("^[0-9a-f]{64}$"))
      )
    )
    and (
      (
        .state == "reserved"
        and .pending_action == "session.enter"
        and (.attestation_nonce | test("^[0-9a-f]{32}$"))
      )
      or
      (
        .state == "entered"
        and .pending_action == null
        and .attestation_nonce == null
      )
    )
  ' "$record_file" >/dev/null 2>&1
}

organ_control_pane_write() (
  local alias="$1"
  local record_json="$2"
  local panes_dir record_file lock_dir pane_stage

  organ_alias_valid "$alias" || return 64
  organ_control_panes_init || return 64
  panes_dir="$ORGAN_STATE_HOME/control/panes"
  record_file="$panes_dir/$alias.json"
  lock_dir="$panes_dir/.$alias.lock"
  mkdir -- "$lock_dir" || return 64
  trap 'rm -f -- "${pane_stage:-}"; rmdir -- "$lock_dir" 2>/dev/null || true' EXIT
  [[ ! -e "$record_file" && ! -L "$record_file" ]] || return 65
  pane_stage="$(mktemp "$panes_dir/.$alias.XXXXXX")" || return 64
  chmod 600 -- "$pane_stage" || return 64
  printf '%s\n' "$record_json" >"$pane_stage" || return 64
  organ_control_pane_record_valid "$alias" "$pane_stage" || return 64
  mv -T -- "$pane_stage" "$record_file" || return 64
  pane_stage=''
)

organ_control_pane_replace_locked() (
  local alias="$1"
  local record_json="$2"
  local panes_dir record_file replace_stage

  organ_alias_valid "$alias" || return 64
  panes_dir="$ORGAN_STATE_HOME/control/panes"
  record_file="$panes_dir/$alias.json"
  [[ -d "$panes_dir" && ! -L "$panes_dir" && -f "$record_file" && ! -L "$record_file" ]] || return 64
  replace_stage="$(mktemp "$panes_dir/.$alias.replace.XXXXXX")" || return 64
  trap 'rm -f -- "${replace_stage:-}"' EXIT
  chmod 600 -- "$replace_stage" || return 64
  printf '%s\n' "$record_json" >"$replace_stage" || return 64
  organ_control_pane_record_valid "$alias" "$replace_stage" || return 64
  mv -T -- "$replace_stage" "$record_file" || return 64
  replace_stage=''
)

organ_control_reserve() {
  local target_json="$1"
  local owner alias host transport endpoint_cwd provider model_policy window_id owner_cwd
  local split_output pane_id pane_pid pane_cwd extra live layout_digest target_digest nonce operation_digest operation_id
  local record data write_rc

  alias="$(jq -er '.alias' <<<"$target_json")" || return 64
  host="$(jq -er '.host' <<<"$target_json")" || return 64
  transport="$(jq -er '.transport' <<<"$target_json")" || return 64
  endpoint_cwd="$(jq -er '.cwd' <<<"$target_json")" || return 64
  provider="$(jq -er '.provider' <<<"$target_json")" || return 64
  [[ "$(jq -r '.mode' <<<"$target_json")" == managed && "$provider" == cc ]] || {
    organ_emit_error reserve "$alias" "$host" MANAGED_TARGET_REQUIRED 'reserve requires a managed cc target'
    return 64
  }
  model_policy="$(jq -r '.model // "provider-default"' <<<"$target_json")"

  if owner="$(organ_control_owner_live)"; then
    :
  else
    case "$?" in
      65) organ_emit_error reserve "$alias" "$host" CONTROLLER_OWNERSHIP_MISMATCH 'command did not originate from the registered owner' ;;
      66) organ_emit_error reserve "$alias" "$host" OPERATOR_CLIENT_NOT_ATTACHED 'operator client is not attached to the visible owner window' ;;
      *) organ_emit_error reserve "$alias" "$host" CONTROLLER_OWNERSHIP_REQUIRED 'initialize and preserve the local owner before reserving layout' ;;
    esac
    return 64
  fi
  window_id="$(jq -er '.window_id' <<<"$owner")" || return 64
  owner_cwd="$(jq -er '.pane_cwd' <<<"$owner")" || return 64

  split_output="$(organ_control_capture split-window -t "$window_id" -c "$owner_cwd" -P -F \
    $'#{pane_id}\t#{pane_pid}\t#{pane_current_path}')" || {
    organ_emit_error reserve "$alias" "$host" MANIFEST_INVALID 'could not reserve a local subordinate pane'
    return 64
  }
  [[ "$split_output" != *$'\n'* ]] || return 64
  IFS=$'\t' read -r pane_id pane_pid pane_cwd extra <<<"$split_output"
  [[ -z "$extra" && "$pane_id" =~ ^%[0-9]+$ && "$pane_pid" =~ ^[0-9]+$ && "$pane_pid" -gt 0 ]] || return 64
  [[ "$pane_cwd" == /* && ! "$pane_cwd" =~ [[:cntrl:]] ]] || return 64

  live="$(organ_control_owner_live)" || {
    organ_control_capture kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    organ_emit_error reserve "$alias" "$host" TARGET_PANE_NOT_VISIBLE 'reserved pane is not simultaneously visible with the owner'
    return 64
  }
  LC_ALL=C awk -F '\t' -v pane="$pane_id" -v pid="$pane_pid" \
    '$1 == pane && $2 == pid && $3 == 0 { found=1 } END { exit !found }' <<<"$(jq -r '.current_panes' <<<"$live")" || {
    organ_control_capture kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    return 64
  }
  layout_digest="$(jq -er '.current_layout_digest' <<<"$live")" || return 64
  target_digest="$(printf '%s\n' "$target_json" | sha256sum | awk '{print $1}')"
  nonce="$(organ_control_nonce)" || return 64
  operation_digest="$(printf '%s\n' "$(jq -r '.owner_id' <<<"$owner")" "$alias" session.enter "$layout_digest" "$nonce" | sha256sum | awk '{print $1}')"
  operation_id="op-${operation_digest:0:16}"
  record="$(jq -cn \
    --arg alias "$alias" --arg owner_id "$(jq -r '.owner_id' <<<"$owner")" \
    --arg owner_identity_digest "$(jq -r '.identity_digest' <<<"$owner")" \
    --arg target_digest "$target_digest" --arg transport "$transport" --arg host "$host" \
    --arg endpoint_cwd "$endpoint_cwd" --arg provider "$provider" --arg model_policy "$model_policy" \
    --arg pane_id "$pane_id" --argjson pane_pid "$pane_pid" --arg operation_id "$operation_id" \
    --arg attestation_nonce "$nonce" --arg layout_digest "$layout_digest" \
    '{schema_version:"1",alias:$alias,owner_id:$owner_id,owner_identity_digest:$owner_identity_digest,target_digest:$target_digest,transport:$transport,host:$host,endpoint_cwd:$endpoint_cwd,provider:$provider,model_policy:$model_policy,pane_id:$pane_id,pane_pid:$pane_pid,state:"reserved",pending_action:"session.enter",operation_id:$operation_id,attestation_nonce:$attestation_nonce,layout_digest:$layout_digest,send_attempted:false,send_delivery:null,message_digest:null}')"
  if ! organ_control_pane_write "$alias" "$record"; then
    write_rc=$?
    organ_control_capture kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    if [[ "$write_rc" -eq 65 ]]; then
      organ_emit_error reserve "$alias" "$host" MANIFEST_INVALID 'target already has a reserved subordinate pane'
    else
      organ_emit_error reserve "$alias" "$host" MANIFEST_INVALID 'could not persist the subordinate pane receipt'
    fi
    return 64
  fi
  data="$(jq -c '{owner_id,pane_id,operation_id,attestation_nonce,layout_digest}' <<<"$record")"
  organ_emit_ok reserve "$alias" "$host" reserved not-applicable "$data"
}

organ_control_enter() (
  local target_json="$1"
  local attestation_nonce="$2"
  local alias host transport endpoint_cwd provider model_policy target_digest
  local panes_dir record_file action_lock record live layout_digest pane_line
  local pane_id pane_pid pane_pid_live pane_dead pane_command pane_cwd pane_extra owner_cwd
  local remote_command endpoint_command quoted_cwd quoted_host quoted_model quoted_remote
  local post_live post_line post_pid post_dead post_command post_cwd post_extra
  local entered_record data

  alias="$(jq -er '.alias' <<<"$target_json")" || return 64
  host="$(jq -er '.host' <<<"$target_json")" || return 64
  transport="$(jq -er '.transport' <<<"$target_json")" || return 64
  endpoint_cwd="$(jq -er '.cwd' <<<"$target_json")" || return 64
  provider="$(jq -er '.provider' <<<"$target_json")" || return 64
  model_policy="$(jq -r '.model // "provider-default"' <<<"$target_json")" || return 64
  [[ "$(jq -r '.mode' <<<"$target_json")" == managed && "$provider" == cc ]] || return 64
  [[ "$attestation_nonce" =~ ^[0-9a-f]{32}$ ]] || {
    organ_emit_error enter "$alias" "$host" OPERATOR_ATTESTATION_INVALID 'attestation does not match the visible reserve operation'
    return 64
  }
  [[ "$endpoint_cwd" =~ ^/[A-Za-z0-9._/-]+$ ]] || {
    organ_emit_error enter "$alias" "$host" TARGET_COMMAND_INVALID 'endpoint cwd is not safe for a visible pane command'
    return 64
  }
  [[ "$model_policy" == provider-default || "$model_policy" =~ ^[A-Za-z0-9._:/-]+$ ]] || {
    organ_emit_error enter "$alias" "$host" TARGET_COMMAND_INVALID 'model policy is not safe for a visible pane command'
    return 64
  }

  organ_control_panes_init || return 64
  panes_dir="$ORGAN_STATE_HOME/control/panes"
  record_file="$panes_dir/$alias.json"
  action_lock="$panes_dir/.$alias.action.lock"
  if ! mkdir -- "$action_lock"; then
    organ_emit_error enter "$alias" "$host" OPERATION_IN_PROGRESS 'another operation is active for this pane'
    return 64
  fi
  trap 'rmdir -- "$action_lock" 2>/dev/null || true' EXIT
  organ_control_pane_record_valid "$alias" "$record_file" || {
    organ_emit_error enter "$alias" "$host" OPERATOR_ATTESTATION_INVALID 'attestation does not match an active reserve operation'
    return 64
  }
  record="$(<"$record_file")"
  [[ "$(jq -r '.state' <<<"$record")" == reserved &&
    "$(jq -r '.pending_action' <<<"$record")" == session.enter &&
    "$(jq -r '.attestation_nonce' <<<"$record")" == "$attestation_nonce" ]] || {
    organ_emit_error enter "$alias" "$host" OPERATOR_ATTESTATION_INVALID 'attestation does not match the visible reserve operation'
    return 64
  }
  target_digest="$(printf '%s\n' "$target_json" | sha256sum | awk '{print $1}')"
  [[ "$(jq -r '.target_digest' <<<"$record")" == "$target_digest" &&
    "$(jq -r '.transport' <<<"$record")" == "$transport" &&
    "$(jq -r '.host' <<<"$record")" == "$host" &&
    "$(jq -r '.endpoint_cwd' <<<"$record")" == "$endpoint_cwd" &&
    "$(jq -r '.provider' <<<"$record")" == "$provider" &&
    "$(jq -r '.model_policy' <<<"$record")" == "$model_policy" ]] || {
    organ_emit_error enter "$alias" "$host" TARGET_CHANGED 'target changed after the visible pane was reserved'
    return 64
  }

  if ! live="$(organ_control_owner_live)"; then
    organ_emit_error enter "$alias" "$host" OPERATOR_VISIBILITY_REQUIRED 'owner and reserved pane must remain visible to the operator'
    return 64
  fi
  layout_digest="$(jq -er '.current_layout_digest' <<<"$live")" || return 64
  [[ "$layout_digest" == "$(jq -r '.layout_digest' <<<"$record")" ]] || {
    organ_emit_error enter "$alias" "$host" OPERATOR_ATTESTATION_STALE 'visible layout changed after reserve; reserve again'
    return 64
  }
  pane_id="$(jq -er '.pane_id' <<<"$record")" || return 64
  pane_pid="$(jq -er '.pane_pid' <<<"$record")" || return 64
  pane_line="$(jq -r '.current_panes' <<<"$live" | LC_ALL=C awk -F '\t' -v pane="$pane_id" '$1 == pane {print}')"
  [[ -n "$pane_line" && "$pane_line" != *$'\n'* ]] || return 64
  IFS=$'\t' read -r pane_id pane_pid_live pane_dead pane_command pane_cwd pane_extra <<<"$pane_line"
  [[ -z "$pane_extra" && "$pane_pid_live" == "$pane_pid" && "$pane_dead" == 0 && "$pane_command" == bash ]] || {
    organ_emit_error enter "$alias" "$host" RESERVED_PANE_CHANGED 'reserved pane is no longer empty and owned'
    return 64
  }
  owner_cwd="$(jq -er '.current_owner_cwd' <<<"$live")" || return 64
  [[ "$owner_cwd" == /* && ! "$owner_cwd" =~ [[:cntrl:]] ]] || return 64

  endpoint_command='exec claude'
  if [[ "$model_policy" != provider-default ]]; then
    printf -v quoted_model '%q' "$model_policy"
    endpoint_command+=" --model $quoted_model"
  fi
  if [[ "$transport" == ssh ]]; then
    organ_deployment_host_valid "$host" || return 64
    printf -v quoted_cwd '%q' "$endpoint_cwd"
    printf -v quoted_host '%q' "$host"
    remote_command="unset CLAUDE_MODEL ANTHROPIC_MODEL && cd -- $quoted_cwd && $endpoint_command"
    printf -v quoted_remote '%q' "$remote_command"
    pane_command="exec ssh -tt -- $quoted_host $quoted_remote"
    pane_cwd="$owner_cwd"
  else
    [[ "$host" == local ]] || return 64
    pane_command="unset CLAUDE_MODEL ANTHROPIC_MODEL && $endpoint_command"
    pane_cwd="$endpoint_cwd"
  fi

  if ! organ_control_capture respawn-pane -k -t "$pane_id" -c "$pane_cwd" "$pane_command" >/dev/null; then
    organ_emit_error enter "$alias" "$host" ENDPOINT_START_FAILED 'could not start the endpoint in the visible pane'
    return 64
  fi
  if ! post_live="$(organ_control_owner_live)"; then
    organ_control_capture kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    organ_emit_error enter "$alias" "$host" OPERATOR_VISIBILITY_REQUIRED 'endpoint pane was not visible after startup'
    return 64
  fi
  post_line="$(jq -r '.current_panes' <<<"$post_live" | LC_ALL=C awk -F '\t' -v pane="$pane_id" '$1 == pane {print}')"
  [[ -n "$post_line" && "$post_line" != *$'\n'* ]] || return 64
  IFS=$'\t' read -r pane_id post_pid post_dead post_command post_cwd post_extra <<<"$post_line"
  [[ -z "$post_extra" && "$post_pid" =~ ^[0-9]+$ && "$post_pid" -gt 0 && "$post_dead" == 0 &&
    "$post_command" =~ ^[A-Za-z0-9._/+:-]+$ && "$post_cwd" == /* && ! "$post_cwd" =~ [[:cntrl:]] ]] || {
    organ_control_capture kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    return 64
  }
  entered_record="$(jq -c --argjson pane_pid "$post_pid" \
    --arg layout_digest "$(jq -r '.current_layout_digest' <<<"$post_live")" \
    '.pane_pid=$pane_pid | .state="entered" | .pending_action=null | .attestation_nonce=null | .layout_digest=$layout_digest' \
    <<<"$record")" || return 64
  if ! organ_control_pane_replace_locked "$alias" "$entered_record"; then
    organ_control_capture kill-pane -t "$pane_id" >/dev/null 2>&1 || true
    organ_emit_error enter "$alias" "$host" MANIFEST_INVALID 'could not consume the operator attestation safely'
    return 64
  fi
  data="$(jq -cn --arg pane_id "$pane_id" --arg transport "$transport" --arg endpoint_cwd "$endpoint_cwd" \
    '{pane_id:$pane_id,transport:$transport,endpoint_cwd:$endpoint_cwd}')"
  organ_emit_ok enter "$alias" "$host" entered not-applicable "$data"
)

organ_control_route_available() {
  local alias="$1"
  local record_file

  organ_alias_valid "$alias" || return 1
  record_file="$ORGAN_STATE_HOME/control/panes/$alias.json"
  [[ -e "$record_file" || -L "$record_file" ]]
}

organ_control_endpoint_context() {
  local target_json="$1"
  local alias record_file record target_digest live pane_id pane_pid pane_line
  local live_pane live_pid live_dead live_command live_cwd live_extra endpoint_display
  local endpoint_pane endpoint_pid endpoint_session endpoint_window endpoint_index endpoint_extra tmux_target synthetic_target

  alias="$(jq -er '.alias' <<<"$target_json")" || return 64
  record_file="$ORGAN_STATE_HOME/control/panes/$alias.json"
  organ_control_pane_record_valid "$alias" "$record_file" || return 64
  record="$(<"$record_file")"
  [[ "$(jq -r '.state' <<<"$record")" == entered ]] || return 64
  target_digest="$(printf '%s\n' "$target_json" | sha256sum | awk '{print $1}')"
  [[ "$(jq -r '.target_digest' <<<"$record")" == "$target_digest" ]] || return 64
  live="$(organ_control_owner_live)" || return 64
  [[ "$(jq -r '.owner_id' <<<"$record")" == "$(jq -r '.owner_id' <<<"$live")" &&
    "$(jq -r '.layout_digest' <<<"$record")" == "$(jq -r '.current_layout_digest' <<<"$live")" ]] || return 64
  pane_id="$(jq -er '.pane_id' <<<"$record")" || return 64
  pane_pid="$(jq -er '.pane_pid' <<<"$record")" || return 64
  pane_line="$(jq -r '.current_panes' <<<"$live" | LC_ALL=C awk -F '\t' -v pane="$pane_id" '$1 == pane {print}')"
  [[ -n "$pane_line" && "$pane_line" != *$'\n'* ]] || return 64
  IFS=$'\t' read -r live_pane live_pid live_dead live_command live_cwd live_extra <<<"$pane_line"
  [[ -z "$live_extra" && "$live_pane" == "$pane_id" && "$live_pid" == "$pane_pid" && "$live_dead" == 0 &&
    "$live_command" =~ ^[A-Za-z0-9._/+:-]+$ && "$live_cwd" == /* && ! "$live_cwd" =~ [[:cntrl:]] ]] || return 64

  endpoint_display="$(organ_control_capture display-message -p -t "$pane_id" \
    $'#{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_index}\t#{pane_index}')" || return 64
  [[ "$endpoint_display" != *$'\n'* ]] || return 64
  IFS=$'\t' read -r endpoint_pane endpoint_pid endpoint_session endpoint_window endpoint_index endpoint_extra <<<"$endpoint_display"
  [[ -z "$endpoint_extra" && "$endpoint_pane" == "$pane_id" && "$endpoint_pid" == "$pane_pid" &&
    "$endpoint_session" == "$(jq -r '.session_name' <<<"$live")" &&
    "$endpoint_window" == "$(jq -r '.window_index' <<<"$live")" && "$endpoint_index" =~ ^[0-9]+$ ]] || return 64
  tmux_target="$endpoint_session:$endpoint_window.$endpoint_index"
  synthetic_target="$(jq -cn --arg alias "$alias" --arg host "$(jq -r '.host' <<<"$record")" \
    --arg cwd "$(jq -r '.current_owner_cwd' <<<"$live")" --arg tmux_target "$tmux_target" \
    '{alias:$alias,transport:"local",host:$host,cwd:$cwd,mode:"adopted",tmux_target:$tmux_target,claude_session_id:null}')" || return 64
  jq -cn --argjson record "$record" --argjson target "$synthetic_target" \
    '{record:$record,target:$target}'
}

organ_control_route() (
  local action="$1"
  local target_json="$2"
  local payload_file="$3"
  local options_json="$4"
  local alias host panes_dir action_lock context synthetic_target record output route_rc post_context
  local message_digest pending_record final_delivery final_record

  alias="$(jq -er '.alias' <<<"$target_json")" || return 64
  host="$(jq -er '.host' <<<"$target_json")" || return 64
  case "$action" in status|read|claim|ask|release) ;; *) return 69 ;; esac
  if [[ "$action" == claim || "$action" == ask || "$action" == release ]]; then
    organ_control_panes_init || return 64
    panes_dir="$ORGAN_STATE_HOME/control/panes"
    action_lock="$panes_dir/.$alias.action.lock"
    if ! mkdir -- "$action_lock"; then
      organ_emit_error "$action" "$alias" "$host" OPERATION_IN_PROGRESS 'another operation is active for this pane'
      return 64
    fi
    trap 'rmdir -- "$action_lock" 2>/dev/null || true' EXIT
  fi
  if ! context="$(organ_control_endpoint_context "$target_json")"; then
    organ_emit_error "$action" "$alias" "$host" OPERATOR_VISIBILITY_REQUIRED 'owned endpoint pane is not live and visible to the operator'
    return 64
  fi
  synthetic_target="$(jq -c '.target' <<<"$context")" || return 64
  record="$(jq -c '.record' <<<"$context")" || return 64

  if [[ "$action" == ask ]]; then
    if [[ "$(jq -r '.send_attempted' <<<"$record")" == true ]]; then
      organ_emit_error ask "$alias" "$host" MESSAGE_ALREADY_ATTEMPTED 'this visible endpoint already has a send attempt; observe it and never replay'
      return 64
    fi
    organ_text_file_valid "$payload_file" || return 64
    message_digest="$(sha256sum -- "$payload_file" | awk '{print $1}')" || return 64
    pending_record="$(jq -c --arg message_digest "$message_digest" \
      '.send_attempted=true | .send_delivery="pending" | .message_digest=$message_digest' <<<"$record")" || return 64
    if ! organ_control_pane_replace_locked "$alias" "$pending_record"; then
      organ_emit_error ask "$alias" "$host" MANIFEST_INVALID 'could not persist the send obligation before delivery'
      return 64
    fi
  fi

  if output="$(organ_local "$action" "$synthetic_target" "$payload_file" "$options_json")"; then
    route_rc=0
  else
    route_rc=$?
  fi
  if [[ "$action" == ask ]]; then
    if [[ "$route_rc" -eq 0 ]] && final_delivery="$(jq -er '.delivery | select(. == "unknown" or . == "confirmed" or . == "blocked")' <<<"$output")"; then
      :
    else
      final_delivery=failed
    fi
    final_record="$(jq -c --arg delivery "$final_delivery" '.send_delivery=$delivery' <<<"$pending_record")" || return 64
    if ! organ_control_pane_replace_locked "$alias" "$final_record"; then
      organ_emit_error ask "$alias" "$host" MANIFEST_INVALID 'send was attempted but its final delivery state could not be persisted'
      return 64
    fi
  fi
  if ! post_context="$(organ_control_endpoint_context "$target_json")"; then
    organ_emit_error "$action" "$alias" "$host" OPERATOR_VISIBILITY_REQUIRED 'endpoint lost operator visibility during the operation'
    return 64
  fi
  : "$post_context"
  printf '%s\n' "$output"
  return "$route_rc"
)

organ_control_close() (
  local target_json="$1"
  local alias host panes_dir record_file action_lock context record claim_path pane_id owner_id post_live data

  alias="$(jq -er '.alias' <<<"$target_json")" || return 64
  host="$(jq -er '.host' <<<"$target_json")" || return 64
  organ_control_panes_init || return 64
  panes_dir="$ORGAN_STATE_HOME/control/panes"
  record_file="$panes_dir/$alias.json"
  if [[ ! -e "$record_file" && ! -L "$record_file" ]]; then
    organ_emit_error close "$alias" "$host" MANAGED_PANE_NOT_FOUND 'no Organoun-owned pane exists for this target'
    return 64
  fi
  action_lock="$panes_dir/.$alias.action.lock"
  if ! mkdir -- "$action_lock"; then
    organ_emit_error close "$alias" "$host" OPERATION_IN_PROGRESS 'another operation is active for this pane'
    return 64
  fi
  trap 'rmdir -- "$action_lock" 2>/dev/null || true' EXIT
  if ! context="$(organ_control_endpoint_context "$target_json")"; then
    organ_emit_error close "$alias" "$host" OPERATOR_VISIBILITY_REQUIRED 'owned endpoint pane is not live and visible to the operator'
    return 64
  fi
  record="$(jq -c '.record' <<<"$context")" || return 64
  claim_path="$(organ_claim_path "$alias")" || return 64
  if [[ -e "$claim_path" || -L "$claim_path" ]]; then
    if organ_claim_read "$alias" >/dev/null; then
      organ_emit_error close "$alias" "$host" CLAIM_ACTIVE 'release the active external-session claim before closing this pane'
    else
      organ_emit_error close "$alias" "$host" CLAIM_STATE_INVALID 'claim state is unsafe or invalid; refusing to close the pane'
    fi
    return 64
  fi

  pane_id="$(jq -er '.pane_id' <<<"$record")" || return 64
  owner_id="$(jq -er '.owner_id' <<<"$record")" || return 64
  if ! organ_control_capture kill-pane -t "$pane_id" >/dev/null; then
    organ_emit_error close "$alias" "$host" PANE_CLOSE_FAILED 'could not close the exact Organoun-owned pane'
    return 64
  fi
  if ! post_live="$(organ_control_owner_live)"; then
    organ_emit_error close "$alias" "$host" OWNER_VISIBILITY_LOST 'owner visibility could not be proven after pane close'
    return 64
  fi
  if LC_ALL=C awk -F '\t' -v pane="$pane_id" '$1 == pane {found=1} END {exit !found}' \
    <<<"$(jq -r '.current_panes' <<<"$post_live")"; then
    organ_emit_error close "$alias" "$host" PANE_CLOSE_UNCONFIRMED 'the owned pane is still present after close'
    return 64
  fi
  [[ -f "$record_file" && ! -L "$record_file" ]] || return 64
  rm -f -- "$record_file" || return 64
  data="$(jq -cn --arg pane_id "$pane_id" --arg owner_id "$owner_id" \
    --arg layout_digest "$(jq -r '.current_layout_digest' <<<"$post_live")" \
    '{pane_id:$pane_id,owner_id:$owner_id,layout_digest:$layout_digest}')"
  organ_emit_ok close "$alias" "$host" closed not-applicable "$data"
)
