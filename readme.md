# GeoServer Docker (Mode-First, Production-Ready)

This directory contains the refactored GeoServer Docker setup used by TOSCA Backend.

The default deployment path is **file-backed GeoServer** (`GEOSERVER_SECURITY_MODE=default`) with hardened runtime validation, proxy handling, and admin bootstrap.

JDBC-based security/config is available as explicit opt-in modes.

## What This Setup Provides

- GeoServer `2.28.3` on Tomcat JDK 17
- Deterministic startup pipeline in `scripts/entrypoint.sh`
- Environment-driven CORS, CSRF, proxy, and credentials
- Mode-aware runtime validation before startup
- Optional JDBC modes for security and config
- Two explicit compose targets only:
  - `docker-compose-dev.yml`
  - `docker-compose-prod.yml`

## Runtime Modes

Use `GEOSERVER_SECURITY_MODE` to select behavior.

| Mode | Purpose | DB Required | Default |
| --- | --- | --- | --- |
| `default` | File-backed GeoServer config/security | No | Yes |
| `jdbc-role` | JDBC role service only (users stay file-backed) | Yes | No |
| `jdbc-auth-role` | JDBC user/group + JDBC role services | Yes | No |
| `jdbc-config` | JDBC config/catalog backend (advanced) | Yes | No |

Mode flags are validated by `scripts/geoserver_validate_runtime.py`.

## Quick Start

### 1) Development (default mode)

```bash
cp env_dev_sample .env.dev
docker compose -f docker-compose-dev.yml --env-file .env.dev up -d --build geoserver
```

Makefile equivalent:

```bash
make init-dev
make up ENV=dev
```

GeoServer UI:

```text
http://localhost:${GEOSERVER_HOST_PORT}/geoserver
```

### 2) Production (default mode)

```bash
cp env_prod_sample .env.prod
# edit .env.prod values for your server/domain/passwords

docker compose -f docker-compose-prod.yml --env-file .env.prod up -d --build geoserver
```

Makefile equivalent:

```bash
make init-prod ENV=prod
make validate ENV=prod
make up ENV=prod
```

Production pre-check:

```bash
set -a && source .env.prod && set +a
./scripts/check_prod_env.sh
```

## Environment Model

This project is controlled by `.env.dev` and `.env.prod`.

Main sections in env files:

1. Global: `COMPOSE_PROJECT_NAME`, `ENV`, `PROD_MODE`
2. Core: GeoServer version/ports/data dir/mode
3. Admin bootstrap: `GEOSERVER_ADMIN_USER`, `GEOSERVER_ADMIN_PASSWORD`
4. URLs/proxy: internal URL vs public URL vs proxy base URL
5. CORS/CSRF hardening
6. Plugins
7. PostgreSQL ports and users
8. Optional JDBC flags

Canonical ports:

- `GEOSERVER_HOST_PORT`
- `GEOSERVER_CONTAINER_PORT`
- `POSTGRES_HOST_PORT`
- `POSTGRES_CONTAINER_PORT`

Backward-compatible aliases (`PG_PORT`, `PG_DOCKER_PORT`, `ENABLE_JDBC_*`) remain for compatibility with existing JDBC templates/scripts.

## Startup and Validation Flow

Container startup is orchestrated by `scripts/entrypoint.sh`:

1. Validate runtime env (`geoserver_validate_runtime.py`)
2. Ensure writable `GEOSERVER_DATA_DIR`
3. Inject CORS filter in `web.xml` (idempotent)
4. Start Tomcat
5. Wait for web + REST readiness (`geoserver_wait_ready.sh`)
6. Wait for core first-boot files
7. Apply admin credentials (`geoserver_set_admin_credentials.py`)
8. Apply JDBC security/config only when enabled
9. Apply/validate proxy settings when `PROXY_BASE_URL` is set
10. Keep Tomcat as foreground process

## Reverse Proxy Rules

Use three distinct URL variables:

- `GEOSERVER_INTERNAL_URL`: only for internal bootstrap/REST checks
- `GEOSERVER_PUBLIC_URL`: user-facing external URL
- `PROXY_BASE_URL`: GeoServer proxyBaseUrl (usually same as public URL)

For production, configure forwarded headers in your reverse proxy:

- `X-Forwarded-Proto`
- `X-Forwarded-Host`
- `X-Forwarded-Port`
- `X-Forwarded-Prefix` (if path-prefix proxying is used)

See `docs/reverse_proxy.md` for details.

## Plugins

Default baked plugin sets:

- Official: `gdal,monitor,vectortiles,mbstyle`
- Community: `sec-oidc`

JDBC community modules are optional and mode-dependent:

- `jdbcconfig`
- `jdbcstore`

Build-time toggle:

```text
BUILD_JDBC_PLUGINS=false
```

Runtime plugin lists are read from env (`OFFICIAL_PLUGINS`, `COMMUNITY_PLUGINS`).

## JDBC Modes (Advanced)

Use JDBC modes only when you need PostgreSQL-backed security/config.

Full operational guide:

- `readme_jdbc.md`
- `docs/jdbc_security.md`
- `docs/geoserver_modes.md`

### Minimal mode examples

`jdbc-role`:

```bash
GEOSERVER_SECURITY_MODE=jdbc-role \
GEOSERVER_ENABLE_JDBC_ROLE=true \
docker compose -f docker-compose-dev.yml --env-file .env.dev up -d --build db geoserver
```

`jdbc-auth-role`:

```bash
GEOSERVER_SECURITY_MODE=jdbc-auth-role \
GEOSERVER_ENABLE_JDBC_ROLE=true \
GEOSERVER_ENABLE_JDBC_AUTH=true \
docker compose -f docker-compose-dev.yml --env-file .env.dev up -d --build db geoserver
```

`jdbc-config`:

```bash
GEOSERVER_SECURITY_MODE=jdbc-config \
GEOSERVER_ENABLE_JDBC_CONFIG=true \
COMMUNITY_PLUGINS=sec-oidc,jdbcconfig \
docker compose -f docker-compose-dev.yml --env-file .env.dev up -d --build db geoserver
```

Validate JDBC mode from container:

```bash
docker compose -f docker-compose-dev.yml --env-file .env.dev exec geoserver \
  python3 /scripts/geoserver_validate_jdbc.py
```

## Makefile Shortcuts

Daily usage:

```bash
make help
make up ENV=dev
make up ENV=prod
make logs ENV=prod
make down ENV=prod
```

Default service for `make up` is `geoserver`.

To include DB explicitly:

```bash
make up-all ENV=dev
# or
make up ENV=dev SERVICE="db geoserver"
```

Useful operational targets:

```bash
make ps ENV=prod
make stop ENV=prod
make start ENV=prod
make shell-geoserver ENV=prod
make shell-db ENV=prod
make clean ENV=dev
```

## Production Checklist

Before first production boot:

- Set non-placeholder strong passwords in `.env.prod`
- Keep `GEOSERVER_ADMIN_PASSWORD` different from `geoserver`
- Set `GEOSERVER_PUBLIC_URL` and `PROXY_BASE_URL`
- Keep `GEOSERVER_INTERNAL_URL` internal (not public URL)
- Ensure `GEOSERVER_CSRF_WHITELIST` includes public GeoServer host
- Keep wildcard CORS disabled unless explicitly required

Validation commands:

```bash
set -a && source .env.prod && set +a
./scripts/check_prod_env.sh
docker compose -f docker-compose-prod.yml --env-file .env.prod exec geoserver \
  python3 /scripts/geoserver_validate_runtime.py
```

## Troubleshooting

- GeoServer not reachable:
  - Check container logs and `GEOSERVER_HOST_PORT` mapping.
- Runtime validation fails:
  - Fix mode/flag mismatch (`GEOSERVER_SECURITY_MODE` vs `GEOSERVER_ENABLE_*`).
- Proxy links are wrong:
  - Re-check `GEOSERVER_PUBLIC_URL`, `PROXY_BASE_URL`, and forwarded headers.
- Production validation fails:
  - Run `set -a && source .env.prod && set +a && ./scripts/check_prod_env.sh` and resolve the reported variable.
- JDBC mode fails:
  - Confirm DB is running, schemas exist, and JDBC flags/plugins match mode requirements.

## Additional Docs

- `docs/geoserver_modes.md`
- `docs/reverse_proxy.md`
- `docs/jdbc_security.md`
- `readme_jdbc.md`
- `readme_keycloak.md`
