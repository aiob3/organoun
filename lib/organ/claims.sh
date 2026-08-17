#!/usr/bin/env bash

organ_claim_path() {
  local alias="$1"
  organ_alias_valid "$alias" || return 64
  printf '%s/claims/%s.json\n' "$ORGAN_STATE_HOME" "$alias"
}

organ_claim_state_ancestors_safe() {
  local relative component current=/
  local -a components

  [[ "$ORGAN_STATE_HOME" == /* ]] || return 64
  [[ ! "$ORGAN_STATE_HOME" =~ [[:cntrl:]] ]] || return 64
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

organ_claim_directories_safe() {
  organ_claim_state_ancestors_safe || return 64
  [[ -d "$ORGAN_STATE_HOME" && ! -L "$ORGAN_STATE_HOME" ]] || return 64
  [[ -d "$ORGAN_STATE_HOME/claims" && ! -L "$ORGAN_STATE_HOME/claims" ]] || return 64
}

organ_claim_init() {
  (
    umask 077
    organ_claim_state_ancestors_safe || return 64
    [[ ! -L "$ORGAN_STATE_HOME" ]] || return 64
    if [[ -e "$ORGAN_STATE_HOME" ]]; then
      [[ -d "$ORGAN_STATE_HOME" ]] || return 64
    else
      mkdir -- "$ORGAN_STATE_HOME" || return 64
    fi
    [[ -d "$ORGAN_STATE_HOME" && ! -L "$ORGAN_STATE_HOME" ]] || return 64
    if [[ -e "$ORGAN_STATE_HOME/claims" || -L "$ORGAN_STATE_HOME/claims" ]]; then
      [[ -d "$ORGAN_STATE_HOME/claims" && ! -L "$ORGAN_STATE_HOME/claims" ]] || return 64
    else
      mkdir -- "$ORGAN_STATE_HOME/claims" || return 64
    fi
    organ_claim_state_ancestors_safe || return 64
    organ_claim_directories_safe || return 64
    chmod 700 -- "$ORGAN_STATE_HOME" "$ORGAN_STATE_HOME/claims"
  )
}

organ_claim_write() {
  local alias="$1"
  local record_json="$2"
  local claim_path claim_dir temporary

  organ_alias_valid "$alias" || return 64
  jq -e --arg alias "$alias" '
    . == {
      schema_version:"1",
      alias:$alias,
      external_id:$alias,
      controller_id:("organ:" + $alias),
      endpoint:.endpoint,
      token:.token
    }
    and (.endpoint | type == "string" and length > 0)
    and (.token | type == "string" and length > 0)
  ' >/dev/null <<<"$record_json" || return 64

  organ_claim_init || return 64
  organ_claim_directories_safe || return 64
  claim_path="$(organ_claim_path "$alias")" || return 64
  claim_dir="${claim_path%/*}"
  umask 077
  temporary="$(mktemp "$claim_dir/.${alias}.XXXXXX")" || return 64
  if ! printf '%s\n' "$record_json" >"$temporary"; then
    rm -f -- "$temporary"
    return 64
  fi
  chmod 600 -- "$temporary"
  if ! mv -f -- "$temporary" "$claim_path"; then
    rm -f -- "$temporary"
    return 64
  fi
}

organ_claim_read() {
  local alias="$1"
  local claim_path

  claim_path="$(organ_claim_path "$alias")" || return 64
  organ_claim_directories_safe || return 64
  [[ -f "$claim_path" && ! -L "$claim_path" ]] || return 64
  jq -ce --arg alias "$alias" '
    if (
      . == {
        schema_version:"1",
        alias:$alias,
        external_id:$alias,
        controller_id:("organ:" + $alias),
        endpoint:.endpoint,
        token:.token
      }
      and (.endpoint | type == "string" and length > 0)
      and (.token | type == "string" and length > 0)
    ) then . else error("invalid claim") end
  ' "$claim_path"
}

organ_claim_delete() {
  local alias="$1"
  local claim_path

  claim_path="$(organ_claim_path "$alias")" || return 64
  organ_claim_directories_safe || return 64
  rm -f -- "$claim_path"
}
