#!/usr/bin/env sh
set -eu

# Deletes logs for a given LogQL stream selector over a time window.
#
# Example:
#   ./scripts/loki-delete-range.sh '{compose_project="ruzivoflow",service="api"}' 2026-04-01T00:00:00Z 2026-04-10T00:00:00Z
#
# Notes:
# - Deletion is processed by Loki compactor after its cancel period (default 24h).
# - This requires Loki compactor retention_enabled and deletion_mode enabled.

LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 '<logql_selector>' <start_rfc3339> <end_rfc3339>" >&2
  exit 2
fi

SELECTOR="$1"
START="$2"
END="$3"

ENC_QUERY="$(python -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe='{}=\",~|()[]:+-*/ '))" "${SELECTOR}")"
ENC_START="$(python -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "${START}")"
ENC_END="$(python -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "${END}")"

# Loki expects query params (not form body) for this endpoint.
curl -g -fsS -X POST \
  "${LOKI_URL}/loki/api/v1/delete?query=${ENC_QUERY}&start=${ENC_START}&end=${ENC_END}"

echo "Delete request submitted. (Default cancel period is 24h.)"

