#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODE="archon"

usage() {
  cat <<'EOF'
Usage: ./supabase-local/restore.sh [--all] <dump-file>

Options:
  --all         Restore a full database dump (may emit Supabase privilege warnings).

The script stops running containers, starts the database, streams the dump via pg_restore,
then restarts the remaining Supabase services.
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
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

DUMP_FILE="$1"

if [[ ! -f "$DUMP_FILE" ]]; then
  echo "Dump file not found: $DUMP_FILE" >&2
  exit 1
fi

require_cmd docker
require_cmd timeout
ensure_compose_available
ensure_repo
ensure_env

echo "Stopping running Supabase containers..."
"$SCRIPT_DIR/stop_supabase.sh" || true

echo "Starting database container..."
compose_cmd up -d db >/dev/null

echo "Waiting for database to accept connections..."
wait_for_postgres 60

restore_cmd='PGPASSWORD="$POSTGRES_PASSWORD" pg_restore --clean --if-exists --no-owner --no-privileges --dbname=postgres --host=localhost --port=5432 --username=postgres'

echo "Restoring dump ($MODE mode) from $DUMP_FILE ..."
set +e
cat "$DUMP_FILE" | compose_cmd exec -T db sh -c "$restore_cmd"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  if [[ "$MODE" == "full" ]]; then
    echo "pg_restore completed with warnings (expected for Supabase-managed objects). Review output above if needed." >&2
  else
    echo "pg_restore failed (archon-only mode). Aborting." >&2
    exit $status
  fi
fi

echo "Restarting Supabase services..."
"$SCRIPT_DIR/start_supabase.sh"

echo "Restore complete."
