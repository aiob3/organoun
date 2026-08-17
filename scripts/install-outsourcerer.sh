#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo_root="$(cd -- "$(dirname -- "$script_path")/.." && pwd -P)"
lock_path="${ORGAN_OUTSOURCERER_LOCK:-$repo_root/vendor/outsourcerer.lock.json}"
prefix=""
apply=false

usage() {
  printf 'usage: %s --prefix PREFIX [--apply]\n' "${0##*/}" >&2
  exit 64
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ "$#" -ge 2 && -z "$prefix" ]] || usage
      prefix="$2"
      shift 2
      ;;
    --apply)
      [[ "$apply" == false ]] || usage
      apply=true
      shift
      ;;
    *) usage ;;
  esac
done

[[ -n "$prefix" ]] || usage

if ! jq -e '
  type == "object"
  and .repository == "https://github.com/alexgreensh/outsourcerer.git"
  and .commit == "3a788b8e072b915622fd80c6f8ecec64de659bd5"
  and .vendored_script == "vendor/outsourcerer/outsourcerer.sh"
  and (.script_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
  and .license == "vendor/outsourcerer/LICENSE"
  and (.license_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
' "$lock_path" >/dev/null; then
  printf 'invalid bundled Outsourcerer lockfile: %s\n' "$lock_path" >&2
  exit 64
fi

vendor_script="$repo_root/$(jq -r '.vendored_script' "$lock_path")"
vendor_license="$repo_root/$(jq -r '.license' "$lock_path")"
expected_script_sha="$(jq -r '.script_sha256' "$lock_path")"
expected_license_sha="$(jq -r '.license_sha256' "$lock_path")"

[[ -f "$vendor_script" && ! -L "$vendor_script" && -x "$vendor_script" ]] || exit 64
[[ -f "$vendor_license" && ! -L "$vendor_license" ]] || exit 64
[[ "$(sha256sum "$vendor_script" | awk '{print $1}')" == "$expected_script_sha" ]] || exit 64
[[ "$(sha256sum "$vendor_license" | awk '{print $1}')" == "$expected_license_sha" ]] || exit 64
rg -Fqx 'Required Notice: Copyright Alex Greenshpun (https://linkedin.com/in/alexgreensh)' "$vendor_license" || exit 64

# Compatibility entry point only: install-organoun.sh already publishes this
# exact snapshot under the Organoun runtime tree. No clone or network access.
printf '%s\n' "$vendor_script"
