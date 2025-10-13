#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODE="archon"
OUTPUT=""

usage() {
  cat <<'EOF'
Usage: ./supabase-local/backup.sh [--all] [--output PATH]

Options:
  --all           Back up the entire database (may emit Supabase privilege warnings on restore).
  --output PATH   Write the dump to PATH (defaults to supabase-local/backup/<timestamp>.{archon,full}.pgsql).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --all)
      MODE="full"
      shift
      ;;
    --output)
      shift
      OUTPUT="${1:-}"
      shift || true
      ;;
    *)
      echo "Unknown argument: $1" >&2
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

mkdir -p "$SCRIPT_DIR/backup"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
extension="$([[ $MODE == "full" ]] && echo "full" || echo "archon")"

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$SCRIPT_DIR/backup/${timestamp}.${extension}.pgsql"
fi

echo "Ensuring database container is running..."
compose_cmd up -d db >/dev/null

if [[ "$MODE" == "full" ]]; then
  dump_cmd='PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=c --no-owner --no-privileges postgres://postgres:$POSTGRES_PASSWORD@127.0.0.1:5432/postgres'
else
  dump_cmd='PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=c --no-owner --no-privileges --table="archon_*" postgres://postgres:$POSTGRES_PASSWORD@127.0.0.1:5432/postgres'
fi

echo "Creating ${MODE} backup at $OUTPUT ..."
compose_cmd exec -T db sh -c "$dump_cmd" >"$OUTPUT"

echo "Backup complete: $OUTPUT"
