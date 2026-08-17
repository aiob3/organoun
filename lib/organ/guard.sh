#!/usr/bin/env bash

ORGAN_MAX_VERIFY_OUTPUT_BYTES=65536

organ_guard_relative_path_valid() {
  local path="$1"
  local rest component

  [[ -n "$path" && "$path" != /* && "$path" != . && "$path" != */ ]] || return 64
  rest="$path"
  while :; do
    if [[ "$rest" == */* ]]; then
      component="${rest%%/*}"
      rest="${rest#*/}"
    else
      component="$rest"
      rest=''
    fi
    [[ -n "$component" && "$component" != . && "$component" != .. && "$component" != .git ]] || return 64
    [[ -n "$rest" ]] || break
  done
}

organ_guard_path_in_scope() {
  local path="$1"
  shift
  local allowed

  for allowed in "$@"; do
    if [[ "$path" == "$allowed" || "$path" == "$allowed/"* ]]; then
      return 0
    fi
  done
  return 1
}

organ_guard_index_flags_clean() {
  local worktree="$1"
  local flags_file entry tag hidden=false

  umask 077
  flags_file="$(mktemp "${TMPDIR:-/tmp}/organoun-index-flags.XXXXXX")" || return 64
  if ! git -C "$worktree" ls-files -v -z -- >"$flags_file" 2>/dev/null; then
    rm -f -- "$flags_file"
    return 64
  fi
  if ! git -C "$worktree" submodule foreach --quiet --recursive \
    'git ls-files -v -z --' >>"$flags_file" 2>/dev/null; then
    rm -f -- "$flags_file"
    return 64
  fi
  while IFS= read -r -d '' entry; do
    tag="${entry:0:1}"
    if [[ "$tag" == S || "$tag" == [a-z] ]]; then
      hidden=true
      break
    fi
  done <"$flags_file"
  rm -f -- "$flags_file"
  [[ "$hidden" == false ]]
}

organ_guard_worktree_clean() {
  local worktree="$1"
  local status_file flags_rc

  umask 077
  status_file="$(mktemp "${TMPDIR:-/tmp}/organoun-git-status.XXXXXX")" || return 64
  if ! git -C "$worktree" status --porcelain=v1 -z --untracked-files=all \
    --ignore-submodules=none >"$status_file" 2>/dev/null; then
    rm -f -- "$status_file"
    return 64
  fi
  if [[ -s "$status_file" ]]; then
    rm -f -- "$status_file"
    return 1
  fi
  rm -f -- "$status_file"
  if organ_guard_index_flags_clean "$worktree"; then
    return 0
  else
    flags_rc=$?
  fi
  [[ "$flags_rc" -eq 1 ]] && return 1
  return 64
}

organ_guard_paths_utf8_valid() {
  local paths_file="$1"
  local path

  while IFS= read -r -d '' path; do
    if ! printf '%s' "$path" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
      return 1
    fi
  done <"$paths_file"
}

organ_guard_prepare() {
  local requested_worktree="$1"
  local allow_json="$2"
  local verify_command="$3"
  local worktree top_level base_sha clean_rc allowed existing_allowed resolved_allowed
  local -a allowed_paths seen_allowed=()

  [[ "$requested_worktree" == /* && ! "$requested_worktree" =~ [[:cntrl:]] ]] || return 65
  [[ -d "$requested_worktree" ]] || return 65
  worktree="$(realpath -e -- "$requested_worktree" 2>/dev/null)" || return 65
  [[ "$worktree" == "$requested_worktree" ]] || return 65
  [[ "$(git -C "$worktree" rev-parse --is-inside-work-tree 2>/dev/null)" == true ]] || return 65
  top_level="$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)" || return 65
  [[ "$top_level" == "$worktree" ]] || return 65
  [[ -n "$verify_command" ]] || return 68
  jq -e 'type == "array" and length > 0 and all(.[]; type == "string")' >/dev/null <<<"$allow_json" || return 67
  mapfile -d '' -t allowed_paths < <(jq --raw-output0 '.[]' <<<"$allow_json")
  [[ "${#allowed_paths[@]}" -gt 0 ]] || return 67
  for allowed in "${allowed_paths[@]}"; do
    organ_guard_relative_path_valid "$allowed" || return 67
    for existing_allowed in "${seen_allowed[@]}"; do
      [[ "$allowed" != "$existing_allowed" ]] || return 67
    done
    seen_allowed+=("$allowed")
    resolved_allowed="$(realpath -m -- "$worktree/$allowed")" || return 67
    [[ "$resolved_allowed" == "$worktree/"* ]] || return 67
  done
  allow_json="$(jq -c 'sort' <<<"$allow_json")" || return 67

  if organ_guard_worktree_clean "$worktree"; then
    :
  else
    clean_rc=$?
    [[ "$clean_rc" -eq 1 ]] && return 66
    return 65
  fi
  base_sha="$(git -C "$worktree" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || return 65
  [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || return 65

  jq -cn --arg worktree "$worktree" --arg base_sha "$base_sha" \
    --argjson allow "$allow_json" --arg verify_command "$verify_command" \
    '{worktree:$worktree,base_sha:$base_sha,allow:$allow,verify_command:$verify_command}'
}

organ_guard_revalidate() {
  local guard_json="$1"
  local worktree base_sha canonical_root current_sha clean_rc

  jq -e '
    type == "object" and (keys_unsorted | sort) == ["allow","base_sha","verify_command","worktree"] and
    (.worktree | type == "string" and startswith("/")) and
    (.base_sha | type == "string" and test("^[0-9a-f]{40}$"))
  ' >/dev/null <<<"$guard_json" || return 64
  worktree="$(jq -r '.worktree' <<<"$guard_json")"
  base_sha="$(jq -r '.base_sha' <<<"$guard_json")"
  canonical_root="$(realpath -e -- "$worktree" 2>/dev/null)" || return 64
  [[ "$canonical_root" == "$worktree" ]] || return 1
  [[ "$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)" == "$worktree" ]] || return 1
  if organ_guard_worktree_clean "$worktree"; then
    :
  else
    clean_rc=$?
    [[ "$clean_rc" -eq 1 ]] && return 1
    return 64
  fi
  current_sha="$(git -C "$worktree" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || return 64
  [[ "$current_sha" == "$base_sha" ]] || return 1
}

organ_guard_capture_verify() {
  local worktree="$1"
  local verify_command="$2"
  local output_file="$3"
  local size_file="$4"
  local count_dir count_fifo count_file count_pid count_rc
  local -a statuses

  umask 077
  count_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-verify-count.XXXXXX")" || return 64
  count_fifo="$count_dir/bytes"
  count_file="$count_dir/count"
  if ! mkfifo -- "$count_fifo"; then
    rmdir -- "$count_dir"
    return 64
  fi
  wc -c <"$count_fifo" >"$count_file" &
  count_pid=$!
  set +e
  (cd -- "$worktree" && bash -lc "$verify_command") 2>&1 |
    tee "$count_fifo" |
    tail -c "$ORGAN_MAX_VERIFY_OUTPUT_BYTES" >"$output_file"
  statuses=("${PIPESTATUS[@]}")
  wait "$count_pid"
  count_rc=$?
  set -e
  if [[ "$count_rc" -ne 0 || "${statuses[1]}" -ne 0 || "${statuses[2]}" -ne 0 ]]; then
    rm -f -- "$count_fifo" "$count_file"
    rmdir -- "$count_dir"
    return 64
  fi
  if ! cp -- "$count_file" "$size_file"; then
    rm -f -- "$count_fifo" "$count_file"
    rmdir -- "$count_dir"
    return 64
  fi
  rm -f -- "$count_fifo" "$count_file"
  rmdir -- "$count_dir"
  return "${statuses[0]}"
}

organ_guard_verification_json() {
  local status="$1"
  local accepted="$2"
  local changed_paths="$3"
  local verify_exit="$4"
  local verify_output_file="$5"
  local verify_output_bytes="$6"
  local truncated="$7"

  if [[ "$verify_exit" == null ]]; then
    jq -cn --arg status "$status" --argjson accepted "$accepted" \
      --argjson changed_paths "$changed_paths" --argjson truncated "$truncated" \
      '{status:$status,accepted:$accepted,changed_paths:$changed_paths,verify_exit:null,
        verify_output:"",verify_output_bytes:0,verify_output_truncated:$truncated}'
  else
    jq -cn --arg status "$status" --argjson accepted "$accepted" \
      --argjson changed_paths "$changed_paths" --argjson verify_exit "$verify_exit" \
      --rawfile verify_output "$verify_output_file" --argjson verify_output_bytes "$verify_output_bytes" \
      --argjson truncated "$truncated" \
      '{status:$status,accepted:$accepted,changed_paths:$changed_paths,verify_exit:$verify_exit,
        verify_output:$verify_output,verify_output_bytes:$verify_output_bytes,
        verify_output_truncated:$truncated}'
  fi
}

organ_guard_verify() {
  local job_json="$1"
  local worktree base_sha allow_json verify_command canonical_root raw_paths sorted_paths
  local output_file size_file redacted_file utf8_file verify_exit verify_output_bytes truncated status serialize_rc
  local path scope_ok flags_rc changed_paths
  local -a allowed_paths

  jq -e '
    .mode == "edit" and (.worktree | type == "string") and
    (.base_sha | type == "string" and test("^[0-9a-f]{40}$")) and
    (.allow | type == "array" and length > 0) and (.verify_command | type == "string" and length > 0)
  ' >/dev/null <<<"$job_json" || return 64
  worktree="$(jq -r '.worktree' <<<"$job_json")"
  base_sha="$(jq -r '.base_sha' <<<"$job_json")"
  allow_json="$(jq -c '.allow' <<<"$job_json")"
  verify_command="$(jq -r '.verify_command' <<<"$job_json")"
  canonical_root="$(realpath -e -- "$worktree" 2>/dev/null)" || return 64
  [[ "$canonical_root" == "$worktree" ]] || return 64
  [[ "$(git -C "$worktree" rev-parse --show-toplevel 2>/dev/null)" == "$worktree" ]] || return 64
  git -C "$worktree" cat-file -e "$base_sha^{commit}" 2>/dev/null || return 64
  mapfile -d '' -t allowed_paths < <(jq --raw-output0 '.[]' <<<"$allow_json")
  if organ_guard_index_flags_clean "$worktree"; then
    :
  else
    flags_rc=$?
    if [[ "$flags_rc" -eq 1 ]]; then
      organ_guard_verification_json blocked-scope false '[]' null /dev/null 0 false
      return 0
    fi
    return 64
  fi

  umask 077
  raw_paths="$(mktemp "${TMPDIR:-/tmp}/organoun-changed-raw.XXXXXX")" || return 64
  sorted_paths="$(mktemp "${TMPDIR:-/tmp}/organoun-changed-sorted.XXXXXX")" || {
    rm -f -- "$raw_paths"
    return 64
  }
  if ! git -C "$worktree" --no-pager diff --no-ext-diff --no-textconv --no-renames \
     --ignore-submodules=none --name-only -z "$base_sha" -- >>"$raw_paths" 2>/dev/null ||
     ! git -C "$worktree" ls-files --others --exclude-standard -z >>"$raw_paths" 2>/dev/null ||
     ! LC_ALL=C sort -zu "$raw_paths" >"$sorted_paths"; then
    rm -f -- "$raw_paths" "$sorted_paths"
    return 64
  fi
  rm -f -- "$raw_paths"

  if ! organ_guard_paths_utf8_valid "$sorted_paths"; then
    rm -f -- "$sorted_paths"
    organ_guard_verification_json blocked-scope false '[]' null /dev/null 0 false
    return 0
  fi
  changed_paths="$(jq -Rs 'split("\u0000")[:-1]' "$sorted_paths")" || {
    rm -f -- "$sorted_paths"
    return 64
  }
  scope_ok=true
  while IFS= read -r -d '' path; do
    if ! organ_guard_path_in_scope "$path" "${allowed_paths[@]}"; then
      scope_ok=false
    fi
  done <"$sorted_paths"
  rm -f -- "$sorted_paths"
  if [[ "$scope_ok" != true ]]; then
    organ_guard_verification_json blocked-scope false "$changed_paths" null /dev/null 0 false
    return 0
  fi

  output_file="$(mktemp "${TMPDIR:-/tmp}/organoun-verify-output.XXXXXX")" || return 64
  size_file="$(mktemp "${TMPDIR:-/tmp}/organoun-verify-size.XXXXXX")" || {
    rm -f -- "$output_file"
    return 64
  }
  redacted_file="$(mktemp "${TMPDIR:-/tmp}/organoun-verify-redacted.XXXXXX")" || {
    rm -f -- "$output_file" "$size_file"
    return 64
  }
  utf8_file="$(mktemp "${TMPDIR:-/tmp}/organoun-verify-utf8.XXXXXX")" || {
    rm -f -- "$output_file" "$size_file" "$redacted_file"
    return 64
  }
  if organ_guard_capture_verify "$worktree" "$verify_command" "$output_file" "$size_file"; then
    verify_exit=0
  else
    verify_exit=$?
  fi
  if [[ "$verify_exit" -eq 64 && ! -s "$size_file" ]]; then
    rm -f -- "$output_file" "$size_file" "$redacted_file" "$utf8_file"
    return 64
  fi
  verify_output_bytes="$(<"$size_file")"
  [[ "$verify_output_bytes" =~ ^[0-9]+$ ]] || {
    rm -f -- "$output_file" "$size_file" "$redacted_file" "$utf8_file"
    return 64
  }
  if (( verify_output_bytes > ORGAN_MAX_VERIFY_OUTPUT_BYTES )); then
    truncated=true
  else
    truncated=false
  fi
  if declare -F organ_osrc_redact_text >/dev/null; then
    organ_osrc_redact_text "$output_file" "$redacted_file" || {
      rm -f -- "$output_file" "$size_file" "$redacted_file" "$utf8_file"
      return 64
    }
  else
    cp -- "$output_file" "$redacted_file" || {
      rm -f -- "$output_file" "$size_file" "$redacted_file" "$utf8_file"
      return 64
    }
  fi
  if ! tail -c "$ORGAN_MAX_VERIFY_OUTPUT_BYTES" "$redacted_file" | iconv -f UTF-8 -t UTF-8 -c >"$utf8_file"; then
    rm -f -- "$output_file" "$size_file" "$redacted_file" "$utf8_file"
    return 64
  fi
  rm -f -- "$output_file" "$size_file" "$redacted_file"
  if [[ "$verify_exit" -eq 0 ]]; then
    status=accepted
    if organ_guard_verification_json "$status" true "$changed_paths" "$verify_exit" "$utf8_file" "$verify_output_bytes" "$truncated"; then
      serialize_rc=0
    else
      serialize_rc=$?
    fi
  else
    status=blocked-verification
    if organ_guard_verification_json "$status" false "$changed_paths" "$verify_exit" "$utf8_file" "$verify_output_bytes" "$truncated"; then
      serialize_rc=0
    else
      serialize_rc=$?
    fi
  fi
  rm -f -- "$utf8_file"
  return "$serialize_rc"
}
