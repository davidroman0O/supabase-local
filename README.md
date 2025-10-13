# Supabase Local Bootstrap

This folder automates bringing up a self-hosted Supabase stack for Archon without touching the main project configuration. It clones Supabase’s official Docker bundle, generates fresh secrets, applies Archon’s schema, and writes the values you need for `.env`.

Just `git clone` that repo into the `[archon](https://github.com/coleam00/Archon/)` repo. 

## Requirements

- macOS or Linux shell with Bash 5+
- Docker Desktop 4.24+ (or any docker engine with Compose v2)
- Git
- OpenSSL (for random secret generation)

All scripts assume you run them from the repository root (`/Users/davidroman/Documents/archon`).

## Quick Start

```bash
# First run or clean slate
./supabase-local/start_fresh.sh

# Subsequent restarts
./supabase-local/start.sh
```

These scripts wrap long-running Docker operations with the `timeout` CLI (default 420 seconds) so a stuck container can’t hang your shell.

### Full Lifecycle

| Action | Command | Notes |
| --- | --- | --- |
| Start / reuse | `./supabase-local/start.sh` | Reuses `.env`, only restarts stopped services. |
| Full reset | `./supabase-local/start_fresh.sh` | Stops containers, wipes volumes, removes cache, reclones Supabase, regenerates secrets, reapplies Archon schema, then starts everything. |
| Stop (keep data) | `./supabase-local/stop_supabase.sh` | Containers stop, named volumes remain. |
| Stop + destroy | `./supabase-local/stop_supabase.sh --destroy` | Stops containers and removes volumes (data loss). |
| Backup (archon only) | `./supabase-local/backup.sh` | Dumps `archon_*` tables into `supabase-local/backup/<timestamp>.archon.pgsql`. |
| Backup (full) | `./supabase-local/backup.sh --all` | Full database dump (may warn about Supabase-owned objects). |
| Restore | `./supabase-local/restore.sh <dump>` | Automatically stops containers, restores the dump, and restarts services (`--all` for full dumps). |

Behind the scenes `start_fresh.sh` runs `setup_supabase.sh --fresh`, `init_db.sh`, and `start_supabase.sh` in order. Setup refreshes the Supabase clone and `.env`, init starts Postgres and applies Archon migrations, and start brings the remaining services online.

Key scripts:

1. `setup_supabase.sh` – clones Supabase, prepares `.env`, and refreshes the cache when `--fresh` is supplied.
2. `init_db.sh` – starts Postgres, waits for readiness, and applies `migration/complete_setup.sql`.
3. `start_supabase.sh` – reuses the cache, optionally pulls images, and launches all services.

After the scripts run, sync the Supabase credentials into Archon’s `.env` (keeps other settings intact). On macOS/Windows the script substitutes `host.docker.internal` automatically; on Linux export `SUPABASE_HOST_OVERRIDE=172.17.0.1` (or your host IP) before running it if needed: 

```bash
SUPABASE_HOST_OVERRIDE=host.docker.internal ./supabase-local/apply_env.sh
```

## Common Tasks

Install / refresh the Supabase cache and secrets (without starting containers):

```bash
./supabase-local/setup_supabase.sh --fresh
```

Start / restart the Supabase stack after initial bootstrap (reuses existing keys and data):

```bash
./supabase-local/start.sh
```

Force a clean slate (regenerates secrets, drops volumes, wipes storage/db data, reclones Supabase):

```bash
./supabase-local/start_fresh.sh
```

Re-run migrations on the database only (leaves other services untouched):

```bash
./supabase-local/init_db.sh --skip-setup
```

Stop services (containers remain, data preserved):

```bash
./supabase-local/stop_supabase.sh
```

Tear down everything including volumes (irreversible):

```bash
./supabase-local/stop_supabase.sh --destroy
```

## Configuration Notes

- Secrets live in `supabase-local/.env` (git ignored). Regenerate by running `./supabase-local/start_fresh.sh`.
- Supabase compose project is named `archon_supabase_local` to avoid collisions with other compose apps.
- To use a different Supabase bundle tag: `SUPABASE_VERSION=v2.9.1 ./supabase-local/start.sh`
- Migration replays are idempotent. The script checks for `archon_settings` and skips reapplying if the schema already exists.
- Docker pull/up phases time out after 420 seconds by default. Override via `SUPABASE_PULL_TIMEOUT_SECONDS` and `SUPABASE_UP_TIMEOUT_SECONDS` environment variables if needed.

## Backup & Restore

### Logical Backup (recommended for dev)

#### Quick commands

```bash
# Archon tables only (default)
./supabase-local/backup.sh

# Full database (includes Supabase system schemas)
./supabase-local/backup.sh --all
```

Backups are stored under `supabase-local/backup/<timestamp>.{archon,full}.pgsql`.

#### Manual alternative

```bash
source supabase-local/generated-env/archon.env
PGURL="${SUPABASE_URL/http\\/\\/127.0.0.1:8000/postgres://postgres:$(grep '^POSTGRES_PASSWORD=' supabase-local/.env | cut -d= -f2)@127.0.0.1:5432/postgres}"

# Full database
pg_dump "$PGURL" --format=c --no-owner --no-privileges --file supabase-backup.pgsql

# Archon-only (avoids Supabase-specific permissions)
pg_dump "$PGURL" --format=c --no-owner --no-privileges \
  --table='archon_*' --file archon-only-backup.pgsql

# Container-based archon dump
env COMPOSE_PROJECT_NAME=archon_supabase_local \
 docker compose --env-file supabase-local/.env \
   -f supabase-local/.cache/supabase/docker/docker-compose.yml \
   exec -T db sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
     --format=c --no-owner --no-privileges \
     --table="archon_*" postgres://postgres:$POSTGRES_PASSWORD@127.0.0.1:5432/postgres' > archon-only-backup.pgsql
```

### Restore

#### Quick commands

```bash
# Archon dump
./supabase-local/restore.sh supabase-local/backup/<timestamp>.archon.pgsql

# Full dump (allows Supabase warnings)
./supabase-local/restore.sh --all supabase-local/backup/<timestamp>.full.pgsql
```

#### Manual alternative

```bash
./supabase-local/stop_supabase.sh

env COMPOSE_PROJECT_NAME=archon_supabase_local \
 docker compose --env-file supabase-local/.env \
   -f supabase-local/.cache/supabase/docker/docker-compose.yml \
   up -d db

pg_restore --clean --if-exists --no-owner --no-privileges \
  --dbname=postgres --host=127.0.0.1 --port=5432 --username=postgres \
  supabase-backup.pgsql

cat supabase-backup.pgsql | env COMPOSE_PROJECT_NAME=archon_supabase_local \
 docker compose --env-file supabase-local/.env \
   -f supabase-local/.cache/supabase/docker/docker-compose.yml \
   exec -T db sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
     --clean --if-exists --no-owner --no-privileges \
     --dbname=postgres --host=localhost --port=5432 --username=postgres'

./supabase-local/start.sh
```

Tip: For point-in-time recovery you’d need WAL archiving, which is usually overkill for local dev. Logical dumps cover most workflows.

> Supabase manages internal schemas, event triggers, and storage tables owned by service roles. When restoring a *full* database dump you may see permission warnings. They’re safe to ignore, or avoid them entirely by backing up only the `archon_*` tables as shown above.

## Using the Local Supabase with Archon

1. From the repository root, bootstrap or update the local stack:

   ```bash
   ./supabase-local/start_fresh.sh    # first run or when you want a clean slate
   # or
   ./supabase-local/start.sh          # reuse existing setup
   ```

2. Ensure Archon has a working `.env`:

   ```bash
   cp .env.example .env   # only if you haven’t created it yet
   ```

   Open `.env` alongside `supabase-local/generated-env/archon.env` and copy the Supabase entries (`SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `SUPABASE_ANON_KEY`) from the generated file into `.env`, replacing the placeholders. Leave the other keys in `.env` as-is unless you want to customize them.

3. Start the Archon services as usual (for example with `docker compose up --build -d` or `make dev`). The application will now talk to the local Supabase instance.

If you later regenerate credentials (for example by running `start_fresh.sh` again), repeat step 2 so Archon’s `.env` stays in sync.

## Troubleshooting

- If Docker cannot pull images, ensure you are signed into Docker Hub.
- To inspect database logs: `docker compose -p archon_supabase_local -f supabase-local/.cache/supabase/docker/docker-compose.yml logs -f db`
- If you change Supabase ports, adjust `KONG_HTTP_PORT` in `.env` and update the values exported in `generated-env/archon.env`.
