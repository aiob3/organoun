#!/usr/bin/env bash
set -euo pipefail

visible_refuse() {
  printf '[VISIBLE_RUNNER_REFUSED] %s\n' "$1" >&2
  exit 64
}

[[ "${1:-}" == -- && "$#" -ge 2 ]] || visible_refuse 'usage: run-visible.sh -- command [args...]'
shift

tmux_bin="${ORGAN_VISIBLE_TMUX:-tmux}"
if [[ "$tmux_bin" == */* ]]; then
  [[ -x "$tmux_bin" && ! -d "$tmux_bin" ]] || visible_refuse 'tmux verifier is unavailable'
else
  command -v "$tmux_bin" >/dev/null 2>&1 || visible_refuse 'tmux verifier is unavailable'
fi
[[ -n "${TMUX:-}" && "${TMUX_PANE:-}" =~ ^%[0-9]+$ ]] || visible_refuse 'command is not running inside a tmux pane'

expected_session=''
expected_window=''
expected_pane="$TMUX_PANE"
expected_pid=''

visibility_snapshot() {
  local display clients panes client_line pane_line
  local session_id session_name window_id window_index pane_id pane_pid pane_cwd zoomed layout extra
  local client_session client_window client_tty client_control client_readonly client_extra attached=false
  local live_pane live_pid live_dead live_command live_cwd live_extra

  display="$("$tmux_bin" display-message -p -t "$expected_pane" \
    $'#{session_id}\t#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_pid}\t#{pane_current_path}\t#{window_zoomed_flag}\t#{window_layout}' 2>/dev/null)" || return 1
  [[ "$display" != *$'\n'* ]] || return 1
  IFS=$'\t' read -r session_id session_name window_id window_index pane_id pane_pid pane_cwd zoomed layout extra <<<"$display"
  [[ -z "$extra" && "$session_id" =~ ^\$[0-9]+$ && "$session_name" =~ ^[A-Za-z0-9._-]+$ ]] || return 1
  [[ "$window_id" =~ ^@[0-9]+$ && "$window_index" =~ ^[0-9]+$ && "$pane_id" == "$expected_pane" ]] || return 1
  [[ "$pane_pid" =~ ^[0-9]+$ && "$pane_pid" -gt 0 && "$pane_cwd" == /* && ! "$pane_cwd" =~ [[:cntrl:]] ]] || return 1
  [[ "$zoomed" == 0 && -n "$layout" ]] || return 1
  if [[ -n "$expected_session" ]]; then
    [[ "$session_id" == "$expected_session" && "$window_id" == "$expected_window" && "$pane_pid" == "$expected_pid" ]] || return 1
  else
    expected_session="$session_id"
    expected_window="$window_id"
    expected_pid="$pane_pid"
  fi

  clients="$("$tmux_bin" list-clients -F \
    $'#{session_id}\t#{window_id}\t#{client_tty}\t#{client_control_mode}\t#{client_readonly}' 2>/dev/null)" || return 1
  while IFS= read -r client_line; do
    IFS=$'\t' read -r client_session client_window client_tty client_control client_readonly client_extra <<<"$client_line"
    if [[ -z "$client_extra" && "$client_session" == "$expected_session" && "$client_window" == "$expected_window" &&
      "$client_tty" == /dev/* && "$client_control" == 0 && "$client_readonly" == 0 ]]; then
      attached=true
      break
    fi
  done <<<"$clients"
  [[ "$attached" == true ]] || return 1

  panes="$("$tmux_bin" list-panes -t "$expected_window" -F \
    $'#{pane_id}\t#{pane_pid}\t#{pane_dead}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null)" || return 1
  pane_line="$(LC_ALL=C awk -F '\t' -v pane="$expected_pane" '$1 == pane {print}' <<<"$panes")"
  [[ -n "$pane_line" && "$pane_line" != *$'\n'* ]] || return 1
  IFS=$'\t' read -r live_pane live_pid live_dead live_command live_cwd live_extra <<<"$pane_line"
  [[ -z "$live_extra" && "$live_pane" == "$expected_pane" && "$live_pid" == "$expected_pid" && "$live_dead" == 0 ]] || return 1
  [[ -n "$live_command" && "$live_cwd" == /* && ! "$live_cwd" =~ [[:cntrl:]] ]] || return 1
}

visibility_snapshot || visible_refuse 'no eligible operator client is viewing this exact pane window'

export ORGAN_OPERATOR_VISIBLE=1
export ORGAN_OPERATOR_PANE="$expected_pane"
export ORGAN_OPERATOR_WINDOW="$expected_window"

child_pid=''
terminate_child_group() {
  local attempt
  [[ "$child_pid" =~ ^[0-9]+$ ]] || return 0
  kill -TERM -- "-$child_pid" 2>/dev/null || true
  for ((attempt = 0; attempt < 20; attempt += 1)); do
    kill -0 "$child_pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL -- "-$child_pid" 2>/dev/null || true
}

# shellcheck disable=SC2329 # Invoked by the HUP/INT/TERM traps below.
signal_exit() {
  local signal_rc="$1"
  terminate_child_group
  wait "$child_pid" 2>/dev/null || true
  exit "$signal_rc"
}
trap 'signal_exit 129' HUP
trap 'signal_exit 130' INT
trap 'signal_exit 143' TERM

printf '[VISIBLE_RUNNER_START] pane=%s window=%s\n' "$expected_pane" "$expected_window"
setsid --wait -- "$@" &
child_pid=$!

while kill -0 "$child_pid" 2>/dev/null; do
  if ! visibility_snapshot; then
    printf '[VISIBLE_RUNNER_LOST] pane=%s\n' "$expected_pane" >&2
    terminate_child_group
    wait "$child_pid" 2>/dev/null || true
    trap - HUP INT TERM
    exit 66
  fi
  sleep 0.1
done

set +e
wait "$child_pid"
command_rc=$?
set -e
trap - HUP INT TERM
printf '[VISIBLE_RUNNER_END] pane=%s rc=%s\n' "$expected_pane" "$command_rc"
exit "$command_rc"
