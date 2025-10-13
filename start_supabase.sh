#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

PULL=true
RUN_INIT=true

usage() {
  cat <<'EOF'
Usage: ./supabase-local/start_supabase.sh [--no-pull] [--skip-init]

Options:
  --no-pull   Skip docker compose pull before starting containers.
  --skip-init Skip running init_db.sh (assume database already initialized).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --no-pull)
      PULL=false
      shift
      ;;
    --skip-init)
      RUN_INIT=false
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd docker
require_cmd timeout
ensure_compose_available
ensure_repo
ensure_env

if [[ "$RUN_INIT" == true ]]; then
  "$SCRIPT_DIR/init_db.sh" --skip-setup
else
  echo "Skipping database initialization (requested)."
fi

if [[ "$PULL" == true ]]; then
  echo "Pulling Supabase images (timeout ${PULL_TIMEOUT_SECONDS}s)..."
  timeout "${PULL_TIMEOUT_SECONDS}s" env COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    pull >/dev/null
fi

echo "Starting Supabase services..."
timeout "${UP_TIMEOUT_SECONDS}s" env COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose \
  --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" \
  up -d >/dev/null

write_generated_env

KONG_HTTP_PORT="$(read_env_var "KONG_HTTP_PORT")"
KONG_HTTP_PORT="${KONG_HTTP_PORT:-8000}"

cat <<EOF

Supabase services are running.

Dashboard: http://127.0.0.1:${KONG_HTTP_PORT}
Generated environment: $GENERATED_ENV_FILE
EOF
