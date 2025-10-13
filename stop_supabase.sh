#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/.cache/supabase/docker/docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-archon_supabase_local}"
ACTION="stop"

usage() {
  cat <<'EOF'
Usage: ./supabase-local/stop_supabase.sh [--destroy]

Options:
  --destroy   Fully tear down the Supabase stack and remove volumes (data loss).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --destroy)
      ACTION="destroy"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to stop Supabase." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "No Supabase environment found at $ENV_FILE. Nothing to do." >&2
  exit 0
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Supabase compose file not found at $COMPOSE_FILE." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required." >&2
  exit 1
fi

compose_cmd() {
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    "$@"
}

if [[ "$ACTION" == "destroy" ]]; then
  echo "Stopping and removing Supabase containers, networks, and volumes..."
  compose_cmd down -v
  echo "Supabase stack destroyed."
else
  echo "Stopping Supabase containers (data preserved)..."
  compose_cmd stop
  echo "Supabase containers stopped."
fi
