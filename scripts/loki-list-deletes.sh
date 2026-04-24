#!/usr/bin/env sh
set -eu

# List pending and processed log delete requests for the default tenant.

LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"

curl -fsS "${LOKI_URL}/loki/api/v1/delete"
echo
