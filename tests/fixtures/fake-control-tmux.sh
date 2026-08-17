#!/usr/bin/env bash
set -euo pipefail

state_file="${ORGAN_FAKE_CONTROL_TMUX_STATE:?}"
log_file="${ORGAN_FAKE_CONTROL_TMUX_LOG:?}"
printf '%q\0' "$@" >>"$log_file"

case "${1:-}" in
  display-message)
    if [[ "${!#}" == $'#{pane_id}\t#{pane_pid}\t#{session_name}\t#{window_index}\t#{pane_index}' ]]; then
      target=''
      previous=''
      for argument in "$@"; do
        if [[ "$previous" == -t ]]; then
          target="$argument"
        fi
        previous="$argument"
      done
      jq -er --arg target "$target" '
        . as $state | .panes[] | select(.id == $target) |
        [.id,(.pid|tostring),$state.session_name,$state.window_index,.index] | @tsv
      ' "$state_file"
    else
      jq -er '
        [.session_id,.session_name,.window_id,.window_index,.owner_pane.id,
         (.owner_pane.pid|tostring),.owner_pane.cwd,
         (.window_zoomed_flag|tostring),.window_layout] | @tsv
      ' "$state_file"
    fi
    ;;
  list-clients)
    jq -er '.clients[] |
      [.session_id,.window_id,.tty,(.control_mode|tostring),(.readonly|tostring)] | @tsv
    ' "$state_file"
    ;;
  list-panes)
    jq -er '.panes[] |
      [.id,(.pid|tostring),(.dead|tostring),.current_command,.cwd] | @tsv
    ' "$state_file"
    ;;
  split-window)
    next_id="$(jq -r '.next_pane.id' "$state_file")"
    next_pid="$(jq -r '.next_pane.pid' "$state_file")"
    next_cwd="$(jq -r '.next_pane.cwd' "$state_file")"
    stage="${state_file}.split.$$"
    jq '.panes += [.next_pane] | .next_pane.id = "%3" | .next_pane.pid += 1 | .next_pane.index = "2"' \
      "$state_file" >"$stage"
    mv -f -- "$stage" "$state_file"
    printf '%s\t%s\t%s\n' "$next_id" "$next_pid" "$next_cwd"
    ;;
  respawn-pane)
    target=''
    start_cwd=''
    previous=''
    for argument in "$@"; do
      if [[ "$previous" == -t ]]; then
        target="$argument"
      elif [[ "$previous" == -c ]]; then
        start_cwd="$argument"
      fi
      previous="$argument"
    done
    pane_command="${!#}"
    respawn_pid="$(jq -r '.respawn_pid' "$state_file")"
    stage="${state_file}.respawn.$$"
    jq --arg target "$target" --arg start_cwd "$start_cwd" --arg pane_command "$pane_command" \
      --argjson respawn_pid "$respawn_pid" '
      .last_respawn = {target:$target,cwd:$start_cwd,command:$pane_command}
      | (.panes[] | select(.id == $target)).pid = $respawn_pid
      | (.panes[] | select(.id == $target)).cwd = $start_cwd
      | (.panes[] | select(.id == $target)).current_command =
          (if ($pane_command | startswith("exec ssh ")) then "ssh" else "claude" end)
    ' \
      "$state_file" >"$stage"
    mv -f -- "$stage" "$state_file"
    ;;
  capture-pane)
    target=''
    previous=''
    for argument in "$@"; do
      if [[ "$previous" == -t ]]; then
        target="$argument"
        break
      fi
      previous="$argument"
    done
    jq -er --arg target "$target" '
      . as $state | .panes[] |
      select(.id == $target or (($state.session_name + ":" + $state.window_index + "." + .index) == $target)) |
      .output
    ' "$state_file"
    ;;
  kill-pane)
    target=''
    previous=''
    for argument in "$@"; do
      if [[ "$previous" == -t ]]; then
        target="$argument"
        break
      fi
      previous="$argument"
    done
    stage="${state_file}.kill.$$"
    jq --arg target "$target" '.panes |= map(select(.id != $target))' "$state_file" >"$stage"
    mv -f -- "$stage" "$state_file"
    ;;
  *)
    printf 'unsupported fake control tmux command: %s\n' "${1:-}" >&2
    exit 70
    ;;
esac
