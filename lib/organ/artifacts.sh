#!/usr/bin/env bash

# Task 5 deliberately uses a fixed conservative cap. A larger artifact can be
# declared by verification, but local fetch never reads more than 1 MiB.
ORGAN_MAX_FETCH_BYTES=1048576

organ_artifact_id_valid() {
  [[ "$1" =~ ^artifact-[a-f0-9]{12}$ ]]
}

organ_artifact_digest() {
  local job_id="$1"
  local relative_path="$2"
  local collision_index="${3:-}"

  if [[ -n "$collision_index" ]]; then
    { printf '%s\0%s\0%s' "$job_id" "$relative_path" "$collision_index"; } | sha256sum | cut -c1-12
  else
    { printf '%s\0%s' "$job_id" "$relative_path"; } | sha256sum | cut -c1-12
  fi
}

organ_artifacts_manifest() {
  local job_json="$1"
  local verification_json="$2"
  local job_id host root canonical_root base_sha relative_path declared_path resolved_path
  local digest artifact_id collision_index size_bytes artifact manifest='[]'
  local -A used_ids=()

  [[ "$(jq -r '.status' <<<"$verification_json")" == accepted ]] || {
    printf '[]\n'
    return 0
  }
  job_id="$(jq -r '.job_id' <<<"$job_json")"
  host="$(jq -r '.host' <<<"$job_json")"
  root="$(jq -r '.worktree' <<<"$job_json")"
  base_sha="$(jq -r '.base_sha' <<<"$job_json")"
  canonical_root="$(realpath -e -- "$root" 2>/dev/null)" || return 64
  [[ "$canonical_root" == "$root" ]] || return 64

  while IFS= read -r -d '' relative_path; do
    organ_guard_relative_path_valid "$relative_path" || return 64
    declared_path="$root/$relative_path"
    [[ -f "$declared_path" && ! -L "$declared_path" ]] || continue
    resolved_path="$(realpath -e -- "$declared_path" 2>/dev/null)" || continue
    [[ "$resolved_path" == "$canonical_root/"* ]] || continue
    size_bytes="$(stat -c '%s' -- "$declared_path")" || return 64
    digest="$(organ_artifact_digest "$job_id" "$relative_path")" || return 64
    artifact_id="artifact-$digest"
    collision_index=0
    while [[ -n "${used_ids[$artifact_id]:-}" && "${used_ids[$artifact_id]}" != "$relative_path" ]]; do
      ((collision_index += 1))
      digest="$(organ_artifact_digest "$job_id" "$relative_path" "$collision_index")" || return 64
      artifact_id="artifact-$digest"
    done
    used_ids["$artifact_id"]="$relative_path"
    artifact="$(jq -cn --arg artifact_id "$artifact_id" --arg host "$host" \
      --arg relative_path "$relative_path" --argjson size_bytes "$size_bytes" --arg commit "$base_sha" \
      '{artifact_id:$artifact_id,host:$host,relative_path:$relative_path,size_bytes:$size_bytes,commit:$commit}')" || return 64
    manifest="$(jq -cn --argjson manifest "$manifest" --argjson artifact "$artifact" '$manifest + [$artifact]')" || return 64
  done < <(jq --raw-output0 '.changed_paths[]' <<<"$verification_json")
  printf '%s\n' "$manifest"
}

organ_artifact_fetch() {
  local job_json="$1"
  local artifact_id="$2"
  local mode="$3"
  local entry root canonical_root relative_path declared_path resolved_path fd_path fd_resolved
  local file_type size_bytes commit
  local artifact_fd

  organ_artifact_id_valid "$artifact_id" || return 65
  [[ "$(jq -r '.mode' <<<"$job_json")" == edit && "$(jq -r '.state' <<<"$job_json")" == accepted ]] || return 66
  entry="$(jq -ce --arg artifact_id "$artifact_id" 'first(.artifacts[] | select(.artifact_id == $artifact_id))' <<<"$job_json")" || return 67
  root="$(jq -r '.worktree' <<<"$job_json")"
  canonical_root="$(realpath -e -- "$root" 2>/dev/null)" || return 68
  [[ "$canonical_root" == "$root" ]] || return 68
  relative_path="$(jq -r '.relative_path' <<<"$entry")"
  organ_guard_relative_path_valid "$relative_path" || return 68
  declared_path="$root/$relative_path"
  [[ -f "$declared_path" && ! -L "$declared_path" ]] || return 68
  resolved_path="$(realpath -e -- "$declared_path" 2>/dev/null)" || return 68
  [[ "$resolved_path" == "$canonical_root/"* ]] || return 68
  exec {artifact_fd}<"$declared_path" || return 68
  fd_path="/proc/$BASHPID/fd/$artifact_fd"
  fd_resolved="$(readlink -f -- "$fd_path" 2>/dev/null)" || {
    exec {artifact_fd}>&-
    return 68
  }
  if [[ "$fd_resolved" != "$resolved_path" || "$fd_resolved" != "$canonical_root/"* ]]; then
    exec {artifact_fd}>&-
    return 68
  fi
  file_type="$(LC_ALL=C stat -Lc '%F' -- "$fd_path" 2>/dev/null)" || {
    exec {artifact_fd}>&-
    return 68
  }
  [[ "$file_type" == 'regular file' ]] || {
    exec {artifact_fd}>&-
    return 68
  }
  size_bytes="$(stat -Lc '%s' -- "$fd_path" 2>/dev/null)" || {
    exec {artifact_fd}>&-
    return 68
  }
  if (( size_bytes > ORGAN_MAX_FETCH_BYTES )); then
    exec {artifact_fd}>&-
    return 75
  fi
  commit="$(jq -r '.commit // empty' <<<"$entry")"
  case "$mode" in
    stdout)
      if ! cat <&"$artifact_fd"; then
        exec {artifact_fd}>&-
        return 74
      fi
      ;;
    json)
      if ! jq -cn --arg artifact_id "$artifact_id" --arg relative_path "$relative_path" \
        --argjson size_bytes "$size_bytes" --arg commit "$commit" \
        '{artifact_id:$artifact_id,relative_path:$relative_path,size_bytes:$size_bytes,commit:$commit}'; then
        exec {artifact_fd}>&-
        return 74
      fi
      ;;
    *)
      exec {artifact_fd}>&-
      return 64
      ;;
  esac
  exec {artifact_fd}>&-
}
