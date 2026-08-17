#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
organ_root="$(cd -- "$(dirname -- "$script_path")/.." && pwd -P)"
organ_bin="$organ_root/bin/organ"
[[ -x "$organ_bin" ]] || {
  printf 'Organoun CLI is unavailable: %s\n' "$organ_bin" >&2
  exit 64
}
[[ -r /dev/tty && -w /dev/tty ]] || {
  printf 'onboarding requires an attached operator terminal\n' >&2
  exit 64
}

printf 'Local project root: ' >/dev/tty
IFS= read -r local_project_root </dev/tty
printf 'Remote SSH alias: ' >/dev/tty
IFS= read -r remote_host </dev/tty
printf 'Remote CWD: ' >/dev/tty
IFS= read -r remote_cwd </dev/tty

deployment_json="$(jq -cn \
  --arg local_project_root "$local_project_root" \
  --arg remote_host "$remote_host" \
  --arg remote_cwd "$remote_cwd" \
  '{schema_version:"1",local_project_root:$local_project_root,remote_host:$remote_host,remote_cwd:$remote_cwd}')"
printf '%s' "$deployment_json" | "$organ_bin" onboard --stdin --json
