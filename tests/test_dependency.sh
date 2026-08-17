#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: the bundled adapter drifts from its immutable pin, loses the
# required upstream notice, resolves outside Organoun, or an installation
# reaches the network instead of publishing the reviewed local snapshot.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env

lock_path="$REPO_ROOT/vendor/outsourcerer.lock.json"
vendor_script="$REPO_ROOT/vendor/outsourcerer/outsourcerer.sh"
vendor_license="$REPO_ROOT/vendor/outsourcerer/LICENSE"
script_sha="bcb4760cb66f1e971b9b909d36913ca6929cb95d7d3ccf8eb883cca5726cc984"
license_sha="6bccffcb3545e3918832905c19db3be80e6cd1ce4c279093297ad93b1886b156"

lock_json="$(jq -c . "$lock_path")"
assert_jq "$lock_json" \
  '.repository == "https://github.com/alexgreensh/outsourcerer.git"
   and .tag == "v0.8.2"
   and .commit == "3a788b8e072b915622fd80c6f8ecec64de659bd5"
   and .upstream_script == "plugins/outsourcerer/skills/outsourcerer/scripts/outsourcerer.sh"
   and .vendored_script == "vendor/outsourcerer/outsourcerer.sh"
   and .script_sha256 == "bcb4760cb66f1e971b9b909d36913ca6929cb95d7d3ccf8eb883cca5726cc984"
   and .license == "vendor/outsourcerer/LICENSE"
   and .license_sha256 == "6bccffcb3545e3918832905c19db3be80e6cd1ce4c279093297ad93b1886b156"'

[[ -f "$vendor_script" && ! -L "$vendor_script" && -x "$vendor_script" ]] || {
  printf 'vendored Outsourcerer script is missing, unsafe, or not executable\n' >&2
  exit 1
}
[[ -f "$vendor_license" && ! -L "$vendor_license" ]] || {
  printf 'vendored Outsourcerer license is missing or unsafe\n' >&2
  exit 1
}
assert_eq "$script_sha" "$(sha256sum "$vendor_script" | awk '{print $1}')"
assert_eq "$license_sha" "$(sha256sum "$vendor_license" | awk '{print $1}')"
rg -Fqx 'Required Notice: Copyright Alex Greenshpun (https://linkedin.com/in/alexgreensh)' "$vendor_license"
rg -Fqx '# PolyForm Noncommercial License 1.0.0' "$vendor_license"
bash -n "$vendor_script"

unset ORGAN_OUTSOURCERER
ORGAN_ROOT="$REPO_ROOT"
export ORGAN_ROOT
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/organ/outsourcerer.sh"
assert_eq "$vendor_script" "$(organ_osrc_bin)"
ORGAN_OUTSOURCERER="$TEST_TMP/operator-adapter"
export ORGAN_OUTSOURCERER
assert_eq "$ORGAN_OUTSOURCERER" "$(organ_osrc_bin)"
unset ORGAN_OUTSOURCERER

network_bin="$TEST_TMP/no-network-bin"
network_log="$TEST_TMP/network.log"
mkdir -p -- "$network_bin"
: >"$network_log"
for command_name in git curl wget; do
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\\n" "${0##*/}" >>"$ORGAN_NETWORK_LOG"' \
    'exit 97' >"$network_bin/$command_name"
  chmod 700 -- "$network_bin/$command_name"
done
export ORGAN_NETWORK_LOG="$network_log"

prefix="$TEST_TMP/install-home"
mkdir -p -- "$prefix"
PATH="$network_bin:$PATH" "$REPO_ROOT/scripts/install-organoun.sh" --prefix "$prefix" --apply
installed_root="$prefix/.local/share/organoun"
installed_script="$installed_root/vendor/outsourcerer/outsourcerer.sh"
installed_license="$installed_root/vendor/outsourcerer/LICENSE"
assert_eq "$script_sha" "$(sha256sum "$installed_script" | awk '{print $1}')"
assert_eq "$license_sha" "$(sha256sum "$installed_license" | awk '{print $1}')"

ORGAN_ROOT="$installed_root"
export ORGAN_ROOT
assert_eq "$installed_script" "$(organ_osrc_bin)"

compat_output="$(PATH="$network_bin:$PATH" "$REPO_ROOT/scripts/install-outsourcerer.sh" --prefix "$TEST_TMP/ignored-prefix" --apply)"
assert_eq "$vendor_script" "$compat_output"
[[ ! -s "$network_log" ]] || {
  printf 'self-contained installation attempted network commands:\n' >&2
  sed -n '1,20p' "$network_log" >&2
  exit 1
}

printf 'dependency tests passed\n'
