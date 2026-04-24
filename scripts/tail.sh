#!/usr/bin/env sh
set -eu
# Usage: ./scripts/tail.sh [service_name ...]
# Default: tail all stack logs
cd "$(dirname "$0")/.."
if [ "$#" -eq 0 ]; then
  docker compose logs -f --tail=100
else
  docker compose logs -f --tail=100 "$@"
fi
