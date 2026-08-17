#!/usr/bin/env bash
set -euo pipefail

# Breaks caught: exact-limit escapable pane text crosses the exec argv limit,
# or byte truncation splits UTF-8 and expands the decoded public excerpt.
# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

new_test_env
cwd="$TEST_TMP/target-cwd"
mkdir -p -- "$cwd"
config="$TEST_TMP/targets.json"
jq -cn --arg cwd "$cwd" '
  {schema_version:"1",targets:[
    {alias:"fallback",transport:"local",host:"local",cwd:$cwd,mode:"adopted",tmux_target:"only-this-pane.4",claude_session_id:null}
  ]}' >"$config"

export ORGAN_CONFIG="$config"
export ORGAN_TMUX="$REPO_ROOT/tests/fixtures/fake-tmux.sh"
export ORGAN_FAKE_TMUX_LOG="$TEST_TMP/tmux.log"
: >"$ORGAN_FAKE_TMUX_LOG"

failures=0

quote_output="$TEST_TMP/quote-pane.txt"
quote_decoded="$TEST_TMP/quote-decoded.txt"
head -c 65536 /dev/zero | tr '\0' '"' >"$quote_output"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$quote_output"
set +e
quote_actual="$("$REPO_ROOT/bin/organ" read fallback --json 2>&1)"
quote_rc=$?
set -e
if [[ "$quote_rc" -ne 0 ]]; then
  printf 'quote-only exact-limit read failed: exit %s\n%s\n' "$quote_rc" "$quote_actual" >&2
  ((failures += 1))
elif ! jq -e '
  .schema_version == "1" and .ok == true and .action == "read" and
  .target == "fallback" and .data.truncated == false
' >/dev/null <<<"$quote_actual"; then
  printf 'quote-only exact-limit read returned invalid public JSON\n' >&2
  ((failures += 1))
else
  jq -jr '.data.excerpt' <<<"$quote_actual" >"$quote_decoded"
  if ! cmp -s -- "$quote_output" "$quote_decoded"; then
    printf 'quote-only exact-limit excerpt did not round-trip exactly\n' >&2
    ((failures += 1))
  fi
fi

utf8_output="$TEST_TMP/utf8-pane.txt"
utf8_expected="$TEST_TMP/utf8-expected.txt"
utf8_decoded="$TEST_TMP/utf8-decoded.txt"
printf 'é' >"$utf8_output"
head -c 65535 /dev/zero | tr '\0' x >>"$utf8_output"
head -c 65535 /dev/zero | tr '\0' x >"$utf8_expected"
assert_eq "65537" "$(wc -c <"$utf8_output")"
export ORGAN_FAKE_TMUX_OUTPUT_FILE="$utf8_output"
set +e
utf8_actual="$("$REPO_ROOT/bin/organ" read fallback --json 2>&1)"
utf8_rc=$?
set -e
if [[ "$utf8_rc" -ne 0 ]]; then
  printf 'UTF-8 boundary read failed: exit %s\n%s\n' "$utf8_rc" "$utf8_actual" >&2
  ((failures += 1))
elif ! jq -e '.ok == true and .data.truncated == true' >/dev/null <<<"$utf8_actual"; then
  printf 'UTF-8 boundary read returned invalid public JSON\n' >&2
  ((failures += 1))
else
  jq -jr '.data.excerpt' <<<"$utf8_actual" >"$utf8_decoded"
  utf8_bytes="$(wc -c <"$utf8_decoded")"
  if (( utf8_bytes > 65536 )); then
    printf 'UTF-8 boundary excerpt exceeded 65536 bytes: %s\n' "$utf8_bytes" >&2
    ((failures += 1))
  fi
  if ! iconv -f UTF-8 -t UTF-8 "$utf8_decoded" >/dev/null; then
    printf 'UTF-8 boundary excerpt was not valid UTF-8\n' >&2
    ((failures += 1))
  fi
  if ! cmp -s -- "$utf8_expected" "$utf8_decoded"; then
    printf 'UTF-8 boundary excerpt did not preserve the complete trailing characters\n' >&2
    ((failures += 1))
  fi
fi

(( failures == 0 ))
