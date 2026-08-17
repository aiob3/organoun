#!/usr/bin/env bash

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

new_test_env() {
  TEST_TMP="$(mktemp -d)"
  export TEST_TMP
  export HOME="$TEST_TMP/home"
  export XDG_CONFIG_HOME="$TEST_TMP/config"
  export XDG_STATE_HOME="$TEST_TMP/state"
  mkdir -p -- "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
  trap 'rm -rf -- "$TEST_TMP"' EXIT
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  if [[ "$expected" != "$actual" ]]; then
    printf 'assert_eq failed: expected %s, got %s\n' "$expected" "$actual" >&2
    return 1
  fi
}

assert_mode() {
  local expected="$1"
  local path="$2"
  local actual
  actual="$(stat -c '%a' -- "$path")"
  assert_eq "$expected" "$actual"
}

assert_not_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    printf 'assert_not_exists failed: %s exists\n' "$path" >&2
    return 1
  fi
}

assert_jq() {
  local json="$1"
  local expression="$2"
  if ! jq -e "$expression" >/dev/null <<<"$json"; then
    printf 'assert_jq failed: %s\nJSON: %s\n' "$expression" "$json" >&2
    return 1
  fi
}
