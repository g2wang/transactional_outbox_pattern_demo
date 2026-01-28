#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE="docker compose"

APP_URL="${APP_URL:-http://localhost:8080}"
CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-outboxdb}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-120}"

log() {
  printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd docker
require_cmd curl
require_cmd sed
require_cmd tail
require_cmd tr

log "Starting stack via docker compose..."
$COMPOSE up -d --build

log "Waiting for Postgres to accept connections..."
deadline=$((SECONDS + MAX_WAIT_SECONDS))
until $COMPOSE exec -T "$POSTGRES_SERVICE" pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for Postgres" >&2
    exit 1
  fi
  sleep 2
done

log "Waiting for app to be reachable at $APP_URL ..."
deadline=$((SECONDS + MAX_WAIT_SECONDS))
until curl -sS -o /dev/null "$APP_URL/" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for app at $APP_URL" >&2
    $COMPOSE ps >&2 || true
    exit 1
  fi
  sleep 2
done

log "Creating an order via POST $APP_URL/orders ..."
resp="$(
  curl -sS -w '\n%{http_code}' -X POST "$APP_URL/orders" \
    -H "Content-Type: application/json" \
    -d '{"customerId":"test-customer","amount":12.34}'
)"
body="$(echo "$resp" | sed '$d')"
code="$(echo "$resp" | tail -n 1)"

if [[ "$code" != "200" ]]; then
  echo "Expected HTTP 200, got $code" >&2
  echo "Response body:" >&2
  echo "$body" >&2
  exit 1
fi

log "Order created. Response:"
echo "$body"

log "Verifying an outbox row exists in Postgres..."
count="$(
  $COMPOSE exec -T "$POSTGRES_SERVICE" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c \
    "select count(*) from outbox;"
)"
count="$(echo "$count" | tr -d '[:space:]')"

if [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]]; then
  echo "Failed to read outbox count from Postgres. Got: '$count'" >&2
  exit 1
fi

if (( count < 1 )); then
  echo "Expected outbox count >= 1, got $count" >&2
  exit 1
fi

log "OK: outbox has $count row(s). Transactional outbox write verified."

log "Optional: Debezium connector can be registered at $CONNECT_URL (see connector.json)."

