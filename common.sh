#!/usr/bin/env bash
# Shared utilities for Supabase lifecycle scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="$SCRIPT_DIR/.cache"
SUPABASE_SRC="$CACHE_DIR/supabase"
COMPOSE_FILE="$SUPABASE_SRC/docker/docker-compose.yml"
ENV_FILE="$SCRIPT_DIR/.env"
GENERATED_ENV_DIR="$SCRIPT_DIR/generated-env"
GENERATED_ENV_FILE="$GENERATED_ENV_DIR/archon.env"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-archon_supabase_local}"
SHARED_NETWORK="${SUPABASE_SHARED_NETWORK:-archon_app-network}"
SUPABASE_BRIDGE_ALIAS="${SUPABASE_BRIDGE_ALIAS:-supabase-kong.localhost}"
SUPABASE_VERSION="${SUPABASE_VERSION:-master}"
PULL_TIMEOUT_SECONDS="${SUPABASE_PULL_TIMEOUT_SECONDS:-420}"
UP_TIMEOUT_SECONDS="${SUPABASE_UP_TIMEOUT_SECONDS:-420}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

ensure_compose_available() {
  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 is required (the 'docker compose' command)." >&2
    exit 1
  fi
}

compose_cmd() {
  COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    "$@"
}

update_env_var() {
  local key="$1"
  local value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PY'
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

lines = []
if env_path.exists():
    lines = env_path.read_text().splitlines()

updated = False
for idx, line in enumerate(lines):
    if line.startswith(f"{key}="):
        lines[idx] = f"{key}={value}"
        updated = True
        break

if not updated:
    lines.append(f"{key}={value}")

env_path.write_text("\n".join(lines) + "\n")
PY
}

read_env_var() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true
}

random_hex() {
  local bytes="${1:-32}"
  openssl rand -hex "$bytes"
}

random_base64() {
  local bytes="${1:-32}"
  openssl rand -base64 "$bytes" | tr -d '\n'
}

generate_jwt() {
  local secret="$1"
  local role="$2"
  python3 - "$secret" "$role" <<'PY'
import base64, hashlib, hmac, json, sys, time

secret = sys.argv[1]
role = sys.argv[2]
now = int(time.time())
payload = {
    "role": role,
    "iss": "archon-supabase-local",
    "iat": now,
    "exp": now + 60 * 60 * 24 * 365 * 10,  # 10 years
    "sub": role,
    "aud": role if role == "anon" else "authenticated",
}
header = {"alg": "HS256", "typ": "JWT"}

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

segments = [
    b64url(json.dumps(header, separators=(",", ":")).encode()),
    b64url(json.dumps(payload, separators=(",", ":")).encode()),
]
signing_input = ".".join(segments).encode()
signature = hmac.new(secret.encode(), signing_input, hashlib.sha256).digest()
segments.append(b64url(signature))
print(".".join(segments))
PY
}

ensure_repo() {
  mkdir -p "$CACHE_DIR"
  if [[ ! -d "$SUPABASE_SRC/.git" ]]; then
    echo "Cloning Supabase (${SUPABASE_VERSION})..."
    git clone --depth 1 --branch "$SUPABASE_VERSION" https://github.com/supabase/supabase "$SUPABASE_SRC"
  else
    echo "Updating Supabase clone to ${SUPABASE_VERSION}..."
    git -C "$SUPABASE_SRC" fetch --depth 1 origin "$SUPABASE_VERSION"
    git -C "$SUPABASE_SRC" checkout --force "$SUPABASE_VERSION"
  fi

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Supabase compose file not found at $COMPOSE_FILE" >&2
    exit 1
  fi
}

generate_env() {
  mkdir -p "$(dirname "$ENV_FILE")"
  cp "$SUPABASE_SRC/docker/.env.example" "$ENV_FILE"

  POSTGRES_PASSWORD="$(random_hex 24)"
  JWT_SECRET="$(random_hex 32)"
  ANON_KEY="$(generate_jwt "$JWT_SECRET" "anon")"
  SERVICE_ROLE_KEY="$(generate_jwt "$JWT_SECRET" "service_role")"

  update_env_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
  update_env_var "JWT_SECRET" "$JWT_SECRET"
  update_env_var "ANON_KEY" "$ANON_KEY"
  update_env_var "SERVICE_ROLE_KEY" "$SERVICE_ROLE_KEY"
  update_env_var "DASHBOARD_USERNAME" "supabase"
  update_env_var "DASHBOARD_PASSWORD" "$(random_base64 18)"
  update_env_var "SECRET_KEY_BASE" "$(random_hex 32)"
  update_env_var "VAULT_ENC_KEY" "$(random_hex 32)"
  update_env_var "PG_META_CRYPTO_KEY" "$(random_hex 32)"
  update_env_var "POOLER_TENANT_ID" "$(random_hex 16)"
  update_env_var "LOGFLARE_PUBLIC_ACCESS_TOKEN" "$(random_hex 24)"
  update_env_var "LOGFLARE_PRIVATE_ACCESS_TOKEN" "$(random_hex 24)"
  update_env_var "SUPABASE_PUBLIC_URL" "http://localhost:8000"
  update_env_var "API_EXTERNAL_URL" "http://localhost:8000"
}

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Generating Supabase environment file..."
    generate_env
  fi
}

write_generated_env() {
  mkdir -p "$GENERATED_ENV_DIR"
  local anon service port
  anon="$(read_env_var "ANON_KEY")"
  service="$(read_env_var "SERVICE_ROLE_KEY")"
  port="$(read_env_var "KONG_HTTP_PORT")"
  port="${port:-8000}"
  cat >"$GENERATED_ENV_FILE" <<EOF
# Generated by Supabase lifecycle scripts on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
SUPABASE_URL=http://127.0.0.1:${port}
SUPABASE_ANON_KEY=${anon}
SUPABASE_SERVICE_KEY=${service}
EOF
}

connect_shared_network() {
  local container="$1"
  shift
  local network="$SHARED_NETWORK"
  local aliases=("$@")

  if [[ -z "$network" ]]; then
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    return
  fi
  if ! docker info >/dev/null 2>&1; then
    return
  fi
  if ! docker network inspect "$network" >/dev/null 2>&1; then
    return
  fi

  local inspect_output=""
  inspect_output="$(docker inspect "$container" --format '{{json .NetworkSettings.Networks}}' 2>/dev/null || true)"
  if [[ -z "$inspect_output" ]]; then
    return
  fi

  local connected=false
  if NETWORK_INFO="$inspect_output" python3 - "$network" <<'PY'
import json, os, sys

networks = json.loads(os.environ["NETWORK_INFO"])
target = sys.argv[1]
sys.exit(0 if target in networks else 1)
PY
  then
    connected=true
  fi

  if [[ "$connected" == true && ${#aliases[@]} -gt 0 ]]; then
    if NETWORK_INFO="$inspect_output" python3 - "$network" "${aliases[@]}" <<'PY'
import json, os, sys

networks = json.loads(os.environ["NETWORK_INFO"])
target = sys.argv[1]
aliases = [alias for alias in sys.argv[2:] if alias]
info = networks.get(target) or {}
existing = set(info.get("Aliases") or [])
missing = [alias for alias in aliases if alias not in existing]
sys.exit(0 if not missing else 1)
PY
    then
      return
    fi

    docker network disconnect "$network" "$container" >/dev/null 2>&1 || return
    connected=false
  fi

  if [[ "$connected" == true ]]; then
    return
  fi

  local args=()
  for alias in "${aliases[@]}"; do
    if [[ -n "$alias" ]]; then
      args+=(--alias "$alias")
    fi
  done

  if docker network connect "${args[@]}" "$network" "$container" >/dev/null 2>&1; then
    if [[ ${#args[@]} -gt 0 ]]; then
      echo "Attached $container to $network with aliases ${aliases[*]}"
    else
      echo "Attached $container to $network"
    fi
  fi
}

wait_for_postgres() {
  local max_attempts="${1:-40}"
  local attempt=1
  while (( attempt <= max_attempts )); do
    if compose_cmd exec -T db pg_isready -U postgres -d postgres -h localhost >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
    ((attempt++))
  done
  echo "Postgres did not become ready in time." >&2
  return 1
}

apply_archon_schema() {
  local exists
  exists=$(compose_cmd exec -T db psql -U postgres -d postgres -tAc "SELECT to_regclass('public.archon_settings');" | tr -d '[:space:]')

  if [[ "$exists" == "archon_settings" ]]; then
    echo "Archon schema already present. Skipping migration."
    return 0
  fi

  echo "Applying Archon schema (migration/complete_setup.sql)..."
  local attempts=0
  local max_attempts=3
  while (( attempts < max_attempts )); do
    if cat "$ARCHON_ROOT/migration/complete_setup.sql" | compose_cmd exec -T db psql -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null; then
      echo "Schema applied successfully."
      return 0
    fi
    ((attempts++))
    if (( attempts < max_attempts )); then
      echo "Schema application failed (attempt ${attempts}/${max_attempts}). Cleaning up and retrying in 5s..."
      compose_cmd exec -T db psql -U postgres -d postgres -c "DROP TABLE IF EXISTS archon_settings CASCADE;" >/dev/null || true
      sleep 5
    fi
  done
  echo "Schema application failed after ${max_attempts} attempts." >&2
  exit 1
}

pull_images() {
  timeout "${PULL_TIMEOUT_SECONDS}s" env COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT_NAME" docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    pull
}
