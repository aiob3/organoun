#!/usr/bin/env bash

organ_state_root_valid() {
  local state_home="${ORGAN_STATE_HOME:-}"
  local relative component
  local -a components

  [[ "$state_home" == /* && "$state_home" != / ]] || return 64
  [[ ! "$state_home" =~ [[:cntrl:]] ]] || return 64
  [[ "$state_home" != */ && "$state_home" != *//* ]] || return 64
  relative="${state_home#/}"
  IFS=/ read -r -a components <<<"$relative"
  (( ${#components[@]} > 0 )) || return 64
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 64
  done
}

organ_state_ancestors_safe() {
  local relative component current=/
  local -a components

  organ_state_root_valid || return 64
  relative="${ORGAN_STATE_HOME#/}"
  IFS=/ read -r -a components <<<"$relative"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 64
    if [[ "$current" == / ]]; then
      current="/$component"
    else
      current="$current/$component"
    fi
    [[ ! -L "$current" ]] || return 64
    if [[ -e "$current" ]]; then
      [[ -d "$current" ]] || return 64
    fi
  done
}

organ_state_subdir_safe() {
  local subdir="$1"

  [[ "$subdir" =~ ^[a-z]+$ ]] || return 64
  organ_state_ancestors_safe || return 64
  [[ -d "$ORGAN_STATE_HOME" && ! -L "$ORGAN_STATE_HOME" ]] || return 64
  [[ -d "$ORGAN_STATE_HOME/$subdir" && ! -L "$ORGAN_STATE_HOME/$subdir" ]] || return 64
}

organ_state_init_subdir() {
  local subdir="$1"

  [[ "$subdir" =~ ^[a-z]+$ ]] || return 64
  (
    umask 077
    organ_state_ancestors_safe || return 64
    [[ ! -L "$ORGAN_STATE_HOME" ]] || return 64
    if [[ -e "$ORGAN_STATE_HOME" ]]; then
      [[ -d "$ORGAN_STATE_HOME" ]] || return 64
    else
      mkdir -- "$ORGAN_STATE_HOME" || return 64
    fi
    [[ -d "$ORGAN_STATE_HOME" && ! -L "$ORGAN_STATE_HOME" ]] || return 64
    if [[ -e "$ORGAN_STATE_HOME/$subdir" || -L "$ORGAN_STATE_HOME/$subdir" ]]; then
      [[ -d "$ORGAN_STATE_HOME/$subdir" && ! -L "$ORGAN_STATE_HOME/$subdir" ]] || return 64
    else
      mkdir -- "$ORGAN_STATE_HOME/$subdir" || return 64
    fi
    organ_state_ancestors_safe || return 64
    organ_state_subdir_safe "$subdir" || return 64
    chmod 700 -- "$ORGAN_STATE_HOME" "$ORGAN_STATE_HOME/$subdir"
  )
}

organ_session_path() {
  local alias="$1"

  organ_alias_valid "$alias" || return 64
  printf '%s/sessions/%s.json\n' "$ORGAN_STATE_HOME" "$alias"
}

organ_session_record_valid() {
  local alias="$1"
  local record_json="$2"

  jq -e --arg alias "$alias" '
    . == {
      schema_version:"1",
      alias:$alias,
      host:.host,
      session_name:.session_name,
      cwd:.cwd,
      pane_id:.pane_id,
      pane_pid:.pane_pid,
      pid_start:.pid_start
    }
    and (.host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"))
    and (.session_name | type == "string" and length > 0 and (test("[[:cntrl:]]") | not))
    and (.cwd | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not))
    and (.pane_id | type == "string" and test("^%[0-9]+$"))
    and (.pane_pid | type == "number" and floor == . and . > 0)
    and (.pid_start | type == "string" and length > 0 and (test("[[:cntrl:]]") | not))
  ' >/dev/null <<<"$record_json"
}

organ_session_write() {
  local alias="$1"
  local record_json="$2"
  local session_path session_dir temporary

  organ_alias_valid "$alias" || return 64
  organ_session_record_valid "$alias" "$record_json" || return 64
  organ_state_init_subdir sessions || return 64
  organ_state_subdir_safe sessions || return 64
  session_path="$(organ_session_path "$alias")" || return 64
  session_dir="${session_path%/*}"
  umask 077
  temporary="$(mktemp "$session_dir/.${alias}.XXXXXX")" || return 64
  if ! printf '%s\n' "$record_json" >"$temporary"; then
    rm -f -- "$temporary"
    return 64
  fi
  chmod 600 -- "$temporary" || {
    rm -f -- "$temporary"
    return 64
  }
  organ_state_subdir_safe sessions || {
    rm -f -- "$temporary"
    return 64
  }
  if ! mv -f -- "$temporary" "$session_path"; then
    rm -f -- "$temporary"
    return 64
  fi
}

organ_session_read() {
  local alias="$1"
  local session_path record_json

  session_path="$(organ_session_path "$alias")" || return 64
  organ_state_subdir_safe sessions || return 64
  [[ -f "$session_path" && ! -L "$session_path" ]] || return 64
  [[ "$(stat -c '%a' -- "$session_path")" == 600 ]] || return 64
  record_json="$(jq -ce . "$session_path")" || return 64
  organ_session_record_valid "$alias" "$record_json" || return 64
  printf '%s\n' "$record_json"
}

organ_session_delete() {
  local alias="$1"
  local session_path

  session_path="$(organ_session_path "$alias")" || return 64
  organ_state_subdir_safe sessions || return 64
  [[ ! -L "$session_path" ]] || return 64
  rm -f -- "$session_path"
}

organ_session_receipt_present() {
  local alias="$1"
  local session_path

  session_path="$(organ_session_path "$alias")" || return 64
  [[ -e "$session_path" || -L "$session_path" ]]
}

organ_session_process_start() {
  local pane_pid="$1"
  local proc_root="${ORGAN_PROC_ROOT:-/proc}"
  local stat_path stat_line remainder marker
  local -a fields

  [[ "$pane_pid" =~ ^[0-9]+$ && "$pane_pid" -gt 0 ]] || return 64
  [[ "$proc_root" == /* && ! "$proc_root" =~ [[:cntrl:]] ]] || return 64
  stat_path="$proc_root/$pane_pid/stat"
  [[ -f "$stat_path" && ! -L "$stat_path" ]] || return 64
  stat_line="$(<"$stat_path")" || return 64
  [[ "$stat_line" == *') '* ]] || return 64
  remainder="${stat_line##*) }"
  read -r -a fields <<<"$remainder"
  (( ${#fields[@]} >= 20 )) || return 64
  marker="${fields[19]}"
  [[ "$marker" =~ ^[0-9]+$ ]] || return 64
  printf '%s\n' "$marker"
}

organ_session_live_identity() {
  local session_name="$1"
  local output live_session pane_id pane_pid pane_cwd pid_start extra

  output="$("$(organ_tmux_bin)" display-message -p -t "=$session_name" $'#{session_name}\t#{pane_id}\t#{pane_pid}\t#{pane_current_path}')" || return 64
  IFS=$'\t' read -r live_session pane_id pane_pid pane_cwd extra <<<"$output"
  [[ -z "$extra" && "$live_session" == "$session_name" ]] || return 64
  [[ "$pane_id" =~ ^%[0-9]+$ ]] || return 64
  [[ "$pane_pid" =~ ^[0-9]+$ && "$pane_pid" -gt 0 ]] || return 64
  [[ "$pane_cwd" == /* && ! "$pane_cwd" =~ [[:cntrl:]] ]] || return 64
  pid_start="$(organ_session_process_start "$pane_pid")" || return 64
  jq -cn --arg session_name "$live_session" --arg cwd "$pane_cwd" \
    --arg pane_id "$pane_id" --argjson pane_pid "$pane_pid" --arg pid_start "$pid_start" \
    '{session_name:$session_name,cwd:$cwd,pane_id:$pane_id,pane_pid:$pane_pid,pid_start:$pid_start}'
}

organ_tmux_raw_file_valid() {
  local input_file="$1"
  local grep_rc

  [[ -f "$input_file" && ! -L "$input_file" && -r "$input_file" ]] || return 64
  if LC_ALL=C grep -a -q '[^ -~]' -- "$input_file" 2>/dev/null; then
    return 64
  else
    grep_rc=$?
  fi
  [[ "$grep_rc" -eq 1 ]] || return 64
}

organ_tmux_empty_file_valid() {
  local input_file="$1"

  organ_tmux_raw_file_valid "$input_file" || return 64
  [[ ! -s "$input_file" ]]
}

organ_tmux_printable_lines_file_valid() {
  local input_file="$1"

  organ_tmux_raw_file_valid "$input_file" || return 64
  LC_ALL=C awk '
    length($0) == 0 { invalid = 1 }
    END { exit invalid }
  ' "$input_file"
}

organ_tmux_single_printable_line() {
  local input_file="$1"
  local value

  organ_tmux_raw_file_valid "$input_file" || return 64
  LC_ALL=C awk '
    NR != 1 || length($0) == 0 { invalid = 1 }
    END { exit (NR == 1 && !invalid) ? 0 : 1 }
  ' "$input_file" || return 64
  value="$(<"$input_file")"
  printf '%s\n' "$value"
}

organ_tmux_capture_bounded() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2
  local capture_dir stderr_dir stdout_stage stderr_stage stdout_fifo stderr_fifo timeout_marker
  local stdout_reader_pid stderr_reader_pid command_pid watchdog_pid
  local stdout_reader_rc stderr_reader_rc command_rc stdout_bytes stderr_bytes
  local private_path
  local max_bytes=65536
  local timeout_seconds=1
  local kill_grace_seconds=0.1

  ORGAN_TMUX_CAPTURE_COMMAND_RC=64
  (( $# > 0 )) || return 64
  capture_dir="${stdout_file%/*}"
  stderr_dir="${stderr_file%/*}"
  [[ "$capture_dir" == "$stderr_dir" && -d "$capture_dir" && ! -L "$capture_dir" ]] || return 64
  [[ ! -e "$stdout_file" && ! -L "$stdout_file" ]] || return 64
  [[ ! -e "$stderr_file" && ! -L "$stderr_file" ]] || return 64

  stdout_stage="$capture_dir/.capture-stdout-stage"
  stderr_stage="$capture_dir/.capture-stderr-stage"
  stdout_fifo="$capture_dir/.capture-stdout-fifo"
  stderr_fifo="$capture_dir/.capture-stderr-fifo"
  timeout_marker="$capture_dir/.capture-timeout"
  for private_path in \
    "$stdout_stage" "$stderr_stage" "$stdout_fifo" "$stderr_fifo" "$timeout_marker"; do
    [[ ! -e "$private_path" && ! -L "$private_path" ]] || return 64
  done

  umask 077
  if ! : >"$stdout_stage" || ! : >"$stderr_stage" ||
    ! mkfifo -- "$stdout_fifo" "$stderr_fifo"; then
    rm -f -- "$stdout_stage" "$stderr_stage" "$stdout_fifo" "$stderr_fifo" "$timeout_marker"
    return 64
  fi

  head -c "$((max_bytes + 1))" <"$stdout_fifo" >"$stdout_stage" &
  stdout_reader_pid=$!
  head -c "$((max_bytes + 1))" <"$stderr_fifo" >"$stderr_stage" &
  stderr_reader_pid=$!
  setsid -- "$@" </dev/null >"$stdout_fifo" 2>"$stderr_fifo" &
  command_pid=$!
  (
    sleep "$timeout_seconds"
    : >"$timeout_marker"
    kill -TERM -- "-$command_pid" "$stdout_reader_pid" "$stderr_reader_pid" 2>/dev/null || true
    sleep "$kill_grace_seconds"
    kill -KILL -- "-$command_pid" "$stdout_reader_pid" "$stderr_reader_pid" 2>/dev/null || true
  ) >/dev/null 2>&1 &
  watchdog_pid=$!

  if wait "$command_pid"; then
    command_rc=0
  else
    command_rc=$?
  fi
  kill -TERM -- "-$command_pid" 2>/dev/null || true
  if wait "$stdout_reader_pid"; then
    stdout_reader_rc=0
  else
    stdout_reader_rc=$?
  fi
  if wait "$stderr_reader_pid"; then
    stderr_reader_rc=0
  else
    stderr_reader_rc=$?
  fi
  kill -KILL -- "-$command_pid" 2>/dev/null || true
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  rm -f -- "$stdout_fifo" "$stderr_fifo"

  if ! chmod 400 -- "$stdout_stage" "$stderr_stage" ||
    ! mv -f -- "$stdout_stage" "$stdout_file" ||
    ! mv -f -- "$stderr_stage" "$stderr_file"; then
    rm -f -- "$stdout_stage" "$stderr_stage" "$stdout_file" "$stderr_file" "$timeout_marker"
    return 64
  fi
  if ! stdout_bytes="$(wc -c <"$stdout_file")" ||
    ! stderr_bytes="$(wc -c <"$stderr_file")"; then
    rm -f -- "$timeout_marker"
    return 64
  fi

  if [[ -e "$timeout_marker" ]] ||
    [[ "$stdout_reader_rc" -ne 0 || "$stderr_reader_rc" -ne 0 ]] ||
    (( stdout_bytes > max_bytes || stderr_bytes > max_bytes )); then
    rm -f -- "$timeout_marker"
    return 64
  fi
  rm -f -- "$timeout_marker"
  ORGAN_TMUX_CAPTURE_COMMAND_RC="$command_rc"
}

organ_session_exists() {
  local session_name="$1"
  local tmux_bin capture_dir version_stdout_file version_stderr_file stdout_file stderr_file
  local tmux_version version_rc query_rc listed_session diagnostic result=64
  local -x LC_ALL=C

  tmux_bin="$(organ_tmux_bin)" || return 64
  umask 077
  capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-tmux-query.XXXXXX")" || return 64
  version_stdout_file="$capture_dir/version-stdout"
  version_stderr_file="$capture_dir/version-stderr"
  stdout_file="$capture_dir/stdout"
  stderr_file="$capture_dir/stderr"

  if organ_tmux_capture_bounded "$version_stdout_file" "$version_stderr_file" "$tmux_bin" -V; then
    version_rc="$ORGAN_TMUX_CAPTURE_COMMAND_RC"
  else
    version_rc=64
  fi
  if (( version_rc == 0 )) &&
    organ_tmux_raw_file_valid "$version_stdout_file" &&
    organ_tmux_raw_file_valid "$version_stderr_file" &&
    organ_tmux_empty_file_valid "$version_stderr_file" &&
    tmux_version="$(organ_tmux_single_printable_line "$version_stdout_file")" &&
    [[ "$tmux_version" =~ ^tmux\ [[:graph:]]+$ ]]; then
    if organ_tmux_capture_bounded \
      "$stdout_file" "$stderr_file" "$tmux_bin" list-sessions -F '#{session_name}'; then
      query_rc="$ORGAN_TMUX_CAPTURE_COMMAND_RC"
    else
      query_rc=64
    fi
    if organ_tmux_raw_file_valid "$stdout_file" &&
      organ_tmux_raw_file_valid "$stderr_file"; then
      case "$query_rc" in
        0)
          if organ_tmux_empty_file_valid "$stderr_file" &&
            organ_tmux_printable_lines_file_valid "$stdout_file"; then
            result=1
            while IFS= read -r listed_session || [[ -n "$listed_session" ]]; do
              if [[ "$listed_session" == "$session_name" ]]; then
                result=0
              fi
            done <"$stdout_file"
          fi
          ;;
        1)
          if organ_tmux_empty_file_valid "$stdout_file" &&
            diagnostic="$(organ_tmux_single_printable_line "$stderr_file")"; then
            if [[ "$diagnostic" == 'no sessions' ||
              "$diagnostic" =~ ^no\ server\ running\ on\ [[:graph:]]([[:print:]]*[[:graph:]])?$ ]]; then
              result=1
            fi
          fi
          ;;
      esac
    fi
  fi
  rm -f -- "$version_stdout_file" "$version_stderr_file" "$stdout_file" "$stderr_file"
  rmdir -- "$capture_dir" 2>/dev/null || return 64
  return "$result"
}

organ_session_assert_owned() {
  local alias="$1"
  local target="${2:-}"
  local record live

  record="$(organ_session_read "$alias")" || return 64
  if [[ -z "$target" ]]; then
    target="$(organ_target_get "$ORGAN_CONFIG" "$alias")" || return 64
  fi
  [[ "$(jq -r '.mode' <<<"$target")" == managed ]] || return 64
  live="$(organ_session_live_identity "$(jq -r '.session_name' <<<"$record")")" || return 64
  jq -e --argjson target "$target" --argjson live "$live" '
    .alias == $target.alias
    and .host == $target.host
    and .session_name == $target.session_name
    and .cwd == $target.cwd
    and .session_name == $live.session_name
    and .cwd == $live.cwd
    and .pane_id == $live.pane_id
    and .pane_pid == $live.pane_pid
    and .pid_start == $live.pid_start
  ' >/dev/null <<<"$record" || return 64
  printf '%s\n' "$record"
}

organ_session_lock() {
  local alias="$1"
  local lock_path

  organ_alias_valid "$alias" || return 64
  organ_state_init_subdir locks || return 64
  organ_state_subdir_safe locks || return 64
  lock_path="$ORGAN_STATE_HOME/locks/session-$alias.lock"
  if [[ -e "$lock_path" || -L "$lock_path" ]]; then
    [[ -f "$lock_path" && ! -L "$lock_path" ]] || return 64
  else
    umask 077
    : >"$lock_path" || return 64
  fi
  chmod 600 -- "$lock_path" || return 64
  exec {ORGAN_SESSION_LOCK_FD}<>"$lock_path" || return 64
  flock -x "$ORGAN_SESSION_LOCK_FD" || {
    exec {ORGAN_SESSION_LOCK_FD}>&-
    return 64
  }
}

organ_session_unlock() {
  if [[ -n "${ORGAN_SESSION_LOCK_FD:-}" ]]; then
    exec {ORGAN_SESSION_LOCK_FD}>&-
  fi
}
