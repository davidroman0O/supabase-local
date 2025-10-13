#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/setup_supabase.sh" --fresh
"$SCRIPT_DIR/init_db.sh"
exec "$SCRIPT_DIR/start_supabase.sh" --skip-init "$@"
