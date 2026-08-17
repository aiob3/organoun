#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == -n ]]; then
  kill -TERM "$PPID"
  exit 0
fi
exec /bin/bash "$@"
