#!/usr/bin/env bash
set -euo pipefail

printf '%q\0' "$@" >>"${ORGAN_FORBIDDEN_SSH_LOG:?}"
printf 'forbidden hidden SSH invocation\n' >&2
exit 70
