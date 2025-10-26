#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage: ./supabase-local/bridge_networks.sh

Connects the Supabase gateway container to the shared Archon Docker network.
Run this after both stacks are up if you are on Linux and need cross-compose access.

Environment:
  SUPABASE_SHARED_NETWORK   Target network name (default: archon_app-network)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$SHARED_NETWORK" ]]; then
  echo "Shared network bridge is disabled (SUPABASE_SHARED_NETWORK is empty). Nothing to do."
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to bridge networks." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not accessible. Ensure your user has permission to run docker commands." >&2
  exit 1
fi

SUPABASE_NETWORK="${COMPOSE_PROJECT_NAME}_default"

if ! docker network inspect "$SUPABASE_NETWORK" >/dev/null 2>&1; then
  echo "Supabase network $SUPABASE_NETWORK was not found. Start the Supabase stack first." >&2
  exit 1
fi

if ! docker network inspect "$SHARED_NETWORK" >/dev/null 2>&1; then
  echo "Target network $SHARED_NETWORK was not found. Start the Archon Docker Compose stack first." >&2
  exit 1
fi

containers=("supabase-kong")

for container in "${containers[@]}"; do
  if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
    connect_shared_network "$container" "$SUPABASE_BRIDGE_ALIAS"
  else
    echo "Container $container is not running. Start Supabase and retry." >&2
    exit 1
  fi
done

echo "Supabase gateway is now connected to $SHARED_NETWORK."
