#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'usage: %s [--canary]\n' "${0##*/}" >&2
  exit 64
}

require_command() {
  command -v "$1" >/dev/null || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 69
  }
}

require_command readlink
smoke_script_path="$(readlink -f -- "${BASH_SOURCE[0]}")" || {
  printf 'could not resolve smoke script path\n' >&2
  exit 69
}
smoke_script_dir="${smoke_script_path%/*}"
smoke_root="$(cd -- "$smoke_script_dir/.." && pwd -P)" || {
  printf 'could not resolve smoke script root\n' >&2
  exit 69
}
smoke_common="$smoke_root/lib/organ/common.sh"
[[ -f "$smoke_common" && ! -L "$smoke_common" && -r "$smoke_common" ]] || {
  printf 'missing committed JSON boundary helper\n' >&2
  exit 69
}
# shellcheck disable=SC1090
source "$smoke_common"

for required in jq tmux claude organ awk iconv mktemp sort uniq chmod rm mv; do
  require_command "$required"
done

smoke_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-smoke.XXXXXX")" || {
  printf 'could not create private smoke workspace\n' >&2
  exit 69
}
chmod 700 -- "$smoke_tmpdir" || {
  rm -rf -- "$smoke_tmpdir"
  printf 'could not protect private smoke workspace\n' >&2
  exit 69
}
SMOKE_JSON=''
SMOKE_RC=''
smoke_claim_active=false

smoke_cleanup() {
  local exit_rc=$?

  trap - EXIT
  if [[ "$smoke_claim_active" == true ]]; then
    smoke_capture_command - organ release claude-onp --json >/dev/null 2>&1 || true
    smoke_claim_active=false
  fi
  rm -rf -- "$smoke_tmpdir"
  exit "$exit_rc"
}
trap smoke_cleanup EXIT

smoke_capture_command() {
  local stdin_file="$1"
  shift
  local raw_file stderr_file normalized_file command_rc

  SMOKE_JSON=''
  SMOKE_RC=''

  raw_file="$(mktemp "$smoke_tmpdir/raw.XXXXXX")" || return 69
  stderr_file="${raw_file}.stderr"
  normalized_file="${raw_file}.json"
  if [[ "$stdin_file" == '-' ]]; then
    if "$@" >"$raw_file" 2>"$stderr_file"; then
      command_rc=0
    else
      command_rc=$?
    fi
  else
    [[ -f "$stdin_file" && ! -L "$stdin_file" ]] || return 64
    if "$@" <"$stdin_file" >"$raw_file" 2>"$stderr_file"; then
      command_rc=0
    else
      command_rc=$?
    fi
  fi

  SMOKE_RC="$command_rc"
  [[ ! -s "$stderr_file" ]] || return 64
  organ_json_normalize_strict "$raw_file" "$normalized_file" || return 64
  SMOKE_JSON="$normalized_file"
}

smoke_fail_closed() {
  printf 'smoke JSON boundary validation failed\n' >&2
  exit 64
}

validate_list_envelope() {
  local json_file="$1"

  jq -e -s '
    def nonempty_string: type == "string" and length > 0;
    def valid_alias: type == "string" and test("^[A-Za-z0-9._-]+$");
    def valid_target:
      type == "object" and
      (.alias | valid_alias) and
      (.transport == "local" or .transport == "ssh") and
      ((.transport == "local" and .host == "local") or
       (.transport == "ssh" and
        (.host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$") and . != "local"))) and
      (.cwd | type == "string" and startswith("/")) and
      (.mode == "adopted" or .mode == "managed") and
      (if .mode == "adopted" then
         ((keys_unsorted - ["alias", "transport", "host", "cwd", "mode", "tmux_target", "claude_session_id"]) | length == 0) and
         (.tmux_target | nonempty_string) and
         ((has("claude_session_id") | not) or
          (.claude_session_id == null or (.claude_session_id | nonempty_string))) and
         (has("provider") | not) and (has("session_name") | not) and (has("model") | not)
       else
         ((keys_unsorted - ["alias", "transport", "host", "cwd", "mode", "provider", "session_name", "model"]) | length == 0) and
         .provider == "cc" and (.session_name | nonempty_string) and
         ((has("model") | not) or (.model == null or (.model | nonempty_string))) and
         (has("tmux_target") | not) and (has("claude_session_id") | not)
       end);
    def valid_data:
      type == "object" and (keys_unsorted | sort) == ["targets"] and
      (.targets | type == "array" and all(.[]; valid_target)) and
      (([.targets[].alias] | unique | length) == (.targets | length));
    length == 1 and (.[0] |
    type == "object" and
    (keys_unsorted | sort) == ["action", "data", "delivery", "host", "ok", "schema_version", "state", "target"] and
    .schema_version == "1" and .ok == true and .action == "list" and
    .target == "" and .host == "" and .state == "unknown" and
    .delivery == "not-applicable" and (.data | valid_data))
  ' "$json_file" >/dev/null
}

validate_status_envelope() {
  local json_file="$1"
  local target="$2"
  local host="$3"

  jq -e -s --arg target "$target" --arg host "$host" '
    def valid_state:
      . == "unknown" or . == "idle" or . == "working" or . == "waiting" or
      . == "done" or . == "stopped" or . == "unreachable" or
      . == "delivery-unknown" or . == "accepted" or . == "blocked-scope" or
      . == "blocked-verification";
    def valid_error:
      type == "object" and (keys_unsorted | sort) == ["code", "message"] and
      (.code | type == "string" and length > 0 and length <= 128) and
      (.message | type == "string" and length > 0 and utf8bytelength <= 4096);
    length == 1 and (.[0] |
    type == "object" and .schema_version == "1" and .action == "status" and
    .target == $target and .host == $host and .delivery == "not-applicable" and
    (.state | valid_state) and
    (if .ok == true then
       (keys_unsorted | sort) == ["action", "data", "delivery", "host", "ok", "schema_version", "state", "target"] and
       .data == {}
     elif .ok == false then
       .state == "unknown" and
       (keys_unsorted | sort) == ["action", "delivery", "error", "host", "ok", "schema_version", "state", "target"] and
       (.error | valid_error)
     else false end))
  ' "$json_file" >/dev/null
}

validate_status_outcome() {
  local json_file="$1"
  local target="$2"
  local host="$3"
  local command_rc="$4"

  validate_status_envelope "$json_file" "$target" "$host" || return 64
  case "$command_rc" in
    0) jq -e '.ok == true' "$json_file" >/dev/null ;;
    64) jq -e '.ok == false and .state == "unknown"' "$json_file" >/dev/null ;;
    *) return 64 ;;
  esac
}

validate_read_success() {
  local json_file="$1"

  jq -e -s '
    def valid_state:
      . == "unknown" or . == "idle" or . == "working" or . == "waiting" or
      . == "done" or . == "stopped" or . == "unreachable" or
      . == "delivery-unknown" or . == "accepted" or . == "blocked-scope" or
      . == "blocked-verification";
    length == 1 and (.[0] |
    type == "object" and
    (keys_unsorted | sort) == ["action", "data", "delivery", "host", "ok", "schema_version", "state", "target"] and
    .schema_version == "1" and .ok == true and .action == "read" and
    .target == "claude-onp" and .host == "local" and
    (.state | valid_state) and .delivery == "not-applicable" and
    (.data | type == "object" and (keys_unsorted | sort) == ["excerpt", "truncated"] and
      (.excerpt | type == "string" and utf8bytelength <= 65536) and
      (.truncated | type == "boolean")))
  ' "$json_file" >/dev/null
}

validate_canary_response() {
  local json_file="$1"

  validate_read_success "$json_file" &&
    jq -e --arg expected 'ORGANOUN_LOCAL_CANARY_OK' \
      '.data.excerpt | split("\n") | index($expected) != null' "$json_file" >/dev/null
}

validate_local_success() {
  local action="$1"
  local delivery="$2"
  local json_file="$3"

  jq -e -s --arg action "$action" --arg delivery "$delivery" '
    length == 1 and (.[0] |
    type == "object" and
    (keys_unsorted | sort) == ["action", "data", "delivery", "host", "ok", "schema_version", "state", "target"] and
    .schema_version == "1" and .ok == true and .action == $action and
    .target == "claude-onp" and .host == "local" and .state == "unknown" and
    .delivery == $delivery and .data == {})
  ' "$json_file" >/dev/null
}

validate_post_release_refusal() {
  local json_file="$1"

  jq -e -s '
    length == 1 and (.[0] |
    type == "object" and
    (keys_unsorted | sort) == ["action", "delivery", "error", "host", "ok", "schema_version", "state", "target"] and
    .schema_version == "1" and .ok == false and .action == "ask" and
    .target == "claude-onp" and .host == "local" and .state == "unknown" and
    .delivery == "not-applicable" and
    (.error | type == "object" and (keys_unsorted | sort) == ["code", "message"] and
      .code == "CLAIM_REQUIRED" and (.message | type == "string" and length > 0 and utf8bytelength <= 4096)))
  ' "$json_file" >/dev/null
}

case "${1:-}" in
  '') canary=false ;;
  --canary) canary=true ;;
  *) usage ;;
esac
[[ "$#" -le 1 ]] || usage

smoke_capture_command - organ list --json || smoke_fail_closed
if [[ "$SMOKE_RC" != 0 ]] || ! validate_list_envelope "$SMOKE_JSON"; then
  smoke_fail_closed
fi
smoke_capture_command - organ status claude-onp --json || smoke_fail_closed
validate_status_outcome "$SMOKE_JSON" claude-onp local "$SMOKE_RC" || smoke_fail_closed

if [[ "$canary" == true ]]; then
  [[ -t 0 && -t 1 ]] || {
    printf 'canary requires an interactive terminal\n' >&2
    exit 64
  }

  printf 'Canary target: claude-onp\nType YES to claim, ask once, and release claude-onp: ' >/dev/tty
  IFS= read -r confirmation </dev/tty
  [[ "$confirmation" == YES ]] || {
    printf 'canary not confirmed\n' >&2
    exit 64
  }

  smoke_capture_command - organ read claude-onp --json || smoke_fail_closed
  if [[ "$SMOKE_RC" != 0 ]] || ! validate_read_success "$SMOKE_JSON"; then
    smoke_fail_closed
  fi

  if smoke_capture_command - organ claim claude-onp --json; then
    claim_capture_ok=true
  else
    claim_capture_ok=false
  fi
  if [[ "$SMOKE_RC" == 0 ]]; then
    smoke_claim_active=true
  fi
  [[ "$claim_capture_ok" == true ]] || smoke_fail_closed
  if [[ "$SMOKE_RC" != 0 ]] || ! validate_local_success claim confirmed "$SMOKE_JSON"; then
    smoke_fail_closed
  fi
  canary_input="$(mktemp "$smoke_tmpdir/input.XXXXXX")" || {
    printf 'could not create private canary input\n' >&2
    exit 69
  }
  printf '%s' 'Responda exatamente ORGANOUN_LOCAL_CANARY_OK' >"$canary_input"
  smoke_capture_command "$canary_input" organ ask claude-onp --stdin --json || smoke_fail_closed
  if [[ "$SMOKE_RC" != 0 ]] || ! validate_local_success ask unknown "$SMOKE_JSON"; then
    smoke_fail_closed
  fi
  smoke_capture_command - organ read claude-onp --json || smoke_fail_closed
  if [[ "$SMOKE_RC" != 0 ]] || ! validate_canary_response "$SMOKE_JSON"; then
    smoke_fail_closed
  fi
  smoke_capture_command - organ release claude-onp --json || smoke_fail_closed
  if [[ "$SMOKE_RC" != 0 ]] || ! validate_local_success release confirmed "$SMOKE_JSON"; then
    smoke_fail_closed
  fi
  smoke_claim_active=false

  # A second delivery is intentionally attempted only after release.  It must
  # be refused; a successful result would mean the adopted-session gate failed.
  if ! smoke_capture_command "$canary_input" organ ask claude-onp --stdin --json ||
    [[ "$SMOKE_RC" != 64 ]] || ! validate_post_release_refusal "$SMOKE_JSON"; then
    printf 'post-release ask was not refused as expected\n' >&2
    exit 70
  fi
fi

printf 'ORGAN_LOCAL_SMOKE_OK\n'
