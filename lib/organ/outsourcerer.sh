#!/usr/bin/env bash

ORGAN_MAX_READ_CAPTURE_BYTES="${ORGAN_MAX_READ_CAPTURE_BYTES:-$((${ORGAN_MAX_READ_BYTES:-65536} + 4096))}"

organ_osrc_bin() {
  local default="${ORGAN_ROOT}/vendor/outsourcerer/outsourcerer.sh"
  printf '%s\n' "${ORGAN_OUTSOURCERER:-$default}"
}

organ_tmux_bin() {
  printf '%s\n' "${ORGAN_TMUX:-tmux}"
}

organ_osrc_adopted_target() {
  local target_json="$1"
  [[ "$(jq -r '.mode' <<<"$target_json")" == adopted ]]
}

organ_osrc_composer_probe() {
  local probe="${ORGAN_CLAUDE_COMPOSER_PROBE:-${ORGAN_ROOT}/probes/claude-composer-empty}"
  [[ "$probe" == /* && -f "$probe" && -x "$probe" ]] || return 64
  printf '%s\n' "$probe"
}

organ_osrc_receipt_probe() {
  local probe="${ORGAN_EXTERNAL_RECEIPT_PROBE:-}"
  if [[ -z "$probe" ]]; then
    return 0
  fi
  [[ "$probe" == /* && -f "$probe" && -x "$probe" ]] || return 64
  printf '%s\n' "$probe"
}

organ_osrc_private_output() {
  umask 077
  mktemp "${TMPDIR:-/tmp}/organoun-command.XXXXXX"
}

organ_osrc_claim() {
  local target_json="$1"
  local alias cwd tmux_target controller output_file rc output token record

  if ! organ_osrc_adopted_target "$target_json"; then
    jq -cn '{ok:false,code:"ADOPTED_TARGET_REQUIRED",message:"action requires an adopted target"}'
    return 0
  fi
  alias="$(jq -r '.alias' <<<"$target_json")"
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  tmux_target="$(jq -r '.tmux_target' <<<"$target_json")"
  controller="organ:$alias"
  output_file="$(organ_osrc_private_output)" || {
    jq -cn '{ok:false,code:"CLAIM_FAILED",message:"could not create private claim output"}'
    return 0
  }
  if (cd -- "$cwd" && env -u OSRC_EXTERNAL_SEND -u OSRC_CONTROLLER_ID -u OSRC_SESSION_CLAIM_TOKEN -u OSRC_EXTERNAL_COMPOSER_PROBE -u OSRC_EXTERNAL_RECEIPT_PROBE OSRC_EXTERNAL_SEND=1 OSRC_CONTROLLER_ID="$controller" "$(organ_osrc_bin)" session claim "$alias" "$tmux_target") >"$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f -- "$output_file"
    jq -cn '{ok:false,code:"CLAIM_FAILED",message:"upstream claim failed"}'
    return 0
  fi
  output="$(<"$output_file")"
  rm -f -- "$output_file"
  token="$(sed -nE 's/^claim token:[[:space:]]*([^[:space:]]+)$/\1/p' <<<"$output")"
  if [[ -z "$token" || "$(wc -l <<<"$token")" -ne 1 ]]; then
    jq -cn '{ok:false,code:"CLAIM_FAILED",message:"upstream claim was not confirmed"}'
    return 0
  fi
  record="$(jq -cn --arg alias "$alias" --arg controller "$controller" --arg endpoint "$tmux_target" --arg token "$token" \
    '{schema_version:"1",alias:$alias,external_id:$alias,controller_id:$controller,endpoint:$endpoint,token:$token}')"
  if ! organ_claim_write "$alias" "$record"; then
    jq -cn '{ok:false,code:"CLAIM_STORE_FAILED",message:"could not store private claim"}'
    return 0
  fi
  jq -cn '{ok:true,state:"unknown",delivery:"confirmed"}'
}

organ_osrc_ask() {
  local target_json="$1"
  local payload_file="$2"
  local alias cwd claim controller token composer_probe receipt_probe output_file rc output message

  if ! organ_osrc_adopted_target "$target_json"; then
    jq -cn '{ok:false,code:"ADOPTED_TARGET_REQUIRED",message:"action requires an adopted target"}'
    return 0
  fi
  alias="$(jq -r '.alias' <<<"$target_json")"
  if ! claim="$(organ_claim_read "$alias")"; then
    jq -cn '{ok:false,code:"CLAIM_REQUIRED",message:"an active claim is required"}'
    return 0
  fi
  composer_probe="$(organ_osrc_composer_probe)" || {
    jq -cn '{ok:false,code:"COMPOSER_PROBE_INVALID",message:"composer probe must be an executable absolute path"}'
    return 0
  }
  if ! receipt_probe="$(organ_osrc_receipt_probe)"; then
    jq -cn '{ok:false,code:"RECEIPT_PROBE_INVALID",message:"receipt probe must be an executable absolute path"}'
    return 0
  fi
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  controller="$(jq -r '.controller_id' <<<"$claim")"
  token="$(jq -r '.token' <<<"$claim")"
  if ! organ_read_text_file "$payload_file" message; then
    jq -cn '{ok:false,code:"REPLY_FAILED",message:"reply payload is not valid text"}'
    return 0
  fi
  output_file="$(organ_osrc_private_output)" || {
    jq -cn '{ok:false,code:"REPLY_FAILED",message:"could not create private reply output"}'
    return 0
  }
  if [[ -n "$receipt_probe" ]]; then
    if (cd -- "$cwd" && env -u OSRC_EXTERNAL_SEND -u OSRC_CONTROLLER_ID -u OSRC_SESSION_CLAIM_TOKEN -u OSRC_EXTERNAL_COMPOSER_PROBE -u OSRC_EXTERNAL_RECEIPT_PROBE OSRC_EXTERNAL_SEND=1 OSRC_CONTROLLER_ID="$controller" OSRC_SESSION_CLAIM_TOKEN="$token" OSRC_EXTERNAL_COMPOSER_PROBE="$composer_probe" OSRC_EXTERNAL_RECEIPT_PROBE="$receipt_probe" "$(organ_osrc_bin)" session reply "$alias" "$message") >"$output_file" 2>&1; then
      rc=0
    else
      rc=$?
    fi
  elif (cd -- "$cwd" && env -u OSRC_EXTERNAL_SEND -u OSRC_CONTROLLER_ID -u OSRC_SESSION_CLAIM_TOKEN -u OSRC_EXTERNAL_COMPOSER_PROBE -u OSRC_EXTERNAL_RECEIPT_PROBE OSRC_EXTERNAL_SEND=1 OSRC_CONTROLLER_ID="$controller" OSRC_SESSION_CLAIM_TOKEN="$token" OSRC_EXTERNAL_COMPOSER_PROBE="$composer_probe" "$(organ_osrc_bin)" session reply "$alias" "$message") >"$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  output="$(<"$output_file")"
  rm -f -- "$output_file"
  if [[ "$rc" -eq 0 && "$output" == 'composer unavailable' ]]; then
    jq -cn '{ok:true,state:"unknown",delivery:"blocked"}'
  elif [[ "$rc" -ne 0 ]]; then
    jq -cn '{ok:false,code:"REPLY_FAILED",message:"upstream reply failed"}'
  elif grep -Eq '^receipt:[[:space:]]*[^[:space:]]+' <<<"$output"; then
    jq -cn '{ok:true,state:"unknown",delivery:"confirmed"}'
  else
    jq -cn '{ok:true,state:"unknown",delivery:"unknown"}'
  fi
}

organ_osrc_release() {
  local target_json="$1"
  local alias cwd claim controller token output_file rc release_line expected_release bytes_expected

  if ! organ_osrc_adopted_target "$target_json"; then
    jq -cn '{ok:false,code:"ADOPTED_TARGET_REQUIRED",message:"action requires an adopted target"}'
    return 0
  fi
  alias="$(jq -r '.alias' <<<"$target_json")"
  if ! claim="$(organ_claim_read "$alias")"; then
    jq -cn '{ok:false,code:"CLAIM_REQUIRED",message:"an active claim is required"}'
    return 0
  fi
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  controller="$(jq -r '.controller_id' <<<"$claim")"
  token="$(jq -r '.token' <<<"$claim")"
  output_file="$(organ_osrc_private_output)" || {
    jq -cn '{ok:false,code:"RELEASE_UNCONFIRMED",message:"could not create private release output"}'
    return 0
  }
  if (cd -- "$cwd" && env -u OSRC_EXTERNAL_SEND -u OSRC_CONTROLLER_ID -u OSRC_SESSION_CLAIM_TOKEN -u OSRC_EXTERNAL_COMPOSER_PROBE -u OSRC_EXTERNAL_RECEIPT_PROBE OSRC_EXTERNAL_SEND=1 OSRC_CONTROLLER_ID="$controller" OSRC_SESSION_CLAIM_TOKEN="$token" "$(organ_osrc_bin)" session release "$alias") >"$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  expected_release="claim released for '$alias'"
  bytes_expected=$((${#expected_release} + 1))
  if [[ "$rc" -ne 0 || "$(wc -c <"$output_file")" -ne "$bytes_expected" ]] ||
    ! IFS= read -r release_line <"$output_file" || [[ "$release_line" != "$expected_release" ]]; then
    rm -f -- "$output_file"
    jq -cn '{ok:false,code:"RELEASE_UNCONFIRMED",message:"upstream release was not confirmed"}'
    return 0
  fi
  rm -f -- "$output_file"
  if ! organ_claim_delete "$alias"; then
    jq -cn '{ok:false,code:"RELEASE_UNCONFIRMED",message:"could not delete private claim"}'
    return 0
  fi
  jq -cn '{ok:true,state:"unknown",delivery:"confirmed"}'
}

organ_capture_to_file() {
  local cwd="$1"
  local max_bytes="$2"
  local output_file="$3"
  local size_file="$4"
  shift 4
  local count_dir count_fifo count_file count_pid count_rc statuses

  umask 077
  count_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-count.XXXXXX")"
  count_fifo="$count_dir/bytes"
  count_file="$count_dir/count"
  mkfifo -- "$count_fifo"
  wc -c <"$count_fifo" >"$count_file" &
  count_pid=$!
  set +e
  (cd -- "$cwd" && "$@") 2>&1 | tee "$count_fifo" | tail -c "$max_bytes" >"$output_file"
  statuses=("${PIPESTATUS[@]}")
  wait "$count_pid"
  count_rc=$?
  set -e
  if [[ "$count_rc" -ne 0 ]]; then
    rm -rf -- "$count_dir"
    return "$count_rc"
  fi
  cat -- "$count_file" >"$size_file"
  rm -rf -- "$count_dir"
  if [[ "${statuses[0]}" -ne 0 ]]; then
    return "${statuses[0]}"
  fi
  if [[ "${statuses[1]}" -ne 0 ]]; then
    return "${statuses[1]}"
  fi
  if [[ "${statuses[2]}" -ne 0 ]]; then
    return "${statuses[2]}"
  fi
  return 0
}

organ_osrc_capture() {
  local max_bytes="$1"
  shift
  local output_file size_file rc

  umask 077
  output_file="$(mktemp "${TMPDIR:-/tmp}/organoun-osrc.XXXXXX")"
  size_file="$(mktemp "${TMPDIR:-/tmp}/organoun-size.XXXXXX")"
  if organ_capture_to_file "$PWD" "$max_bytes" "$output_file" "$size_file" "$(organ_osrc_bin)" "$@"; then
    rc=0
  else
    rc=$?
  fi
  cat -- "$output_file"
  rm -f -- "$output_file"
  rm -f -- "$size_file"
  return "$rc"
}

organ_osrc_state_file() {
  local source_file="$1"
  local state

  state="$(jq -r 'if type == "object" and (.state | type == "string") then .state else "unknown" end' "$source_file" 2>/dev/null || printf unknown)"
  case "$state" in
    unknown|idle|working|waiting|done|stopped|unreachable|delivery-unknown|accepted|blocked-scope|blocked-verification)
      printf '%s\n' "$state"
      ;;
    *) printf '%s\n' unknown ;;
  esac
}

organ_osrc_structured_excerpt() {
  local source_file="$1"
  local max_bytes="$2"
  local raw_bytes="$3"
  local state truncated

  state="$(organ_osrc_state_file "$source_file")"
  if (( raw_bytes > max_bytes )); then
    truncated=true
  else
    truncated=false
  fi
  jq -cn --arg state "$state" --argjson truncated "$truncated" \
    '{excerpt:("state: " + $state),truncated:$truncated}'
}

organ_osrc_redact_text() {
  local source_file="$1"
  local redacted_file="$2"

  sed -E \
    -e 's/([Cc]laim[[:space:]]+[Tt]oken:[[:space:]]*)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/((^|[[:space:]])((proxy-)?authorization|cookie|set-cookie|(x-)?api[_-]?key|(x-)?auth[_-]?token|(x-)?access[_-]?token|(x-)?client[_-]?secret|x-credential)[[:space:]]*:[[:space:]]*).*/\1[REDACTED]/I' \
    -e 's/("?(token|api[_-]?key|access[_-]?token|secret|password|credential)"?[[:space:]]*:[[:space:]]*"?)[^",[:space:]}]+/\1[REDACTED]/gI' \
    -e 's/([A-Za-z_]*(token|key|secret|password|credential)[A-Za-z_]*[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1[REDACTED]/gI' \
    -e 's/((^|[[:space:]])(basic|bearer)[[:space:]]+)[^[:space:]]+/\1[REDACTED]/gI' \
    -e 's/([Pp]rompt:[[:space:]]*)[^[:cntrl:]]*/\1[REDACTED]/g' \
    -e 's/(sk-[A-Za-z0-9_-]{8,}|AKIA[A-Z0-9]{16})/[REDACTED]/g' \
    "$source_file" >"$redacted_file"
}

organ_osrc_text_excerpt() {
  local source_file="$1"
  local max_bytes="$2"
  local raw_bytes="$3"
  local redacted_file excerpt_file utf8_file redacted_bytes truncated

  umask 077
  redacted_file="$(mktemp "${TMPDIR:-/tmp}/organoun-redacted.XXXXXX")"
  excerpt_file="$(mktemp "${TMPDIR:-/tmp}/organoun-excerpt.XXXXXX")"
  utf8_file="$(mktemp "${TMPDIR:-/tmp}/organoun-utf8.XXXXXX")"
  organ_osrc_redact_text "$source_file" "$redacted_file"
  redacted_bytes="$(wc -c <"$redacted_file")"
  if (( redacted_bytes > max_bytes )); then
    tail -c "$max_bytes" "$redacted_file" >"$excerpt_file"
  else
    cp -- "$redacted_file" "$excerpt_file"
  fi
  iconv -f UTF-8 -t UTF-8 -c "$excerpt_file" >"$utf8_file"
  if (( raw_bytes > max_bytes || redacted_bytes > max_bytes )); then
    truncated=true
  else
    truncated=false
  fi
  jq -cn --rawfile excerpt "$utf8_file" --argjson truncated "$truncated" \
    '{excerpt:$excerpt,truncated:$truncated}'
  rm -f -- "$redacted_file" "$excerpt_file" "$utf8_file"
}

organ_osrc_adopted_capture() {
  local session_id="$1"
  local tmux_target="$2"
  local cwd="$3"
  local raw_file size_file rc raw_bytes state serialize_rc

  umask 077
  raw_file="$(mktemp "${TMPDIR:-/tmp}/organoun-capture.XXXXXX")"
  size_file="$(mktemp "${TMPDIR:-/tmp}/organoun-size.XXXXXX")"
  if [[ -n "$session_id" ]]; then
    if organ_capture_to_file "$cwd" "$ORGAN_MAX_READ_CAPTURE_BYTES" "$raw_file" "$size_file" "$(organ_osrc_bin)" fleet show "$session_id" --json; then
      rc=0
    else
      rc=$?
    fi
  else
    if organ_capture_to_file "$cwd" "$ORGAN_MAX_READ_CAPTURE_BYTES" "$raw_file" "$size_file" "$(organ_tmux_bin)" capture-pane -p -t "$tmux_target" -S -120; then
      rc=0
    else
      rc=$?
    fi
  fi

  if [[ "$rc" -ne 0 ]]; then
    rm -f -- "$raw_file" "$size_file"
    jq -cn --argjson rc "$rc" '{ok:false,code:"OUTSOURCERER_UNAVAILABLE",message:"local session observation failed",exit_code:$rc}'
    return 0
  fi

  raw_bytes="$(<"$size_file")"
  rm -f -- "$size_file"
  if (( raw_bytes > ORGAN_MAX_READ_CAPTURE_BYTES )); then
    rm -f -- "$raw_file"
    jq -cn '{ok:true,state:"unknown",excerpt:"[output omitted: exceeds private read limit]",truncated:true}'
    return 0
  fi

  state="$(organ_osrc_state_file "$raw_file")"
  if [[ -n "$session_id" ]]; then
    if organ_osrc_structured_excerpt "$raw_file" "$ORGAN_MAX_READ_BYTES" "$raw_bytes" |
      jq -cn --arg state "$state" \
        'input as $excerpt | {ok:true,state:$state,excerpt:$excerpt.excerpt,truncated:$excerpt.truncated}'; then
      serialize_rc=0
    else
      serialize_rc=$?
    fi
  else
    if organ_osrc_text_excerpt "$raw_file" "$ORGAN_MAX_READ_BYTES" "$raw_bytes" |
      jq -cn --arg state "$state" \
        'input as $excerpt | {ok:true,state:$state,excerpt:$excerpt.excerpt,truncated:$excerpt.truncated}'; then
      serialize_rc=0
    else
      serialize_rc=$?
    fi
  fi
  rm -f -- "$raw_file"
  return "$serialize_rc"
}

organ_osrc_managed_call() {
  local cwd="$1"
  local session_name="$2"
  local output_file="$3"
  shift 3

  (cd -- "$cwd" && env \
    -u OUTSOURCERER_TMUX \
    -u OSRC_EXTERNAL_SEND \
    -u OSRC_CONTROLLER_ID \
    -u OSRC_SESSION_CLAIM_TOKEN \
    -u OSRC_EXTERNAL_COMPOSER_PROBE \
    -u OSRC_EXTERNAL_RECEIPT_PROBE \
    -u OSRC_PROVIDER \
    -u OSRC_MODEL \
    -u OSRC_DEFAULT_PROVIDER \
    -u OSRC_DEFAULT_MODEL \
    -u OUTSOURCERER_PROVIDER \
    -u OUTSOURCERER_MODEL \
    -u OUTSOURCERER_DEFAULT_PROVIDER \
    -u OUTSOURCERER_DEFAULT_MODEL \
    -u CLAUDE_MODEL \
    -u ANTHROPIC_MODEL \
    OUTSOURCERER_TMUX="$session_name" "$(organ_osrc_bin)" "$@") >"$output_file" 2>&1
}

organ_osrc_managed_error() {
  jq -cn --arg code "$1" --arg message "$2" '{ok:false,code:$code,message:$message}'
}

organ_osrc_managed_observe() {
  local cwd="$1"
  local session_name="$2"
  local output_file rc state

  output_file="$(organ_osrc_private_output)" || {
    organ_osrc_managed_error OUTSOURCERER_UNAVAILABLE 'could not create private observation output'
    return 0
  }
  if organ_osrc_managed_call "$cwd" "$session_name" "$output_file" session read --state; then
    rc=0
  else
    rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f -- "$output_file"
    organ_osrc_managed_error OUTSOURCERER_UNAVAILABLE 'managed session observation failed'
    return 0
  fi
  state="$(jq -r 'if type == "object" and (.state | type == "string") then .state else "unknown" end' "$output_file" 2>/dev/null || printf unknown)"
  rm -f -- "$output_file"
  case "$state" in
    unknown|idle|working|waiting|done|stopped|unreachable|delivery-unknown)
      jq -cn --arg state "$state" '{ok:true,state:$state}'
      ;;
    *)
      jq -cn '{ok:true,state:"unknown"}'
      ;;
  esac
}

organ_osrc_managed_wait_ready() {
  local cwd="$1"
  local session_name="$2"
  local interval="${ORGAN_SESSION_POLL_INTERVAL:-1}"
  local attempt observation state

  [[ "$interval" =~ ^([0-9]+)(\.[0-9]+)?$ ]] || interval=1
  for ((attempt = 1; attempt <= 20; attempt += 1)); do
    observation="$(organ_osrc_managed_observe "$cwd" "$session_name")"
    if [[ "$(jq -r '.ok' <<<"$observation")" != true ]]; then
      printf '%s\n' "$observation"
      return 65
    fi
    state="$(jq -r '.state' <<<"$observation")"
    if [[ "$state" == idle ]]; then
      printf '%s\n' "$observation"
      return 0
    fi
    if (( attempt < 20 )); then
      sleep "$interval"
    fi
  done
  return 64
}

organ_osrc_managed_start() {
  local target_json="$1"
  local alias host cwd session_name model output_file rc output live record
  local -a start_args

  alias="$(jq -r '.alias' <<<"$target_json")"
  host="$(jq -r '.host' <<<"$target_json")"
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  session_name="$(jq -r '.session_name' <<<"$target_json")"
  model="$(jq -r '.model // ""' <<<"$target_json")"
  start_args=(--provider cc)
  if [[ -n "$model" ]]; then
    start_args+=(-m "$model")
  fi
  start_args+=(session start)

  output_file="$(organ_osrc_private_output)" || return 64
  if organ_osrc_managed_call "$cwd" "$session_name" "$output_file" "${start_args[@]}"; then
    rc=0
  else
    rc=$?
  fi
  output="$(<"$output_file")"
  rm -f -- "$output_file"
  if grep -Fqx -- "Session already exists: $session_name" <<<"$output"; then
    return 65
  fi
  [[ "$rc" -eq 0 ]] || return 64
  grep -Fqx -- "Session started: $session_name" <<<"$output" || return 64
  live="$(organ_session_live_identity "$session_name")" || return 65
  jq -e --arg session_name "$session_name" --arg cwd "$cwd" \
    '.session_name == $session_name and .cwd == $cwd' >/dev/null <<<"$live" || return 65
  record="$(jq -cn --arg alias "$alias" --arg host "$host" --argjson live "$live" \
    '{schema_version:"1",alias:$alias,host:$host,session_name:$live.session_name,cwd:$live.cwd,pane_id:$live.pane_id,pane_pid:$live.pane_pid,pid_start:$live.pid_start}')"
  organ_session_write "$alias" "$record" || return 66
  printf '%s\n' "$record"
}

organ_osrc_managed_dispatch() {
  local target_json="$1"
  local payload_file="$2"
  local options_json="$3"
  local alias host cwd session_name message readiness wait_rc job_id output_file rc output delivery patch dispatch_mode guard_json

  alias="$(jq -r '.alias' <<<"$target_json")"
  host="$(jq -r '.host' <<<"$target_json")"
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  session_name="$(jq -r '.session_name' <<<"$target_json")"
  if ! organ_read_text_file "$payload_file" message; then
    organ_osrc_managed_error DISPATCH_INVALID_TEXT 'dispatch payload is not valid text'
    return 0
  fi

  if readiness="$(organ_osrc_managed_wait_ready "$cwd" "$session_name")"; then
    :
  else
    wait_rc=$?
    if [[ "$wait_rc" -eq 65 ]]; then
      printf '%s\n' "$readiness"
    else
      organ_osrc_managed_error SESSION_NOT_READY 'managed session did not become ready within 20 observations'
    fi
    return 0
  fi
  if ! organ_session_assert_owned "$alias" "$target_json" >/dev/null; then
    organ_osrc_managed_error MANAGED_SESSION_COLLISION 'managed session ownership changed during readiness observation'
    return 0
  fi
  dispatch_mode="$(jq -r '.mode // "read"' <<<"$options_json")"
  if [[ "$dispatch_mode" == edit ]]; then
    guard_json="$(jq -c '.guard' <<<"$options_json")"
    if ! organ_guard_revalidate "$guard_json"; then
      organ_osrc_managed_error EDIT_WORKTREE_STALE 'edit worktree changed after preflight and before send'
      return 0
    fi
    if ! job_id="$(organ_job_create_edit "$alias" "$host" "$session_name" "$guard_json")"; then
      organ_osrc_managed_error JOB_STORE_FAILED 'could not allocate and create a private edit job receipt'
      return 0
    fi
  elif ! job_id="$(organ_job_create_read "$alias" "$host" "$session_name")"; then
    organ_osrc_managed_error JOB_STORE_FAILED 'could not allocate and create a private job receipt'
    return 0
  fi
  output_file="$(organ_osrc_private_output)" || {
    organ_osrc_managed_error OUTSOURCERER_UNAVAILABLE 'could not create private send output'
    return 0
  }
  if ! organ_session_assert_owned "$alias" "$target_json" >/dev/null; then
    rm -f -- "$output_file"
    organ_osrc_managed_error MANAGED_SESSION_COLLISION 'managed session ownership changed before send'
    return 0
  fi
  if organ_osrc_managed_call "$cwd" "$session_name" "$output_file" session send "$message"; then
    rc=0
  else
    rc=$?
  fi
  output="$(<"$output_file")"
  rm -f -- "$output_file"
  if [[ "$rc" -eq 0 ]] && grep -Eq '^receipt:[[:space:]]*[^[:space:]]+$' <<<"$output"; then
    delivery=confirmed
  else
    delivery=unknown
  fi
  if [[ "$dispatch_mode" == edit ]]; then
    patch="$(jq -cn --arg delivery "$delivery" '{delivery:$delivery,dispatch_complete:true}')"
  else
    patch="$(jq -cn --arg delivery "$delivery" '{delivery:$delivery}')"
  fi
  if ! organ_job_update "$job_id" "$patch"; then
    organ_osrc_managed_error JOB_STORE_FAILED 'could not persist managed delivery state'
    return 0
  fi
  jq -cn --arg state working --arg delivery "$delivery" --arg job_id "$job_id" \
    '{ok:true,state:$state,delivery:$delivery,job_id:$job_id}'
}

organ_osrc_managed_locked() {
  local action="$1"
  local target_json="$2"
  local payload_file="$3"
  local options_json="$4"
  local alias cwd session_name owned start_rc observation output_file rc output exists_rc

  alias="$(jq -r '.alias' <<<"$target_json")"
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  session_name="$(jq -r '.session_name' <<<"$target_json")"
  [[ -d "$cwd" ]] || {
    organ_osrc_managed_error CWD_INVALID 'managed target cwd is not an accessible directory'
    return 0
  }

  if organ_session_receipt_present "$alias"; then
    if ! owned="$(organ_session_assert_owned "$alias" "$target_json")"; then
      organ_osrc_managed_error MANAGED_SESSION_COLLISION 'managed session ownership is missing, invalid, or stale'
      return 0
    fi
  else
    if organ_session_exists "$session_name"; then
      organ_osrc_managed_error MANAGED_SESSION_COLLISION 'tmux session name exists without valid Organoun ownership'
      return 0
    else
      exists_rc=$?
    fi
    if [[ "$exists_rc" -ne 1 ]]; then
      organ_osrc_managed_error TMUX_UNAVAILABLE 'exact managed tmux session absence could not be established'
      return 0
    fi
    owned=''
  fi

  case "$action" in
    dispatch)
      if [[ -z "$owned" ]]; then
        if owned="$(organ_osrc_managed_start "$target_json")"; then
          :
        else
          start_rc=$?
          case "$start_rc" in
            65) organ_osrc_managed_error MANAGED_SESSION_COLLISION 'upstream reported a managed session name collision' ;;
            66) organ_osrc_managed_error SESSION_STORE_FAILED 'managed session started but ownership could not be recorded' ;;
            *) organ_osrc_managed_error SESSION_START_FAILED 'managed session launch was not confirmed' ;;
          esac
          return 0
        fi
      fi
      organ_osrc_managed_dispatch "$target_json" "$payload_file" "$options_json"
      ;;
    status|read)
      if [[ -z "$owned" ]]; then
        if [[ "$action" == status ]]; then
          jq -cn '{ok:true,state:"stopped"}'
        else
          organ_osrc_managed_error MANAGED_READ_UNAVAILABLE 'managed session read requires a valid ownership receipt'
        fi
        return 0
      fi
      observation="$(organ_osrc_managed_observe "$cwd" "$session_name")"
      if [[ "$(jq -r '.ok' <<<"$observation")" != true ]]; then
        printf '%s\n' "$observation"
      elif [[ "$action" == status ]]; then
        printf '%s\n' "$observation"
      else
        jq -cn --arg state "$(jq -r '.state' <<<"$observation")" \
          '{ok:true,state:$state,excerpt:("state: " + $state),truncated:false}'
      fi
      ;;
    stop)
      if [[ -z "$owned" ]]; then
        organ_osrc_managed_error MANAGED_SESSION_NOT_OWNED 'managed session has no valid ownership receipt'
        return 0
      fi
      output_file="$(organ_osrc_private_output)" || {
        organ_osrc_managed_error STOP_UNCONFIRMED 'could not create private stop output'
        return 0
      }
      if organ_osrc_managed_call "$cwd" "$session_name" "$output_file" session stop; then
        rc=0
      else
        rc=$?
      fi
      output="$(<"$output_file")"
      rm -f -- "$output_file"
      if [[ "$rc" -ne 0 || "$output" != "Session stopped: $session_name" ]]; then
        organ_osrc_managed_error STOP_UNCONFIRMED 'managed session stop was not confirmed'
        return 0
      fi
      if organ_session_exists "$session_name"; then
        organ_osrc_managed_error STOP_UNCONFIRMED 'managed tmux session remains live after stop acknowledgement'
        return 0
      else
        exists_rc=$?
      fi
      if [[ "$exists_rc" -ne 1 ]]; then
        organ_osrc_managed_error STOP_UNCONFIRMED 'managed tmux absence could not be independently confirmed'
        return 0
      fi
      if ! organ_session_delete "$alias"; then
        organ_osrc_managed_error STOP_UNCONFIRMED 'managed session stopped but ownership receipt could not be deleted'
        return 0
      fi
      jq -cn '{ok:true,state:"stopped",delivery:"confirmed"}'
      ;;
    *)
      organ_osrc_managed_error ACTION_UNAVAILABLE 'action is not available yet'
      ;;
  esac
}

organ_osrc_managed() {
  local action="$1"
  local target_json="$2"
  local payload_file="$3"
  local options_json="$4"
  local alias adapter

  alias="$(jq -r '.alias' <<<"$target_json")"
  if ! organ_state_init_subdir sessions || ! organ_state_init_subdir jobs; then
    organ_osrc_managed_error SESSION_STORE_FAILED 'private managed state directories are unsafe or unavailable'
    return 0
  fi
  if ! organ_session_lock "$alias"; then
    organ_osrc_managed_error SESSION_STORE_FAILED 'could not establish the private per-target lifecycle lock'
    return 0
  fi
  adapter="$(organ_osrc_managed_locked "$action" "$target_json" "$payload_file" "$options_json")"
  organ_session_unlock
  printf '%s\n' "$adapter"
}

organ_osrc() {
  local action="$1"
  local target_json="$2"
  local _payload_file="$3"
  local options_json="${4:-}"
  local mode provider session_id tmux_target cwd adapter

  [[ -n "$options_json" ]] || options_json='{}'

  mode="$(jq -r '.mode' <<<"$target_json")"
  case "$action" in
    claim)
      organ_osrc_claim "$target_json"
      return
      ;;
    ask)
      organ_osrc_ask "$target_json" "$_payload_file"
      return
      ;;
    release)
      organ_osrc_release "$target_json"
      return
      ;;
  esac
  if [[ "$mode" == managed ]]; then
    provider="$(jq -r '.provider // ""' <<<"$target_json")"
    if [[ "$provider" != cc ]]; then
      jq -cn '{ok:false,code:"PROVIDER_UNAVAILABLE",message:"managed Claude dispatch requires explicit provider cc"}'
      return 0
    fi
    organ_osrc_managed "$action" "$target_json" "$_payload_file" "$options_json"
    return 0
  fi

  if [[ "$action" == stop ]]; then
    jq -cn '{ok:false,code:"ADOPTED_SESSION_CANNOT_STOP",message:"adopted sessions cannot be stopped by Organoun"}'
    return 0
  fi

  session_id="$(jq -r '.claude_session_id // ""' <<<"$target_json")"
  tmux_target="$(jq -r '.tmux_target' <<<"$target_json")"
  cwd="$(jq -r '.cwd' <<<"$target_json")"
  adapter="$(organ_osrc_adopted_capture "$session_id" "$tmux_target" "$cwd")"
  if [[ "$(jq -r '.ok' <<<"$adapter")" != true ]]; then
    printf '%s\n' "$adapter"
    return 0
  fi

  case "$action" in
    status)
      jq -cn --arg state "$(jq -r '.state' <<<"$adapter")" '{ok:true,state:$state}'
      ;;
    read)
      printf '%s\n' "$adapter"
      ;;
    *)
      jq -cn '{ok:false,code:"ACTION_UNAVAILABLE",message:"action is not available yet"}'
      ;;
  esac
}
