#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

FRESH=false

usage() {
  cat <<'EOF'
Usage: ./supabase-local/setup_supabase.sh [--fresh]

Options:
  --fresh   Remove cached Supabase clone, local volumes, and regenerate .env.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --fresh)
      FRESH=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd git
require_cmd docker
require_cmd openssl
require_cmd python3
require_cmd timeout
ensure_compose_available

if [[ "$FRESH" == true ]]; then
  echo "Fresh setup requested. Tearing down existing resources..."
  if [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" ]]; then
    timeout 120s env COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose \
      --env-file "$ENV_FILE" \
      -f "$COMPOSE_FILE" \
      down -v || true
  fi
  rm -f "$ENV_FILE"
  rm -rf "$GENERATED_ENV_DIR"
  rm -rf "$SUPABASE_SRC"
  rm -rf "$CACHE_DIR"
fi

ensure_repo
ensure_env
mkdir -p "$GENERATED_ENV_DIR"

echo "Setup complete. Supabase sources and environment are ready."
