#!/usr/bin/env bash

ORGAN_MAX_ASK_BYTES="${ORGAN_MAX_ASK_BYTES:-16384}"
ORGAN_MAX_READ_BYTES="${ORGAN_MAX_READ_BYTES:-65536}"

organ_utf8_file_valid() {
  local input_file="$1"

  [[ -r "$input_file" && ! -d "$input_file" && ! -L "$input_file" ]] || return 64
  LC_ALL=C iconv -f UTF-8 -t UTF-8 "$input_file" >/dev/null 2>&1
}

organ_text_file_valid() {
  local input_file="$1"
  local _nul_prefix

  organ_utf8_file_valid "$input_file" || return 64
  if IFS= read -r -d '' _nul_prefix <"$input_file"; then
    return 64
  fi
}

organ_read_text_file() {
  local input_file="$1"
  local output_name="$2"
  local text_value=''

  [[ "$output_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 64
  organ_text_file_valid "$input_file" || return 64
  IFS= read -r -d '' text_value <"$input_file" || true
  printf -v "$output_name" '%s' "$text_value"
}

# jq accepts duplicate object keys (last value wins) and repairs invalid UTF-8.
# This validator therefore examines the original bytes first. The lexical pass
# assigns each object its own scope and emits every raw key token; jq is used
# only on those isolated, UTF-8-valid string tokens to decode JSON escapes, so
# spellings such as "host" and "\u0068ost" compare as the same authority.
organ_json_normalize_strict() (
  local input_file="$1"
  local output_file="$2"
  local validation_dir source_snapshot key_tokens canonical_keys sorted_keys duplicate_keys normalized_stage
  local input_fd source_bytes

  [[ -f "$input_file" && ! -L "$input_file" ]] || return 64
  [[ ! -e "$output_file" && ! -L "$output_file" ]] || return 64

  umask 077
  validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-json.XXXXXX")" || return 64
  chmod 700 -- "$validation_dir" || {
    rm -rf -- "$validation_dir"
    return 64
  }
  trap 'rm -rf -- "$validation_dir"' EXIT
  source_snapshot="$validation_dir/source"
  key_tokens="$validation_dir/keys.jsonl"
  canonical_keys="$validation_dir/keys.tsv"
  sorted_keys="$validation_dir/keys.sorted.tsv"
  duplicate_keys="$validation_dir/duplicates"
  normalized_stage="$validation_dir/normalized"

  exec {input_fd}<"$input_file" || return 64
  [[ "$(stat -Lc '%F' -- "/proc/$$/fd/$input_fd" 2>/dev/null)" == 'regular file' ]] || return 64
  head -c 1048577 <&"$input_fd" >"$source_snapshot" || return 64
  exec {input_fd}<&-
  source_bytes="$(wc -c <"$source_snapshot")" || return 64
  [[ "$source_bytes" =~ ^[0-9]+$ && "$source_bytes" -le 1048576 ]] || return 64
  chmod 400 -- "$source_snapshot" || return 64
  organ_utf8_file_valid "$source_snapshot" || return 64

  if ! LC_ALL=C awk '
    BEGIN { RS = "\0"; ORS = "" }
    {
      document = $0
      document_length = length(document)
      depth = 0
      next_scope = 0
      for (cursor = 1; cursor <= document_length;) {
        byte = substr(document, cursor, 1)
        if (byte == "\"") {
          token_start = cursor
          cursor++
          closed = 0
          while (cursor <= document_length) {
            byte = substr(document, cursor, 1)
            if (byte == "\\") {
              cursor += 2
              continue
            }
            if (byte == "\"") {
              closed = 1
              break
            }
            cursor++
          }
          if (!closed) {
            next
          }
          if (depth > 0 && container_type[depth] == "object" && object_wants_key[depth]) {
            token = substr(document, token_start, cursor - token_start + 1)
            printf "[%d,%s]\n", object_scope[depth], token
            object_wants_key[depth] = 0
          }
          cursor++
          continue
        }
        if (byte == "{") {
          depth++
          container_type[depth] = "object"
          object_scope[depth] = ++next_scope
          object_wants_key[depth] = 1
        } else if (byte == "[") {
          depth++
          container_type[depth] = "array"
          object_scope[depth] = 0
          object_wants_key[depth] = 0
        } else if (byte == "}" || byte == "]") {
          delete container_type[depth]
          delete object_scope[depth]
          delete object_wants_key[depth]
          if (depth > 0) {
            depth--
          }
        } else if (byte == "," && depth > 0 && container_type[depth] == "object") {
          object_wants_key[depth] = 1
        }
        cursor++
      }
    }
  ' "$source_snapshot" >"$key_tokens"; then
    return 64
  fi

  if [[ -s "$key_tokens" ]]; then
    if ! jq -er '[.[0], (.[1] | @base64)] | @tsv' "$key_tokens" >"$canonical_keys" 2>/dev/null; then
      return 64
    fi
    LC_ALL=C sort "$canonical_keys" >"$sorted_keys" || return 64
    uniq -d "$sorted_keys" >"$duplicate_keys" || return 64
    [[ ! -s "$duplicate_keys" ]] || return 64
  fi

  if ! jq -ce -s 'if length == 1 then .[0] else error("one JSON value required") end' \
    "$source_snapshot" >"$normalized_stage" 2>/dev/null; then
    return 64
  fi
  chmod 600 -- "$normalized_stage" || return 64
  mv -f -- "$normalized_stage" "$output_file"
)

organ_emit_ok() {
  jq -cn --arg action "$1" --arg target "$2" --arg host "$3" \
    --arg state "$4" --arg delivery "$5" \
    'input as $data | {schema_version:"1",ok:true,action:$action,target:$target,host:$host,state:$state,delivery:$delivery,data:$data}' \
    <<<"$6"
}

organ_emit_error() {
  jq -cn --arg action "$1" --arg target "$2" --arg host "$3" \
    --arg code "$4" --arg message "$5" \
    '{schema_version:"1",ok:false,action:$action,target:$target,host:$host,state:"unknown",delivery:"not-applicable",error:{code:$code,message:$message}}'
}
