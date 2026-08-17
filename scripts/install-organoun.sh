#!/usr/bin/env bash
set -euo pipefail

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
repo_root="$(cd -- "$(dirname -- "$script_path")/.." && pwd -P)"
prefix=""
prefix_seen=false
apply=false
apply_seen=false
reinstall=false
reinstall_seen=false

print_help() {
  cat <<EOF
Usage: ${0##*/} [--prefix HOME_ROOT] [--apply] [--reinstall]

Install the Organoun CLI, runtime, and Codex skill for one local user.

Default (without --apply):
  Print the three exact destinations below and make no filesystem changes.

With --apply:
  Validate the source and every managed destination, stage and syntax-check the
  runtime, then create only these missing Organoun-owned entries:
    HOME_ROOT/.local/share/organoun   runtime, probes, config example, and vendor pin
    HOME_ROOT/.local/bin/organ        relative symlink to the installed CLI
    HOME_ROOT/.codex/skills/organoun  installed Codex skill

  An identical existing installation is accepted. A conflicting or unsafe
  destination is refused. The source checkout and project repositories are not
  modified, and no project onboarding is performed.

With --apply --reinstall:
  Require the existing runtime, CLI link, and skill to match the Organoun-owned
  destination topology. Stage and validate the pulled source first, replace only
  the installed runtime and skill with same-filesystem renames, keep the CLI
  link, and restore the previous installation if publication is interrupted.
  Project deployments and the source checkout remain untouched.

After a successful apply (not performed automatically):
  export PATH="\$HOME/.local/bin:\$PATH"
      Makes the installed CLI resolvable in the current shell and its children
      only. It does not edit a shell startup file and ends with that shell.
  command -v organ
      Prints the exact executable the current shell will use. Stop if it does
      not resolve to HOME_ROOT/.local/bin/organ.

Options:
  --prefix HOME_ROOT  Use this existing canonical directory as the home root.
                      Default: the current HOME.
  --apply             Perform the changes described above. Without this flag,
                      the command is a dry run.
  --reinstall         With --apply, replace a prior Organoun installation after
                      validating its three exact managed destinations.
  --help              Print this explanation and exit without changes.
EOF
}

usage() {
  print_help >&2
  exit 64
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ "$prefix_seen" == false && "$#" -ge 2 ]] || usage
      prefix="$2"
      prefix_seen=true
      shift 2
      ;;
    --apply)
      [[ "$apply_seen" == false ]] || usage
      apply=true
      apply_seen=true
      shift
      ;;
    --reinstall)
      [[ "$reinstall_seen" == false ]] || usage
      reinstall=true
      reinstall_seen=true
      shift
      ;;
    --help)
      print_help
      exit 0
      ;;
    *) usage ;;
  esac
done

[[ "$reinstall" == false || "$apply" == true ]] || {
  printf '%s\n' '--reinstall requires --apply' >&2
  usage
}

home_root="${prefix:-${HOME:-}}"
[[ -n "$home_root" && "$home_root" == /* && "$home_root" != / ]] || {
  printf 'HOME root must be an absolute directory other than /\n' >&2
  exit 64
}
[[ ! "$home_root" =~ [[:cntrl:]] ]] || {
  printf 'HOME root contains control characters\n' >&2
  exit 64
}
home_root="${home_root%/}"
[[ -d "$home_root" && ! -L "$home_root" ]] || {
  printf 'HOME root must exist and must not be a symlink: %s\n' "$home_root" >&2
  exit 64
}
canonical_root="$(readlink -f -- "$home_root")"
[[ "$canonical_root" == "$home_root" ]] || {
  printf 'HOME root must be canonical and have no symlink ancestors: %s\n' "$home_root" >&2
  exit 64
}

share="$home_root/.local/share/organoun"
cli_link="$home_root/.local/bin/organ"
skill="$home_root/.codex/skills/organoun"

print_destinations() {
  printf '%s\n' "$share" "$cli_link" "$skill"
}

if [[ "$apply" != true ]]; then
  print_destinations
  exit 0
fi

for source_path in \
  "$repo_root/bin/organ" \
  "$repo_root/lib/organ" \
  "$repo_root/probes/claude-composer-empty" \
  "$repo_root/scripts/onboard-organoun.sh" \
  "$repo_root/vendor/outsourcerer/outsourcerer.sh" \
  "$repo_root/vendor/outsourcerer/LICENSE" \
  "$repo_root/vendor/outsourcerer.lock.json" \
  "$repo_root/config/deployment.example.json" \
  "$repo_root/skills/organoun/SKILL.md" \
  "$repo_root/skills/organoun/agents/openai.yaml"; do
  [[ -e "$source_path" && ! -L "$source_path" ]] || {
    printf 'required source is missing or unsafe: %s\n' "$source_path" >&2
    exit 64
  }
done

assert_safe_existing_directory() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -d "$path" && ! -L "$path" ]] || {
      printf 'refusing unsafe install ancestor: %s\n' "$path" >&2
      return 64
    }
  fi
}

assert_safe_ancestors() {
  local path
  for path in \
    "$home_root/.local" \
    "$home_root/.local/share" \
    "$home_root/.local/bin" \
    "$home_root/.codex" \
    "$home_root/.codex/skills"; do
    assert_safe_existing_directory "$path" || return 64
  done
}

assert_relative_link_or_absent() {
  local path="$1"
  local expected="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -L "$path" && "$(readlink -- "$path")" == "$expected" ]] || {
      printf 'refusing non-owned install destination: %s\n' "$path" >&2
      return 64
    }
  fi
}

runtime_matches_source() {
  [[ -d "$share" && ! -L "$share" ]] || return 1
  diff -qr -- "$repo_root/bin" "$share/bin" >/dev/null 2>&1 || return 1
  diff -qr -- "$repo_root/lib" "$share/lib" >/dev/null 2>&1 || return 1
  diff -qr -- "$repo_root/probes" "$share/probes" >/dev/null 2>&1 || return 1
  diff -qr -- "$repo_root/config" "$share/config" >/dev/null 2>&1 || return 1
  diff -qr -- "$repo_root/vendor" "$share/vendor" >/dev/null 2>&1 || return 1
  cmp -s -- "$repo_root/scripts/onboard-organoun.sh" "$share/scripts/onboard-organoun.sh" || return 1
}

skill_matches_source() {
  [[ -d "$skill" && ! -L "$skill" ]] || return 1
  diff -qr -- "$repo_root/skills/organoun" "$skill" >/dev/null 2>&1
}

assert_reinstallable() {
  [[ -d "$share" && ! -L "$share" ]] || {
    printf 'reinstall requires the existing Organoun runtime: %s\n' "$share" >&2
    return 64
  }
  [[ -d "$skill" && ! -L "$skill" ]] || {
    printf 'reinstall requires the existing Organoun skill: %s\n' "$skill" >&2
    return 64
  }
  [[ -L "$cli_link" && "$(readlink -- "$cli_link")" == '../share/organoun/bin/organ' ]] || {
    printf 'reinstall requires the exact Organoun CLI link: %s\n' "$cli_link" >&2
    return 64
  }
  [[ -f "$share/bin/organ" && ! -L "$share/bin/organ" && \
     -f "$skill/SKILL.md" && ! -L "$skill/SKILL.md" ]] || {
    printf 'reinstall refused an incomplete Organoun installation\n' >&2
    return 64
  }
}

preflight() {
  assert_safe_ancestors || return 64
  assert_relative_link_or_absent "$cli_link" '../share/organoun/bin/organ' || return 64
  if [[ "$reinstall" == true ]]; then
    assert_reinstallable || return 64
    return 0
  fi
  if [[ -e "$share" || -L "$share" ]]; then
    runtime_matches_source || {
      printf 'refusing existing share tree with different managed files: %s\n' "$share" >&2
      return 64
    }
  fi
  if [[ -e "$skill" || -L "$skill" ]]; then
    skill_matches_source || {
      printf 'refusing existing skill with different files: %s\n' "$skill" >&2
      return 64
    }
  fi
}

preflight

umask 077
lock_dir="$home_root/.organoun-install.lock"
if ! mkdir -- "$lock_dir"; then
  printf 'another Organoun installation is active: %s\n' "$lock_dir" >&2
  exit 75
fi

stage=""
share_created=false
skill_created=false
cli_created=false
share_backup=""
skill_backup=""
complete=false

cleanup() {
  set +e
  if [[ "$complete" != true ]]; then
    [[ "$cli_created" == false ]] || rm -f -- "$cli_link"
    [[ "$skill_created" == false ]] || rm -rf -- "$skill"
    [[ "$share_created" == false ]] || rm -rf -- "$share"
    if [[ -n "$skill_backup" && -d "$skill_backup" && ! -e "$skill" && ! -L "$skill" ]]; then
      mv -T -- "$skill_backup" "$skill"
    fi
    if [[ -n "$share_backup" && -d "$share_backup" && ! -e "$share" && ! -L "$share" ]]; then
      mv -T -- "$share_backup" "$share"
    fi
  fi
  [[ -z "$stage" ]] || rm -rf -- "$stage"
  rmdir -- "$lock_dir" 2>/dev/null || true
}

finish() {
  local rc=$?
  trap - EXIT HUP INT TERM
  cleanup
  exit "$rc"
}

trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# Recheck after acquiring the root-local lock so no destination decision is
# based only on the earlier, unlocked observation.
preflight

stage="$(mktemp -d -- "$home_root/.organoun-stage.XXXXXX")"
chmod 700 -- "$stage"
mkdir -- "$stage/share" "$stage/skill"
cp -a -- "$repo_root/bin" "$repo_root/config" "$repo_root/lib" \
  "$repo_root/probes" "$repo_root/vendor" "$stage/share/"
mkdir -- "$stage/share/scripts"
cp -a -- "$repo_root/scripts/onboard-organoun.sh" "$stage/share/scripts/"
cp -a -- "$repo_root/skills/organoun/." "$stage/skill/"

find "$stage/share" "$stage/skill" -type d -exec chmod 755 -- {} +
find "$stage/share" "$stage/skill" -type f -exec chmod 644 -- {} +
chmod 755 -- \
  "$stage/share/bin/organ" \
  "$stage/share/probes/claude-composer-empty" \
  "$stage/share/scripts/onboard-organoun.sh" \
  "$stage/share/vendor/outsourcerer/outsourcerer.sh"

while IFS= read -r -d '' shell_file; do
  bash -n -- "$shell_file"
done < <(find "$stage/share/bin" "$stage/share/lib" "$stage/share/probes" \
  "$stage/share/scripts" -type f -print0)
bash -n -- "$stage/share/vendor/outsourcerer/outsourcerer.sh"

ensure_directory() {
  local path="$1"
  local mode="$2"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    mkdir -m "$mode" -- "$path"
  fi
  [[ -d "$path" && ! -L "$path" ]] || return 64
}

ensure_directory "$home_root/.local" 755
ensure_directory "$home_root/.local/share" 755
ensure_directory "$home_root/.local/bin" 755
ensure_directory "$home_root/.codex" 755
ensure_directory "$home_root/.codex/skills" 755

if [[ "$reinstall" == true ]]; then
  share_backup="$stage/previous-share"
  skill_backup="$stage/previous-skill"
  mv -T -- "$share" "$share_backup"
  mv -T -- "$skill" "$skill_backup"
  mv -T -- "$stage/share" "$share"
  share_created=true
  mv -T -- "$stage/skill" "$skill"
  skill_created=true
elif [[ ! -e "$share" && ! -L "$share" ]]; then
  mv -T -- "$stage/share" "$share"
  share_created=true
fi
if [[ "$reinstall" != true && ! -e "$skill" && ! -L "$skill" ]]; then
  mv -T -- "$stage/skill" "$skill"
  skill_created=true
fi

if [[ ! -e "$cli_link" && ! -L "$cli_link" ]]; then
  cli_tmp="$home_root/.local/bin/.organ.install.$$"
  [[ ! -e "$cli_tmp" && ! -L "$cli_tmp" ]] || exit 64
  ln -s -- '../share/organoun/bin/organ' "$cli_tmp"
  mv -T -- "$cli_tmp" "$cli_link"
  cli_created=true
fi
chmod 755 -- "$share/bin/organ" "$share/probes/claude-composer-empty" \
  "$share/scripts/onboard-organoun.sh" \
  "$share/vendor/outsourcerer/outsourcerer.sh"

complete=true
rm -rf -- "$stage"
stage=""
rmdir -- "$lock_dir"
trap - EXIT HUP INT TERM
