#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

SKIP_SETUP=false

usage() {
  cat <<'EOF'
Usage: ./supabase-local/init_db.sh [--skip-setup]

Options:
  --skip-setup   Assume repo and .env already exist (skip cloning / env generation).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --skip-setup)
      SKIP_SETUP=true
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

if [[ "$SKIP_SETUP" == false ]]; then
  ensure_repo
  ensure_env
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Supabase compose file not found. Run ./supabase-local/setup_supabase.sh first." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Supabase .env missing. Run ./supabase-local/setup_supabase.sh first." >&2
  exit 1
fi

if [[ "$SKIP_SETUP" == true ]]; then
  echo "Using existing Supabase clone and environment."
fi

echo "Pulling database images (timeout ${PULL_TIMEOUT_SECONDS}s)..."
timeout "${PULL_TIMEOUT_SECONDS}s" env COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose   --env-file "$ENV_FILE"   -f "$COMPOSE_FILE"   pull db vector >/dev/null

echo "Starting database container..."
timeout "${UP_TIMEOUT_SECONDS}s" env COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose   --env-file "$ENV_FILE"   -f "$COMPOSE_FILE"   up -d db >/dev/null

echo "Waiting for Postgres to become ready..."
wait_for_postgres

apply_archon_schema
write_generated_env

echo "Database initialized with Archon schema."
