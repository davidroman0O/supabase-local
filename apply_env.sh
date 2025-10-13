#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR%/supabase-local}"
ENV_TEMPLATE="$ROOT_DIR/.env.example"
ARCHON_ENV="$ROOT_DIR/.env"
GENERATED_ENV="$SCRIPT_DIR/generated-env/archon.env"

usage() {
  cat <<'EOF'
Usage: ./supabase-local/apply_env.sh

Copies Supabase URL and keys from supabase-local/generated-env/archon.env
into the project's .env. If .env does not exist, it will be created from .env.example first.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${SUPABASE_LOCAL_GENERATED:-}" ]]; then
  GENERATED_ENV="$SUPABASE_LOCAL_GENERATED"
fi
if [[ -n "${SUPABASE_TARGET_ENV:-}" ]]; then
  ARCHON_ENV="$SUPABASE_TARGET_ENV"
fi

if [[ ! -f "$GENERATED_ENV" ]]; then
  echo "Generated env file not found at $GENERATED_ENV. Run ./supabase-local/start.sh or start_fresh.sh first." >&2
  exit 1
fi

if [[ ! -f "$ARCHON_ENV" ]]; then
  if [[ -f "$ENV_TEMPLATE" ]]; then
    echo "Creating .env from .env.example..."
    cp "$ENV_TEMPLATE" "$ARCHON_ENV"
  else
    echo ".env and .env.example are missing. Please create an .env file." >&2
    exit 1
  fi
fi

replacements=($(grep "^SUPABASE_" "$GENERATED_ENV" || true))
HOST_OVERRIDE=${SUPABASE_HOST_OVERRIDE:-host.docker.internal}
updated_keys=()

tmp=$(mktemp)
while IFS= read -r line; do
  for entry in "${replacements[@]}"; do
    key=${entry%%=*}
    value=${entry#*=}
    if [[ $key == SUPABASE_URL ]]; then
      value=${value/127.0.0.1/$HOST_OVERRIDE}
    fi
    if [[ "$line" == "$key="* ]]; then
      line="$key=$value"
      updated_keys+=("$key")
      break
    fi
  done
  printf '%s\n' "$line" >> "$tmp"
done < "$ARCHON_ENV"

for entry in "${replacements[@]}"; do
  key=${entry%%=*}
  value=${entry#*=}
  if [[ $key == SUPABASE_URL ]]; then
    value=${value/127.0.0.1/$HOST_OVERRIDE}
  fi
  skip=false
  for seen in "${updated_keys[@]}"; do
    if [[ "$seen" == "$key" ]]; then
      skip=true
      break
    fi
  done
  $skip && continue
  if ! grep -q "^$key=" "$tmp"; then
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
done

mv "$tmp" "$ARCHON_ENV"
echo "Supabase credentials applied to $ARCHON_ENV"
