#!/usr/bin/env bash

ORGAN_DEPLOYMENT_RELATIVE_PATH='.organoun/deployment.json'

organ_deployment_host_valid() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$ ]]
}

organ_deployment_project_root() {
  local physical_root git_root

  physical_root="$(pwd -P)" || return 64
  git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 64
  [[ "$git_root" == /* ]] || return 64
  git_root="$(cd -- "$git_root" && pwd -P)" || return 64
  [[ "$physical_root" == "$git_root" ]] || return 64
  printf '%s\n' "$git_root"
}

organ_deployment_path_resolve() {
  local project_root

  project_root="$(organ_deployment_project_root)" || return 64
  printf '%s/%s\n' "$project_root" "$ORGAN_DEPLOYMENT_RELATIVE_PATH"
}

organ_deployment_schema_valid() {
  local snapshot_path="$1"

  jq -e '
    type == "object" and
    (keys_unsorted | sort) == ["local_project_root","remote_cwd","remote_host","schema_version"] and
    .schema_version == "1" and
    (.local_project_root | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not)) and
    (.remote_host | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,252}$")) and
    (.remote_cwd | type == "string" and startswith("/") and (test("[[:cntrl:]]") | not))
  ' "$snapshot_path" >/dev/null 2>&1 || return 64
}

organ_deployment_snapshot_create() {
  local input_path="$1"
  local snapshot_path="$2"
  local project_root declared_root remote_host

  project_root="$(organ_deployment_project_root)" || return 64
  organ_json_normalize_strict "$input_path" "$snapshot_path" || return 64
  chmod 400 -- "$snapshot_path" || return 64
  organ_deployment_schema_valid "$snapshot_path" || return 64
  declared_root="$(jq -er '.local_project_root' "$snapshot_path")" || return 64
  [[ "$declared_root" == "$project_root" ]] || return 64
  remote_host="$(jq -er '.remote_host' "$snapshot_path")" || return 64
  organ_deployment_host_valid "$remote_host" || return 64
}

organ_deployment_digest() {
  local snapshot_path="$1"

  [[ -f "$snapshot_path" && ! -L "$snapshot_path" ]] || return 64
  sha256sum -- "$snapshot_path" | awk '{print $1}'
}

organ_deployment_route_check() (
  local snapshot_path="$1"
  local remote_host capture_dir stdout_file stderr_file resolved_host

  remote_host="$(jq -er '.remote_host' "$snapshot_path")" || return 64
  organ_deployment_host_valid "$remote_host" || return 64
  command -v ssh >/dev/null 2>&1 || return 64
  command -v timeout >/dev/null 2>&1 || return 64

  umask 077
  capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-route.XXXXXX")" || return 64
  chmod 700 -- "$capture_dir" || {
    rmdir -- "$capture_dir"
    return 64
  }
  trap 'rm -rf -- "$capture_dir"' EXIT
  stdout_file="$capture_dir/stdout"
  stderr_file="$capture_dir/stderr"
  if ! LC_ALL=C timeout --signal=TERM --kill-after=1s 5s ssh -G "$remote_host" \
      >"$stdout_file" 2>"$stderr_file"; then
    return 64
  fi
  [[ ! -s "$stderr_file" ]] || return 64
  resolved_host="$(LC_ALL=C awk '$1 == "hostname" && NF == 2 {print $2}' "$stdout_file")" || return 64
  [[ -n "$resolved_host" && "$resolved_host" != *$'\n'* &&
    "$resolved_host" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,252}$ ]] || return 64
)

organ_deployment_gitignore_publish() (
  local project_root="$1"
  local ignore_path stage mode changed=false

  ignore_path="$project_root/.gitignore"
  if [[ -e "$ignore_path" || -L "$ignore_path" ]]; then
    [[ -f "$ignore_path" && ! -L "$ignore_path" ]] || return 64
    mode="$(stat -c '%a' -- "$ignore_path")" || return 64
  else
    mode=644
  fi
  stage="$(mktemp "$project_root/.gitignore.organoun.XXXXXX")" || return 64
  trap '[[ -z "${stage:-}" ]] || rm -f -- "$stage"' EXIT
  chmod "$mode" -- "$stage" || return 64
  if [[ -f "$ignore_path" ]]; then
    cp -- "$ignore_path" "$stage" || return 64
  fi
  if ! grep -Fqx -- '/.organoun/deployment.json' "$stage" 2>/dev/null; then
    if [[ -s "$stage" && "$(tail -c 1 -- "$stage" | wc -l)" -eq 0 ]]; then
      printf '\n' >>"$stage" || return 64
    fi
    printf '%s\n' '/.organoun/deployment.json' >>"$stage" || return 64
    changed=true
  fi
  if ! grep -Fqx -- '/.organoun/state/' "$stage" 2>/dev/null; then
    if [[ -s "$stage" && "$(tail -c 1 -- "$stage" | wc -l)" -eq 0 ]]; then
      printf '\n' >>"$stage" || return 64
    fi
    printf '%s\n' '/.organoun/state/' >>"$stage" || return 64
    changed=true
  fi
  if [[ "$changed" == true ]]; then
    mv -T -- "$stage" "$ignore_path" || return 64
    stage=''
  fi
)

organ_deployment_onboard() (
  local input_path="$1"
  local project_root deployment_dir deployment_path lock_path validation_dir snapshot_path
  local published_stage digest data

  project_root="$(organ_deployment_project_root)" || {
    organ_emit_error onboard '' '' ONBOARD_ROOT_INVALID 'run onboarding from the canonical Git project root'
    return 64
  }
  deployment_dir="$project_root/.organoun"
  deployment_path="$deployment_dir/deployment.json"
  lock_path="$project_root/.organoun-onboard.lock"
  [[ ! -e "$deployment_path" && ! -L "$deployment_path" ]] || {
    organ_emit_error onboard '' '' DEPLOYMENT_ALREADY_EXISTS 'deployment already exists; refusing overwrite'
    return 64
  }
  if ! mkdir -- "$lock_path" 2>/dev/null; then
    organ_emit_error onboard '' '' ONBOARD_IN_PROGRESS 'another onboarding operation is active'
    return 75
  fi
  trap 'rm -f -- "${published_stage:-}"; rm -rf -- "${validation_dir:-}"; rmdir -- "$lock_path" 2>/dev/null || true' EXIT

  umask 077
  validation_dir="$(mktemp -d "${TMPDIR:-/tmp}/organoun-onboard.XXXXXX")" || return 64
  chmod 700 -- "$validation_dir" || return 64
  snapshot_path="$validation_dir/deployment.json"
  if ! organ_deployment_snapshot_create "$input_path" "$snapshot_path"; then
    organ_emit_error onboard '' '' DEPLOYMENT_INVALID 'deployment input is missing or invalid'
    return 64
  fi
  if ! organ_deployment_route_check "$snapshot_path"; then
    organ_emit_error onboard '' '' ROUTE_INVALID 'configured SSH route could not be resolved locally'
    return 64
  fi
  if ! organ_deployment_gitignore_publish "$project_root"; then
    organ_emit_error onboard '' '' GITIGNORE_UNSAFE 'deployment could not be protected by the project gitignore'
    return 64
  fi
  if [[ -e "$deployment_dir" || -L "$deployment_dir" ]]; then
    [[ -d "$deployment_dir" && ! -L "$deployment_dir" &&
      "$(stat -c '%a' -- "$deployment_dir")" == 700 ]] || {
      organ_emit_error onboard '' '' DEPLOYMENT_DIRECTORY_UNSAFE 'project deployment directory is unsafe'
      return 64
    }
  else
    mkdir -m 700 -- "$deployment_dir" || return 64
  fi
  [[ ! -e "$deployment_path" && ! -L "$deployment_path" ]] || {
    organ_emit_error onboard '' '' DEPLOYMENT_ALREADY_EXISTS 'deployment appeared during onboarding; refusing overwrite'
    return 64
  }
  published_stage="$(mktemp "$deployment_dir/.deployment.XXXXXX")" || return 64
  install -m 600 -- "$snapshot_path" "$published_stage" || return 64
  mv -T -- "$published_stage" "$deployment_path" || return 64
  published_stage=''

  [[ -f "$deployment_path" && ! -L "$deployment_path" &&
    "$(stat -c '%a' -- "$deployment_path")" == 600 ]] || return 64
  cmp -s -- "$snapshot_path" "$deployment_path" || return 64
  git -C "$project_root" check-ignore -q --no-index -- '.organoun/deployment.json' || return 64
  git -C "$project_root" check-ignore -q --no-index -- '.organoun/state/' || return 64
  digest="$(organ_deployment_digest "$snapshot_path")" || return 64
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 64
  data='{"message":"Organoun Connected","write_count":1,"submission_count":1,"config_path":".organoun/deployment.json","gitignored":true}'
  organ_emit_ok onboard '' '' connected not-applicable "$data"
)
