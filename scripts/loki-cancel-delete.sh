#!/usr/bin/env sh
set -eu

# Cancel a delete request before the compactor processes it (see Loki delete_request_cancel_period).

LOKI_URL="${LOKI_URL:-http://127.0.0.1:3100}"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <request_id> [force=true]" >&2
  exit 2
fi

REQ="$1"
FORCE="${2:-}"

URL="${LOKI_URL}/loki/api/v1/delete?request_id=${REQ}"
if [ "$FORCE" = "true" ] || [ "$FORCE" = "force=true" ]; then
  URL="${URL}&force=true"
fi

curl -g -fsS -X DELETE "$URL"
echo "Cancelled (or request accepted for cancel)."
