#!/usr/bin/env bash

ORGAN_CONFIG=''
ORGAN_STATE_HOME=''

organ_runtime_paths_init() {
  local project_root

  project_root="$(organ_deployment_project_root)" || return 64
  ORGAN_CONFIG="$project_root/.organoun/deployment.json"
  ORGAN_STATE_HOME="$project_root/.organoun/state"
  [[ "$ORGAN_CONFIG" == /* && "$ORGAN_STATE_HOME" == /* ]] || return 64
}

organ_alias_valid() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

organ_config_schema_valid() {
  local snapshot_path="$1"

  jq -e '
    def nonempty_string: type == "string" and length > 0;
    def valid_alias: type == "string" and test("^[A-Za-z0-9._-]+$");
    def valid_target:
      type == "object"
      and ((keys_unsorted - ["alias", "transport", "host", "cwd", "mode", "tmux_target", "claude_session_id", "provider", "session_name", "model"]) | length == 0)
      and (.alias | valid_alias)
      and (.transport == "local" or .transport == "ssh")
      and ((.transport == "local" and .host == "local") or
           (.transport == "ssh" and (.host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$"))))
      and (.cwd | type == "string" and startswith("/"))
      and (.mode == "adopted" or .mode == "managed")
      and (if .mode == "adopted" then
             (.tmux_target | nonempty_string)
             and ((has("claude_session_id") | not) or (.claude_session_id == null or (.claude_session_id | nonempty_string)))
             and (has("provider") | not)
             and (has("session_name") | not)
             and (has("model") | not)
           else
             (.provider == "cc")
             and (.session_name | nonempty_string)
             and ((has("model") | not) or (.model == null or (.model | nonempty_string)))
             and (has("tmux_target") | not)
             and (has("claude_session_id") | not)
           end);
    type == "object"
    and ((keys_unsorted - ["schema_version", "targets"]) | length == 0)
    and .schema_version == "1"
    and (.targets | type == "array")
    and all(.targets[]; valid_target)
    and ([.targets[].alias] | unique | length) == (.targets | length)
  ' "$snapshot_path" >/dev/null 2>&1 || return 64
}

organ_config_snapshot_create() {
  local config_path="$1"
  local snapshot_path="$2"
  local normalized_path

  [[ -f "$config_path" && -r "$config_path" && ! -L "$config_path" ]] || return 64
  normalized_path="${snapshot_path}.normalized"
  [[ ! -e "$normalized_path" && ! -L "$normalized_path" ]] || return 64
  if organ_deployment_snapshot_create "$config_path" "$normalized_path"; then
    jq -ce '
      {
        schema_version:"1",
        targets:[
          {alias:"local-managed",transport:"local",host:"local",cwd:.local_project_root,mode:"managed",provider:"cc",session_name:"organoun-local",model:null},
          {alias:"remote-managed",transport:"ssh",host:.remote_host,cwd:.remote_cwd,mode:"managed",provider:"cc",session_name:"organoun-remote",model:null}
        ]
      }
    ' "$normalized_path" >"$snapshot_path" || {
      rm -f -- "$normalized_path" "$snapshot_path"
      return 64
    }
    rm -f -- "$normalized_path"
    chmod 400 -- "$snapshot_path" || return 64
    organ_config_schema_valid "$snapshot_path"
    return
  fi
  rm -f -- "$normalized_path"
  return 64
}

organ_runtime_config_digest() (
  local snapshot_dir snapshot_path digest

  snapshot_dir="$(organ_config_snapshot_dir)" || return 64
  snapshot_path="$snapshot_dir/targets.json"
  trap 'rm -f -- "$snapshot_path" "$snapshot_path.normalized"; rmdir -- "$snapshot_dir" 2>/dev/null || true' EXIT
  organ_config_snapshot_create "$ORGAN_CONFIG" "$snapshot_path" || return 64
  digest="$(sha256sum -- "$snapshot_path" | awk '{print $1}')" || return 64
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 64
  printf '%s\n' "$digest"
)

organ_config_valid() (
  local config_path="$1"
  local snapshot_dir snapshot_path

  umask 077
  snapshot_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-config.XXXXXX")" || return 64
  chmod 700 -- "$snapshot_dir" || {
    rmdir -- "$snapshot_dir"
    return 64
  }
  snapshot_path="$snapshot_dir/targets.json"
  trap 'rm -f -- "$snapshot_path"; rmdir -- "$snapshot_dir"' EXIT
  organ_config_snapshot_create "$config_path" "$snapshot_path"
)

organ_config_snapshot_dir() {
  local created_dir

  umask 077
  created_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-config.XXXXXX")" || return 64
  if ! chmod 700 -- "$created_dir"; then
    rmdir -- "$created_dir"
    return 64
  fi
  printf '%s\n' "$created_dir"
}

organ_targets_list() (
  local config_path="$1"
  local snapshot_dir snapshot_path

  snapshot_dir="$(organ_config_snapshot_dir)" || return 64
  snapshot_path="$snapshot_dir/targets.json"
  trap 'rm -f -- "$snapshot_path"; rmdir -- "$snapshot_dir"' EXIT
  organ_config_snapshot_create "$config_path" "$snapshot_path" || return 64
  jq -ce '.targets' "$snapshot_path" || return 64
)

organ_target_get() (
  local config_path="$1"
  local alias="$2"
  local snapshot_dir snapshot_path target query_rc

  organ_alias_valid "$alias" || return 65
  snapshot_dir="$(organ_config_snapshot_dir)" || return 64
  snapshot_path="$snapshot_dir/targets.json"
  trap 'rm -f -- "$snapshot_path"; rmdir -- "$snapshot_dir"' EXIT
  organ_config_snapshot_create "$config_path" "$snapshot_path" || return 64
  if target="$(jq -ce --arg alias "$alias" 'first(.targets[] | select(.alias == $alias))' "$snapshot_path")"; then
    printf '%s\n' "$target"
    return 0
  else
    query_rc=$?
  fi
  if [[ "$query_rc" -eq 4 ]]; then
    return 65
  else
    return 64
  fi
)
