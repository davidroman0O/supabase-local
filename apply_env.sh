#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ROOT_DIR="$ARCHON_ROOT"
ENV_TEMPLATE="$ROOT_DIR/.env.example"
ARCHON_ENV="$ROOT_DIR/.env"
GENERATED_ENV="$GENERATED_ENV_FILE"

check_port() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    # macOS/BSD netcat uses -G for timeout, GNU netcat uses -w.
    if nc -h 2>&1 | grep -qi "OpenBSD"; then
      nc -z -G 1 "$host" "$port" >/dev/null 2>&1
    else
      nc -z -w 1 "$host" "$port" >/dev/null 2>&1
    fi
    return $?
  fi

  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout 1"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout 1"
  fi

  if [[ -n "$timeout_cmd" ]]; then
    $timeout_cmd bash -c ">/dev/tcp/${host}/${port}" >/dev/null 2>&1
  else
    bash -c ">/dev/tcp/${host}/${port}" >/dev/null 2>&1
  fi
}

detect_supabase_host() {
  if [[ -n "${SUPABASE_HOST_OVERRIDE:-}" ]]; then
    echo "$SUPABASE_HOST_OVERRIDE"
    return
  fi

  local port host candidates=() os network_gateway="" has_docker=false
  port="$(read_env_var "KONG_HTTP_PORT")"
  port="${port:-8000}"
  os="$(uname -s)"

  candidates+=(host.docker.internal 127.0.0.1 localhost)
  if [[ "$os" == "Linux" ]]; then
    candidates+=(172.17.0.1)
  fi

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    has_docker=true
    network_gateway="$(docker network inspect "${COMPOSE_PROJECT_NAME}_default" \
      --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null | tr -d '"' || true)"
    if [[ -n "$network_gateway" ]]; then
      candidates+=("$network_gateway")
    fi
  fi

  for host in "${candidates[@]}"; do
    if [[ -z "$host" ]]; then
      continue
    fi
    if check_port "$host" "$port"; then
      echo "$host"
      return
    fi
  done

  if [[ "$has_docker" == true ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^supabase-kong$'; then
    echo "${SUPABASE_BRIDGE_ALIAS:-supabase-kong.localhost}"
    return
  fi

  echo "${SUPABASE_BRIDGE_ALIAS:-supabase-kong.localhost}"
}

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
HOST_OVERRIDE="$(detect_supabase_host)"
echo "Using Supabase host override: $HOST_OVERRIDE"
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
