#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/helpers.sh"

installer="$REPO_ROOT/scripts/install-organoun.sh"
skill_source="$REPO_ROOT/skills/organoun"

[[ -x "$installer" ]] || {
  printf 'Organoun installer is missing or not executable: %s\n' "$installer" >&2
  exit 1
}
[[ -f "$skill_source/SKILL.md" ]] || {
  printf 'Organoun skill is missing: %s\n' "$skill_source/SKILL.md" >&2
  exit 1
}

assert_contains_line() {
  local expected="$1"
  local actual="$2"
  while IFS= read -r line; do
    [[ "$line" == "$expected" ]] && return 0
  done <<<"$actual"
  printf 'missing output line: %s\noutput:\n%s\n' "$expected" "$actual" >&2
  return 1
}

assert_skill_pattern() {
  local file="$1"
  local label="$2"
  local pattern="$3"
  if ! grep -Eq -- "$pattern" "$file"; then
    printf 'skill contract missing: %s (%s)\n' "$label" "$file" >&2
    return 1
  fi
}

assert_skill_contract() {
  local file="$1"
  local description

  description="$(awk '/^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$file")"

  for trigger in \
    'veja o Claude' \
    'pergunte ao Claude' \
    'despache' \
    'Organoun' \
    "\`organ\`"; do
    if [[ "$description" != *"$trigger"* ]]; then
      printf 'skill contract missing: natural-language trigger: %s (%s)\n' \
        "$trigger" "$file" >&2
      return 1
    fi
  done

  assert_skill_pattern "$file" 'first adopted reply requires explicit claim' \
    'primeira vez.*sessão .*adopted.*claim'
  assert_skill_pattern "$file" 'explicit claim precedes adopted reply' \
    'claim antes de responder'
  assert_skill_pattern "$file" 'adopted sessions can never be stopped' \
    'Nunca execute nem recomende .*organ stop.*sessão .*adopted'
  assert_skill_pattern "$file" 'unknown delivery is never replayed' \
    'Nunca repita .*entrega desconhecida'
  assert_skill_pattern "$file" 'unknown delivery is never retried automatically' \
    'nem manual nem automaticamente'
  assert_skill_pattern "$file" 'worker done report remains an allegation' \
    'done.*alegações'
  assert_skill_pattern "$file" 'only controller verify acceptance is accepted' \
    'organ verify JOB_ID.*state=accepted'
  assert_skill_pattern "$file" 'provider and model are never inferred' \
    'Nunca infira provider ou modelo'
  assert_skill_pattern "$file" 'failed verification is terminal for that job' \
    'blocked-verification.*job é terminal'
  assert_skill_pattern "$file" 'terminal verification is never rerun or redispatched' \
    'não reexecute .*verify.*nem redespache/reapresente esse job'
  assert_skill_pattern "$file" 'new work requires a separately scoped explicit intention' \
    'nova intenção explícita.*separadamente escopada.*trabalho novo'
  assert_skill_pattern "$file" 'installation is checked before project activation' \
    'test -x .*\.local/bin/organ.*antes de .*init'
  assert_skill_pattern "$file" 'installed skill is checked before project activation' \
    'test -r .*\.codex/skills/organoun/SKILL\.md.*antes de .*init'
  assert_skill_pattern "$file" 'tmux owner context is checked before deployment selection' \
    'tmux.*antes de (ler|inspecionar).*deployment'
  assert_skill_pattern "$file" 'missing tmux returns an explicit restart recipe' \
    'sair do Codex.*iniciar ou entrar.*tmux.*retomar'
  assert_skill_pattern "$file" 'new project returns onboarding to the visible operator' \
    'ONBOARD_REQUIRED.*operador.*organ.*onboard.*state=connected.*Pare'
  assert_skill_pattern "$file" 'configured project runs init' \
    'raiz Git canônica.*organ.*init --json'
  assert_skill_pattern "$file" 'initialized session returns the operator handoff sentence' \
    'Organoun ativo nesta sessão\. O que vamos criar hoje\?'
}

assert_operations_verification_contract() {
  local file="$1"

  assert_skill_pattern "$file" 'runbook marks failed verification terminal for that job' \
    'blocked-verification.*job é terminal'
  assert_skill_pattern "$file" 'runbook forbids verify rerun and redispatch' \
    'não reexecute .*verify.*nem redespache/reapresente esse job'
  assert_skill_pattern "$file" 'runbook returns separately scoped new work to the user' \
    'nova intenção explícita.*separadamente escopada.*trabalho novo'
}

if [[ "${1:-}" == --assert-skill-contract ]]; then
  [[ "$#" -eq 2 ]] || exit 64
  assert_skill_contract "$2"
  exit 0
fi
if [[ "${1:-}" == --assert-operations-verification-contract ]]; then
  [[ "$#" -eq 2 ]] || exit 64
  assert_operations_verification_contract "$2"
  exit 0
fi

new_test_env

assert_empty_dir() {
  local path="$1"
  if [[ -d "$path" ]] && find "$path" -mindepth 1 -print -quit | read -r _; then
    printf 'expected empty directory: %s\n' "$path" >&2
    return 1
  fi
}

assert_failed() {
  if "$@"; then
    printf 'command unexpectedly succeeded:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 1
  fi
}

assert_frontmatter_shape() {
  local file="$1"
  local result
  result="$(awk '
    NR == 1 { if ($0 != "---") exit 2; in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { closed=1; exit }
    in_frontmatter && /^[[:space:]]*($|#)/ { next }
    in_frontmatter {
      key=$0
      sub(/:.*/, "", key)
      if (key != "name" && key != "description") exit 3
      seen[key]++
    }
    END {
      if (!closed || seen["name"] != 1 || seen["description"] != 1) exit 4
      print "ok"
    }
  ' "$file")" || {
    printf 'invalid SKILL.md frontmatter shape: %s\n' "$file" >&2
    return 1
  }
  assert_eq ok "$result"
}

dry_prefix="$TEST_TMP/dry-prefix"
mkdir -p -- "$dry_prefix"
dry_output="$(HOME="$TEST_TMP/poison-home" \
  XDG_CONFIG_HOME="$TEST_TMP/poison-xdg" \
  CODEX_HOME="$TEST_TMP/poison-codex" \
  "$installer" --prefix "$dry_prefix")"
assert_contains_line "$dry_prefix/.local/share/organoun" "$dry_output"
assert_contains_line "$dry_prefix/.local/bin/organ" "$dry_output"
assert_contains_line "$dry_prefix/.codex/skills/organoun" "$dry_output"
[[ "$dry_output" != *"/.config/organoun/"* ]] || {
  printf 'dry run still advertises global Organoun configuration\n' >&2
  exit 1
}
[[ "$dry_output" != *"organ-remote"* ]] || {
  printf 'dry run still advertises a remote Organoun helper\n' >&2
  exit 1
}
assert_empty_dir "$dry_prefix"
assert_not_exists "$TEST_TMP/poison-home"
assert_not_exists "$TEST_TMP/poison-xdg"
assert_not_exists "$TEST_TMP/poison-codex"

# No --prefix is the real-home code path. HOME is hermetic here; dry-run must
# still be the default and must not honor XDG/Codex homes outside that root.
dry_home="$TEST_TMP/real-home-mode"
mkdir -p -- "$dry_home"
real_dry_output="$(HOME="$dry_home" \
  XDG_CONFIG_HOME="$TEST_TMP/external-xdg" \
  CODEX_HOME="$TEST_TMP/external-codex" \
  "$installer")"
assert_contains_line "$dry_home/.local/share/organoun" "$real_dry_output"
assert_contains_line "$dry_home/.codex/skills/organoun" "$real_dry_output"
assert_empty_dir "$dry_home"
assert_not_exists "$TEST_TMP/external-xdg"
assert_not_exists "$TEST_TMP/external-codex"

prefix="$TEST_TMP/prefix"
outside="$TEST_TMP/outside"
mkdir -p -- "$prefix/.codex" "$outside"
printf 'operator-owned global instructions\n' >"$prefix/.codex/AGENTS.md"
cp -- "$prefix/.codex/AGENTS.md" "$TEST_TMP/AGENTS.before"

HOME="$TEST_TMP/poison-home" \
  XDG_CONFIG_HOME="$outside/config" \
  XDG_DATA_HOME="$outside/data" \
  XDG_STATE_HOME="$outside/state" \
  CODEX_HOME="$outside/codex" \
  "$installer" --prefix "$prefix" --apply

share="$prefix/.local/share/organoun"
cli_link="$prefix/.local/bin/organ"
installed_skill="$prefix/.codex/skills/organoun"

[[ -d "$share" && ! -L "$share" ]] || { printf 'share tree not published as a directory\n' >&2; exit 1; }
[[ -L "$cli_link" ]] || { printf 'CLI is not a symlink\n' >&2; exit 1; }
assert_eq '../share/organoun/bin/organ' "$(readlink -- "$cli_link")"
assert_eq "$share/bin/organ" "$(readlink -f -- "$cli_link")"
assert_mode 755 "$share/bin/organ"
assert_mode 755 "$share/probes/claude-composer-empty"
assert_mode 755 "$installed_skill"
assert_mode 644 "$installed_skill/SKILL.md"
cmp -s -- "$REPO_ROOT/bin/organ" "$share/bin/organ"
cmp -s -- "$REPO_ROOT/probes/claude-composer-empty" "$share/probes/claude-composer-empty"
cmp -s -- "$REPO_ROOT/config/deployment.example.json" "$share/config/deployment.example.json"
diff -ru -- "$skill_source" "$installed_skill"
cmp -s -- "$skill_source/SKILL.md" "$installed_skill/SKILL.md"
cmp -s -- "$skill_source/agents/openai.yaml" "$installed_skill/agents/openai.yaml"
assert_skill_contract "$skill_source/SKILL.md"
assert_skill_contract "$installed_skill/SKILL.md"
cmp -s -- "$TEST_TMP/AGENTS.before" "$prefix/.codex/AGENTS.md"
assert_empty_dir "$outside"
assert_not_exists "$share/remote"
assert_not_exists "$prefix/.local/libexec/organoun/organ-remote"

while IFS= read -r source_file; do
  relative="${source_file#"$REPO_ROOT/"}"
  cmp -s -- "$source_file" "$share/$relative" || {
    printf 'installed runtime file differs from source: %s\n' "$relative" >&2
    exit 1
  }
done < <(find "$REPO_ROOT/lib/organ" -type f -name '*.sh' -print)

probe_path="$(HOME="$prefix" bash -c '
  ORGAN_ROOT="$1"
  source "$1/lib/organ/outsourcerer.sh"
  organ_osrc_composer_probe
' _ "$share")"
assert_eq "$share/probes/claude-composer-empty" "$probe_path"
[[ "$probe_path" == /* && -x "$probe_path" ]] || {
  printf 'installed composer probe is not absolute and executable: %s\n' "$probe_path" >&2
  exit 1
}

assert_frontmatter_shape "$skill_source/SKILL.md"
assert_eq 'name: organoun' "$(awk '/^name:/{print; exit}' "$skill_source/SKILL.md")"
case "$(awk '/^description:/{sub(/^description:[[:space:]]*/, ""); print; exit}' "$skill_source/SKILL.md")" in
  'Use when'*) ;;
  *) printf 'skill description must start with Use when\n' >&2; exit 1 ;;
esac
assert_eq 2 "$(find "$skill_source" -type f | wc -l)"

# Re-applying an identical runtime never creates or mutates global config.
HOME="$TEST_TMP/poison-home" "$installer" --prefix "$prefix" --apply
cmp -s -- "$TEST_TMP/AGENTS.before" "$prefix/.codex/AGENTS.md"
assert_not_exists "$prefix/.config/organoun/targets.json"

# A pre-existing non-owned leaf blocks the whole transaction. Nothing else is
# published before all destinations pass preflight.
conflict_prefix="$TEST_TMP/conflict-prefix"
mkdir -p -- "$conflict_prefix/.local/bin"
printf 'operator file\n' >"$conflict_prefix/.local/bin/organ"
assert_failed "$installer" --prefix "$conflict_prefix" --apply
assert_eq 'operator file' "$(<"$conflict_prefix/.local/bin/organ")"
assert_not_exists "$conflict_prefix/.local/share/organoun"
assert_not_exists "$conflict_prefix/.config/organoun/targets.json"
assert_not_exists "$conflict_prefix/.codex/skills/organoun"

# A symlinked ancestor must not redirect any write beyond the authorized root.
symlink_prefix="$TEST_TMP/symlink-prefix"
symlink_outside="$TEST_TMP/symlink-outside"
mkdir -p -- "$symlink_prefix" "$symlink_outside"
ln -s -- "$symlink_outside" "$symlink_prefix/.local"
assert_failed "$installer" --prefix "$symlink_prefix" --apply
assert_empty_dir "$symlink_outside"
assert_not_exists "$symlink_prefix/.config"
assert_not_exists "$symlink_prefix/.codex"

# Syntax validation happens against a private staged tree. A failed validation
# leaves no published share, links, config, or skill.
bad_source="$TEST_TMP/bad-source"
mkdir -p -- "$bad_source"
cp -a -- "$REPO_ROOT/bin" "$REPO_ROOT/config" "$REPO_ROOT/lib" \
  "$REPO_ROOT/probes" "$REPO_ROOT/scripts" "$REPO_ROOT/skills" \
  "$REPO_ROOT/vendor" "$bad_source/"
printf '\nif syntax is broken\n' >>"$bad_source/lib/organ/common.sh"
bad_prefix="$TEST_TMP/bad-prefix"
mkdir -p -- "$bad_prefix"
assert_failed "$bad_source/scripts/install-organoun.sh" --prefix "$bad_prefix" --apply
assert_empty_dir "$bad_prefix"

# An interrupt while validating the private stage must return nonzero and leave
# no partial tree. The fake bash signals only the installer's `bash -n` call.
interrupt_bin="$TEST_TMP/interrupt-bin"
interrupt_prefix="$TEST_TMP/interrupt-prefix"
mkdir -p -- "$interrupt_bin" "$interrupt_prefix"
ln -s -- "$REPO_ROOT/tests/fixtures/fake-bash-interrupt.sh" "$interrupt_bin/bash"
set +e
timeout 5s env PATH="$interrupt_bin:$PATH" \
  "$installer" --prefix "$interrupt_prefix" --apply
interrupt_rc=$?
set -e
if [[ "$interrupt_rc" -eq 0 ]]; then
  printf 'interrupted install reported success\n' >&2
  exit 1
fi
if [[ "$interrupt_rc" -eq 124 ]]; then
  printf 'interrupted install did not exit before timeout\n' >&2
  exit 1
fi
assert_empty_dir "$interrupt_prefix"

# A failure after share/config/skill publication begins must roll every leaf
# back. Failing `ln` reaches this path only when it creates the public links.
failure_bin="$TEST_TMP/failure-bin"
failure_prefix="$TEST_TMP/failure-prefix"
mkdir -p -- "$failure_bin" "$failure_prefix/.config/organoun"
chmod 750 -- "$failure_prefix/.config/organoun"
failure_config_mode="$(stat -c '%a' -- "$failure_prefix/.config/organoun")"
ln -s -- "$REPO_ROOT/tests/fixtures/fake-ln-fail.sh" "$failure_bin/ln"
assert_failed env PATH="$failure_bin:$PATH" "$installer" --prefix "$failure_prefix" --apply
assert_mode "$failure_config_mode" "$failure_prefix/.config/organoun"
assert_not_exists "$failure_prefix/.local/share/organoun"
assert_not_exists "$failure_prefix/.local/bin/organ"
assert_not_exists "$failure_prefix/.local/libexec/organoun/organ-remote"
assert_not_exists "$failure_prefix/.config/organoun/targets.json"
assert_not_exists "$failure_prefix/.codex/skills/organoun"

# Rollback documentation names only Organoun-owned leaves, so following it
# cannot remove the user's broader Codex, config, local, Claude, or tmux trees.
operations="$REPO_ROOT/docs/operations.md"
[[ -f "$operations" ]] || { printf 'operations runbook is missing\n' >&2; exit 1; }
assert_operations_verification_contract "$operations"
for owned_path in \
  '.local/bin/organ' \
  '.local/share/organoun' \
  '.codex/skills/organoun'; do
  awk -v path="$owned_path" 'index($0, path) { found=1 } END { exit !found }' "$operations" || {
    printf 'rollback instructions omit owned path: %s\n' "$owned_path" >&2
    exit 1
  }
done
if awk '/^[[:space:]]*rm[[:space:]]+-f[[:space:]]+--[[:space:]]+.*\.config\/organoun\/targets\.json(["[:space:]]|$)/ { found=1 } END { exit !found }' "$operations"; then
  printf 'rollback instructions unconditionally remove operator configuration\n' >&2
  exit 1
fi
if awk '/rm[[:space:]]+-rf[[:space:]]+.*(\.local|\.config|\.codex)(["[:space:]]|$)/ { found=1 } END { exit !found }' "$operations"; then
  printf 'rollback instructions contain a broad destructive removal\n' >&2
  exit 1
fi

printf 'test_install_skill.sh: PASS\n'
