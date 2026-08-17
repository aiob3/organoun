#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  printf 'usage: %s\n' "${0##*/}" >&2
  exit 64
fi

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

for required in jq organ awk iconv mktemp sort uniq chmod rm mv; do
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
trap 'rm -rf -- "$smoke_tmpdir"' EXIT

SMOKE_JSON=''
SMOKE_RC=''

smoke_capture_command() {
  local raw_file stderr_file normalized_file command_rc

  raw_file="$(mktemp "$smoke_tmpdir/raw.XXXXXX")" || return 69
  stderr_file="${raw_file}.stderr"
  normalized_file="${raw_file}.json"
  if "$@" >"$raw_file" 2>"$stderr_file"; then
    command_rc=0
  else
    command_rc=$?
  fi

  [[ ! -s "$stderr_file" ]] || return 64
  organ_json_normalize_strict "$raw_file" "$normalized_file" || return 64
  SMOKE_JSON="$normalized_file"
  SMOKE_RC="$command_rc"
}

smoke_fail_closed() {
  printf 'smoke JSON boundary validation failed\n' >&2
  exit 64
}

validate_status_envelope() {
  local json_file="$1"

  jq -e -s '
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
    .target == "remote-managed" and
    (.host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$") and . != "local") and
    .delivery == "not-applicable" and (.state | valid_state) and
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
  local command_rc="$2"

  validate_status_envelope "$json_file" || return 64
  case "$command_rc" in
    0) jq -e '.ok == true' "$json_file" >/dev/null ;;
    64) jq -e '.ok == false and .state == "unknown"' "$json_file" >/dev/null ;;
    *) return 64 ;;
  esac
}

smoke_capture_command organ status remote-managed --json || smoke_fail_closed
validate_status_outcome "$SMOKE_JSON" "$SMOKE_RC" || smoke_fail_closed
printf 'ORGAN_REMOTE_SMOKE_OK\n'
