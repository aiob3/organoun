#!/usr/bin/env bash
set -euo pipefail

if [[ "${ORGAN_FAKE_TMUX_REQUIRE_C_LOCALE:-0}" == 1 && "${LC_ALL:-}" != C ]]; then
  printf 'tmux query did not receive LC_ALL=C\n' >&2
  exit 70
fi

if [[ "${1:-}" == -V ]]; then
  if [[ -n "${ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE:-}" ]]; then
    cat -- "$ORGAN_FAKE_TMUX_VERSION_OUTPUT_FILE"
  elif [[ -n "${ORGAN_FAKE_TMUX_VERSION_OUTPUT+x}" ]]; then
    printf '%s' "$ORGAN_FAKE_TMUX_VERSION_OUTPUT"
  else
    printf 'tmux 3.4-fake\n'
  fi
  if [[ -n "${ORGAN_FAKE_TMUX_VERSION_STDERR_FILE:-}" ]]; then
    cat -- "$ORGAN_FAKE_TMUX_VERSION_STDERR_FILE" >&2
  fi
  if [[ -n "${ORGAN_FAKE_TMUX_VERSION_HOLD_SECONDS:-}" ]]; then
    sleep "$ORGAN_FAKE_TMUX_VERSION_HOLD_SECONDS"
  fi
  exit "${ORGAN_FAKE_TMUX_VERSION_RC:-0}"
fi

if [[ "${1:-}" == has-session && -z "${ORGAN_FAKE_TMUX_STATE_FILE:-}" ]]; then
  exit 1
fi
if [[ "${1:-}" == list-sessions && -z "${ORGAN_FAKE_TMUX_STATE_FILE:-}" ]]; then
  printf 'no server running on /tmp/tmux-fake/default\n' >&2
  exit 1
fi

printf '%q\0' "$@" >>"$ORGAN_FAKE_TMUX_LOG"
if [[ -n "${ORGAN_FAKE_TMUX_CWD_LOG:-}" ]]; then
  printf '%s\n' "$PWD" >>"$ORGAN_FAKE_TMUX_CWD_LOG"
fi

if [[ -n "${ORGAN_FAKE_TMUX_STATE_FILE:-}" && -f "$ORGAN_FAKE_TMUX_STATE_FILE" ]]; then
  case "${1:-}" in
    has-session)
      if [[ -n "${ORGAN_FAKE_TMUX_QUERY_RC:-}" ]]; then
        printf '%s' "${ORGAN_FAKE_TMUX_QUERY_OUTPUT:-}" >&2
        exit "$ORGAN_FAKE_TMUX_QUERY_RC"
      fi
      if [[ "${ORGAN_FAKE_TMUX_NO_SERVER:-0}" == 1 ]]; then
        printf 'no server running on /tmp/tmux-fake/default\n' >&2
        exit 1
      fi
      if [[ -n "${ORGAN_FAKE_TMUX_HAS_SESSION_RC:-}" ]]; then
        exit "$ORGAN_FAKE_TMUX_HAS_SESSION_RC"
      fi
      requested="${3#=}"
      if jq -e --arg requested "$requested" '.exists == true and .session_name == $requested' "$ORGAN_FAKE_TMUX_STATE_FILE" >/dev/null; then
        exit 0
      fi
      exit 1
      ;;
    list-sessions)
      [[ "${2:-}" == -F && "${3:-}" == '#{session_name}' && "$#" -eq 3 ]] || exit 70
      if [[ -n "${ORGAN_FAKE_TMUX_QUERY_RC:-}" ]]; then
        if [[ -n "${ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE:-}" ]]; then
          cat -- "$ORGAN_FAKE_TMUX_QUERY_STDOUT_FILE"
        fi
        if [[ -n "${ORGAN_FAKE_TMUX_QUERY_STDERR_FILE:-}" ]]; then
          cat -- "$ORGAN_FAKE_TMUX_QUERY_STDERR_FILE" >&2
        else
          printf '%s' "${ORGAN_FAKE_TMUX_QUERY_OUTPUT:-}" >&2
        fi
        if [[ -n "${ORGAN_FAKE_TMUX_QUERY_LATE_STDOUT_FILE:-}" ]]; then
          (
            while [[ ! -e "${ORGAN_FAKE_TMUX_QUERY_LATE_TRIGGER_FILE:?}" ]]; do
              sleep 0.01
            done
            cat -- "$ORGAN_FAKE_TMUX_QUERY_LATE_STDOUT_FILE"
          ) &
        fi
        if [[ -n "${ORGAN_FAKE_TMUX_QUERY_HOLD_SECONDS:-}" ]]; then
          sleep "$ORGAN_FAKE_TMUX_QUERY_HOLD_SECONDS"
        fi
        exit "$ORGAN_FAKE_TMUX_QUERY_RC"
      fi
      if [[ "${ORGAN_FAKE_TMUX_NO_SERVER:-0}" == 1 ]]; then
        printf 'no server running on /tmp/tmux-fake/default\n' >&2
        exit 1
      fi
      jq -er 'select(.exists == true) | .session_name' "$ORGAN_FAKE_TMUX_STATE_FILE" 2>/dev/null || true
      exit 0
      ;;
    display-message)
      requested="${4#=}"
      jq -er --arg requested "$requested" '
        select(.exists == true and .session_name == $requested) |
        [.session_name,.pane_id,(.pane_pid|tostring),.cwd] | @tsv
      ' "$ORGAN_FAKE_TMUX_STATE_FILE"
      exit 0
      ;;
  esac
fi

if [[ -n "${ORGAN_FAKE_TMUX_OUTPUT_FILE:-}" ]]; then
  if [[ -n "${ORGAN_FAKE_TMUX_CHUNK_BYTES:-}" ]]; then
    while IFS= read -r -N "$ORGAN_FAKE_TMUX_CHUNK_BYTES" chunk || [[ -n "$chunk" ]]; do
      printf '%s' "$chunk"
      sleep "${ORGAN_FAKE_TMUX_CHUNK_DELAY:-0}"
    done <"$ORGAN_FAKE_TMUX_OUTPUT_FILE"
  else
    cat -- "$ORGAN_FAKE_TMUX_OUTPUT_FILE"
  fi
else
  printf '%s\n' "${ORGAN_FAKE_TMUX_OUTPUT:-fallback pane output}"
fi
