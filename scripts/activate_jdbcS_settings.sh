#!/usr/bin/env bash
#
# IMPORTANT:
# This script MUST be executed from the project root directory.
# It expects .env.dev or .env.prod to be present at the same level.
#
# Example:
#   ENV_FILE=.env.dev ./scripts/activate_jdbcS_settings.sh
#
# Running this script without the correct env file will cause failures.
#set -euo pipefail

ENV_FILE="${ENV_FILE:-.env.dev}"

############################################
# 0️⃣ Load .env (HOST)
############################################
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ .env not found: $ENV_FILE"
  exit 1
fi

echo "🔑 Loading $ENV_FILE"
set -a
source "$ENV_FILE"
set +a

############################################
# CONFIG
############################################
if [ -n "${COMPOSE_FILE:-}" ]; then
  COMPOSE_FILE="${COMPOSE_FILE}"
elif [[ "${ENV_FILE}" == *"prod"* ]] && [ -f "docker-compose-prod.yml" ]; then
  COMPOSE_FILE="docker-compose-prod.yml"
else
  COMPOSE_FILE="docker-compose-dev.yml"
fi
HOST_INIT_DIR="${HOST_INIT_DIR:-./docker/geoserver-init}"
GS_SECURITY_DIR="${GS_SECURITY_DIR:-/geoserver_data/data/security}"
GS_URL="${GS_URL:-http://localhost:8080/geoserver}"
ADMIN_USER="${GEOSERVER_ADMIN_USER:-admin}"
ADMIN_PASS="${GEOSERVER_ADMIN_PASSWORD:-geoserver}"
SECURITY_MODE="${GEOSERVER_SECURITY_MODE:-default}"

case "$SECURITY_MODE" in
  jdbc-role)
    MODE_ENABLE_ROLE=true
    MODE_ENABLE_AUTH=false
    SECURITY_AUTH_PROVIDER_NAME="default"
    ;;
  jdbc-auth-role)
    MODE_ENABLE_ROLE=true
    MODE_ENABLE_AUTH=true
    SECURITY_AUTH_PROVIDER_NAME="${JDBC_AUTH_SERVICE_NAME:-jdbc_auth}"
    ;;
  *)
    MODE_ENABLE_ROLE=false
    MODE_ENABLE_AUTH=false
    SECURITY_AUTH_PROVIDER_NAME="default"
    ;;
esac

if [ "${GEOSERVER_ENABLE_JDBC_CONFIG:-false}" = "true" ] || [ "$SECURITY_MODE" = "jdbc-config" ]; then
  MODE_ENABLE_CONFIG=true
else
  MODE_ENABLE_CONFIG=false
fi

echo "🧭 Using compose file: $COMPOSE_FILE"
echo "🔐 Security mode: $SECURITY_MODE"
echo "🔑 Security auth provider in config: $SECURITY_AUTH_PROVIDER_NAME"

if [ "$MODE_ENABLE_ROLE" != true ] && [ "$MODE_ENABLE_CONFIG" != true ]; then
  echo "❌ activate_jdbcS_settings.sh only supports jdbc-role, jdbc-auth-role, or jdbc-config flows"
  echo "   Current GEOSERVER_SECURITY_MODE=$SECURITY_MODE"
  exit 1
fi

############################################
# 1️⃣ Detect containers
############################################
GEOSERVER_CONTAINER=$(
  docker compose -f "$COMPOSE_FILE" ps -q geoserver \
  | xargs -r docker inspect --format '{{.Name}}' | sed 's|/||'
)

DB_CONTAINER=$(
  docker compose -f "$COMPOSE_FILE" ps -q db \
  | xargs -r docker inspect --format '{{.Name}}' | sed 's|/||'
)

[ -z "$GEOSERVER_CONTAINER" ] && echo "❌ GeoServer container not found" && exit 1
[ -z "$DB_CONTAINER" ] && echo "❌ DB container not found" && exit 1

echo "🧱 GeoServer: $GEOSERVER_CONTAINER"
echo "🗄️  DB:       $DB_CONTAINER"

############################################
# 2️⃣ Wait for GeoServer health
############################################
MAX_WAIT=240
COUNTER=0

while true; do
  HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$GEOSERVER_CONTAINER" 2>/dev/null || echo "notfound")
  if [ "$HEALTH_STATUS" = "healthy" ]; then
    echo "✅ GeoServer web service is healthy."
    break
  fi
  if [ $COUNTER -ge $MAX_WAIT ]; then
    echo "❌ GeoServer did not become healthy in $MAX_WAIT seconds."
    exit 1
  fi
  echo "⏳ Waiting for GeoServer... ($COUNTER/$MAX_WAIT)"
  sleep 5
  COUNTER=$((COUNTER + 5))
done

############################################
# 3️⃣ Render templates
############################################
render() {
  local DIR="$1"
  envsubst < "$DIR/config.xml.template" > "$DIR/config.xml"
}

echo "🧩 Rendering templates"
render "$HOST_INIT_DIR/jdbc_role_service/jdbc_role"
if [ "$MODE_ENABLE_AUTH" = true ]; then
  render "$HOST_INIT_DIR/jdbc_login_service/jdbc_login"
  render "$HOST_INIT_DIR/auth/jdbc_auth"
fi
SECURITY_AUTH_PROVIDER_NAME="$SECURITY_AUTH_PROVIDER_NAME" envsubst < "$HOST_INIT_DIR/security/config.xml.template" \
        > "$HOST_INIT_DIR/security/config.xml"

############################################
# 4️⃣ Copy security files
############################################
docker_cp_dir_if_missing() {
  docker exec "$GEOSERVER_CONTAINER" sh -lc "[ -d '$2' ]" && return
  docker exec "$GEOSERVER_CONTAINER" sh -lc "mkdir -p '$(dirname "$2")'"
  docker cp "$1" "$GEOSERVER_CONTAINER:$2"
}

docker_cp_file_overwrite() {
  docker exec "$GEOSERVER_CONTAINER" sh -lc "mkdir -p '$(dirname "$2")'"
  docker cp "$1" "$GEOSERVER_CONTAINER:$2"
}

echo "📦 Copying security files"
docker_cp_dir_if_missing \
  "$HOST_INIT_DIR/jdbc_role_service/jdbc_role" \
  "$GS_SECURITY_DIR/role/jdbc_role"

if [ "$MODE_ENABLE_AUTH" = true ]; then
  docker_cp_dir_if_missing \
    "$HOST_INIT_DIR/jdbc_login_service/jdbc_login" \
    "$GS_SECURITY_DIR/usergroup/jdbc_login"

  docker_cp_dir_if_missing \
    "$HOST_INIT_DIR/auth/jdbc_auth" \
    "$GS_SECURITY_DIR/auth/jdbc_auth"
fi

docker_cp_file_overwrite \
  "$HOST_INIT_DIR/security/config.xml" \
  "$GS_SECURITY_DIR/config.xml"

############################################
# 5️⃣ Wait for JDBC tables
############################################
echo ""
echo "=================================================="
echo "⚠️  MANUAL STEP REQUIRED ⚠️"
echo "=================================================="
echo "1) Open GeoServer UI"
if [ "$MODE_ENABLE_AUTH" = true ]; then
  echo "2) Security → User Group Services → jdbc_login → Test connection → Save"
  echo "3) Security → Role Services → jdbc_role → Test connection → Save"
else
  echo "2) Security → Role Services → jdbc_role → Test connection → Save"
fi
echo ""
echo "⏳ Waiting for JDBC tables..."
echo "=================================================="
echo "Schema: ${PG_SCHEMA_GEOSERVER}"
echo "DB host/port in check: ${PG_HOST:-db}:${PG_DOCKER_PORT:-5432}"

if [ "$MODE_ENABLE_AUTH" = true ]; then
  REQUIRED_TABLES=("roles" "users" "user_roles")
else
  REQUIRED_TABLES=("roles" "user_roles")
fi
ACTIVE_JDBC_SCHEMA="${PG_SCHEMA_GEOSERVER}"
AUTO_CREATE_MISSING_JDBC_TABLES="${AUTO_CREATE_MISSING_JDBC_TABLES:-true}"
AUTO_CREATE_DONE=false

while true; do
  FOUND_TARGET=0
  FOUND_PUBLIC=0
  if ! TABLES_EXIST=$(
    docker exec -i "$DB_CONTAINER" sh -lc \
    "PGPASSWORD='$PG_GS_PASSWORD' psql -t -A \
      -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
      -U '$PG_GS_USER' -d '$PG_DATABASE' \
      -c \"SELECT schemaname || '|' || tablename FROM pg_tables WHERE schemaname IN ('${PG_SCHEMA_GEOSERVER}','public');\""
  ); then
    echo "❌ Could not query PostgreSQL while waiting for JDBC tables."
    echo "⏱️  Retrying in 10s"
    sleep 10
    continue
  fi

  if [ -n "$TABLES_EXIST" ]; then
    echo "🔎 Tables currently visible in ${PG_SCHEMA_GEOSERVER} and public:"
    echo "$TABLES_EXIST" | sed 's/^/   - /'
  else
    echo "🔎 No tables currently visible in ${PG_SCHEMA_GEOSERVER} and public"
  fi

  for tbl in "${REQUIRED_TABLES[@]}"; do
    if echo "$TABLES_EXIST" | grep -qx "${PG_SCHEMA_GEOSERVER}|$tbl"; then
      FOUND_TARGET=$((FOUND_TARGET+1))
    fi
    if echo "$TABLES_EXIST" | grep -qx "public|$tbl"; then
      FOUND_PUBLIC=$((FOUND_PUBLIC+1))
    fi
  done

  if [ "$FOUND_TARGET" -eq "${#REQUIRED_TABLES[@]}" ]; then
    ACTIVE_JDBC_SCHEMA="${PG_SCHEMA_GEOSERVER}"
    echo "✅ JDBC tables detected in schema ${ACTIVE_JDBC_SCHEMA}: ${REQUIRED_TABLES[*]}"
    break
  fi

  if [ "$FOUND_PUBLIC" -eq "${#REQUIRED_TABLES[@]}" ]; then
    ACTIVE_JDBC_SCHEMA="public"
    echo "⚠️  JDBC tables were created in public schema."
    echo "✅ Continuing with ACTIVE_JDBC_SCHEMA=${ACTIVE_JDBC_SCHEMA}"
    break
  fi

  if [ "$AUTO_CREATE_MISSING_JDBC_TABLES" = "true" ] && [ "$AUTO_CREATE_DONE" = false ]; then
    echo "🛠️  Auto-creating missing JDBC tables in schema ${PG_SCHEMA_GEOSERVER}"
    if docker exec -i "$DB_CONTAINER" sh -lc \
      "PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
        -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
        -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL
CREATE SCHEMA IF NOT EXISTS ${PG_SCHEMA_GEOSERVER};

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.roles (
  name varchar(64) NOT NULL PRIMARY KEY,
  parent varchar(64)
);

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.role_props (
  rolename varchar(64) NOT NULL,
  propname varchar(64) NOT NULL,
  propvalue varchar(2048),
  PRIMARY KEY (rolename, propname)
);

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.user_roles (
  username varchar(128) NOT NULL,
  rolename varchar(64) NOT NULL,
  PRIMARY KEY (username, rolename)
);

CREATE INDEX IF NOT EXISTS user_roles_idx ON ${PG_SCHEMA_GEOSERVER}.user_roles (rolename, username);

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.group_roles (
  groupname varchar(128) NOT NULL,
  rolename varchar(64) NOT NULL,
  PRIMARY KEY (groupname, rolename)
);

CREATE INDEX IF NOT EXISTS group_roles_idx ON ${PG_SCHEMA_GEOSERVER}.group_roles (rolename, groupname);
SQL
    then
      if [ "$MODE_ENABLE_AUTH" = true ]; then
        if docker exec -i "$DB_CONTAINER" sh -lc \
          "PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
            -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
            -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL
CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.users (
  name varchar(128) NOT NULL PRIMARY KEY,
  password varchar(254),
  enabled char(1) NOT NULL
);

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.user_props (
  username varchar(128) NOT NULL,
  propname varchar(64) NOT NULL,
  propvalue varchar(2048),
  PRIMARY KEY (username, propname)
);

CREATE INDEX IF NOT EXISTS user_props_idx1 ON ${PG_SCHEMA_GEOSERVER}.user_props (propname, propvalue);
CREATE INDEX IF NOT EXISTS user_props_idx2 ON ${PG_SCHEMA_GEOSERVER}.user_props (propname, username);

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.groups (
  name varchar(128) NOT NULL PRIMARY KEY,
  enabled char(1) NOT NULL
);

CREATE TABLE IF NOT EXISTS ${PG_SCHEMA_GEOSERVER}.group_members (
  groupname varchar(128) NOT NULL,
  username varchar(128) NOT NULL,
  PRIMARY KEY (groupname, username)
);

CREATE INDEX IF NOT EXISTS group_members_idx ON ${PG_SCHEMA_GEOSERVER}.group_members (username, groupname);
SQL
        then
          echo "✅ JDBC auth tables bootstrap completed in schema ${PG_SCHEMA_GEOSERVER}"
        else
          echo "⚠️  JDBC auth table bootstrap failed; continuing to wait for UI-triggered creation"
        fi
      fi
      AUTO_CREATE_DONE=true
      echo "✅ JDBC role tables bootstrap completed in schema ${PG_SCHEMA_GEOSERVER}"
    else
      echo "⚠️  JDBC auto-create failed; continuing to wait for UI-triggered creation"
      AUTO_CREATE_DONE=true
    fi
  fi

  echo "⏱️  Not ready yet… waiting 10s"
  sleep 10
done

############################################
# 6️⃣ Seed roles
############################################
echo "🧬 Seeding roles"
echo "🗂️  Using schema for seeding: ${ACTIVE_JDBC_SCHEMA}"
docker exec -i "$DB_CONTAINER" sh -lc \
"PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
 -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
 -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

INSERT INTO ${ACTIVE_JDBC_SCHEMA}.roles (name, parent)
VALUES
  ('ADMIN','ROLE_ADMINISTRATOR'),
  ('GROUP_ADMIN','ROLE_GROUP_ADMIN')
ON CONFLICT DO NOTHING;
SQL

############################################
# 7️⃣ Create admin user via REST (FIXED)
############################################
BOOTSTRAP_AUTH_USER="${GEOSERVER_ADMIN_USER:-admin}"
BOOTSTRAP_AUTH_PASS="${GEOSERVER_ADMIN_PASSWORD:-geoserver}"

if [ "$MODE_ENABLE_AUTH" = true ]; then
  # from .env (fallback)
  JDBC_LOGIN_SERVICE_NAME="${JDBC_LOGIN_SERVICE_NAME:-jdbc_login}"

  # IMPORTANT: this runs INSIDE the geoserver container, so localhost is correct
  USER_API="http://localhost:8080/geoserver/rest/security/usergroup/service/${JDBC_LOGIN_SERVICE_NAME}/users"

  echo "👤 Creating user '${ADMIN_USER}' via ${JDBC_LOGIN_SERVICE_NAME}..."

  RESPONSE=$(docker exec "$GEOSERVER_CONTAINER" sh -lc "
curl -s -w '\n%{http_code}' \
  -u \"${BOOTSTRAP_AUTH_USER}:${BOOTSTRAP_AUTH_PASS}\" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -X POST \
  \"${USER_API}\" \
  -d '{
    \"user\": {
      \"userName\": \"${ADMIN_USER}\",
      \"password\": \"${ADMIN_PASS}\",
      \"enabled\": true
    }
  }'
")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  case "$HTTP_CODE" in
    201)
      echo "✅ User created successfully"
      ;;
    409)
      echo "ℹ️  User already exists (HTTP 409)"
      ;;
    500)
      if echo "$BODY" | grep -qi 'duplicate key value violates unique constraint.*users_pkey'; then
        echo "ℹ️  User already exists (duplicate key on users_pkey)"
      else
        echo "❌ Server error while creating user (HTTP 500)"
        echo "$BODY"
        exit 1
      fi
      ;;
    401)
      echo "❌ Authentication failed (HTTP 401) - configured admin credentials rejected"
      echo "$BODY"
      exit 1
      ;;
    404)
      echo "❌ Endpoint not found (HTTP 404)"
      echo "   USER_API: ${USER_API}"
      echo "$BODY"
      exit 1
      ;;
    *)
      echo "❌ Unexpected response (HTTP $HTTP_CODE)"
      echo "$BODY"
      exit 1
      ;;
  esac
else
  echo "ℹ️  jdbc-role mode: skipping JDBC user creation; users remain file-backed"
fi

############################################
# 8️⃣ Assign role to admin
############################################
echo "🔗 Assigning ADMIN role to ${ADMIN_USER}"
if [ "$MODE_ENABLE_AUTH" = true ]; then
  docker exec -i "$DB_CONTAINER" sh -lc \
  "PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
   -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
   -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

INSERT INTO ${ACTIVE_JDBC_SCHEMA}.user_roles (username, rolename)
VALUES ('${ADMIN_USER}','ADMIN')
ON CONFLICT DO NOTHING;

SELECT 
  u.name        AS username,
  u.enabled,
  ur.rolename
FROM ${ACTIVE_JDBC_SCHEMA}.users u
LEFT JOIN ${ACTIVE_JDBC_SCHEMA}.user_roles ur
  ON ur.username = u.name
WHERE u.name = '${ADMIN_USER}';
SQL
else
  docker exec -i "$DB_CONTAINER" sh -lc \
  "PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
   -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
   -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

INSERT INTO ${ACTIVE_JDBC_SCHEMA}.user_roles (username, rolename)
VALUES ('${ADMIN_USER}','ADMIN')
ON CONFLICT DO NOTHING;

SELECT username, rolename
FROM ${ACTIVE_JDBC_SCHEMA}.user_roles
WHERE username = '${ADMIN_USER}'
  AND rolename = 'ADMIN';
SQL
fi

############################################
# 9️⃣ Activate JDBCConfig
############################################
if [ "$MODE_ENABLE_CONFIG" = true ]; then
  echo "⚙️  Activating JDBCConfig"
  JDBCCONFIG_HOST_SCRIPT="$HOST_INIT_DIR/jdbcConfig/activate_jdbcConfig.sh"
  JDBCCONFIG_CONTAINER_SCRIPT="/tmp/activate_jdbcConfig.sh"

  docker cp \
    "$JDBCCONFIG_HOST_SCRIPT" \
    "$GEOSERVER_CONTAINER:$JDBCCONFIG_CONTAINER_SCRIPT"

  docker exec "$GEOSERVER_CONTAINER" sh -lc \
    "chmod +x '$JDBCCONFIG_CONTAINER_SCRIPT' && '$JDBCCONFIG_CONTAINER_SCRIPT'"
else
  echo "ℹ️  JDBCConfig activation skipped for security mode ${SECURITY_MODE}"
fi

############################################
# 🔟 Reload GeoServer
############################################
echo "🔄 Reloading GeoServer"
if ! docker exec "$GEOSERVER_CONTAINER" sh -lc \
  "curl -sf -u \"${BOOTSTRAP_AUTH_USER}:${BOOTSTRAP_AUTH_PASS}\" -X POST \"${GS_URL}/rest/reload\""; then
  echo "❌ GeoServer reload failed!"
  exit 1
fi

read -p "User setup is complete. Do you want to restart GeoServer now to apply changes? (y/n): " RESTART_ANSWER
if [[ "$RESTART_ANSWER" =~ ^[Yy]$ ]]; then
  echo "Bringing up DB + GeoServer for changes to take effect..."
  docker compose -f "$COMPOSE_FILE" up -d db geoserver

  echo "⏳ Waiting for DB container to exist..."
  DB_WAIT=0
  while ! docker compose -f "$COMPOSE_FILE" ps -q db >/dev/null 2>&1 || [ -z "$(docker compose -f "$COMPOSE_FILE" ps -q db 2>/dev/null)" ]; do
    sleep 2
    DB_WAIT=$((DB_WAIT + 2))
    if [ "$DB_WAIT" -ge 60 ]; then
      echo "⚠️  DB container did not appear within 60 seconds"
      break
    fi
  done

  echo "⏳ Waiting for GeoServer health after restart..."
  GS_WAIT=0
  while true; do
    HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$GEOSERVER_CONTAINER" 2>/dev/null || echo "notfound")
    if [ "$HEALTH_STATUS" = "healthy" ]; then
      echo "✅ GeoServer is healthy after restart"
      break
    fi
    if [ "$HEALTH_STATUS" = "unhealthy" ]; then
      echo "❌ GeoServer became unhealthy after restart"
      echo "--- Last 120 GeoServer log lines ---"
      docker logs --tail 120 "$GEOSERVER_CONTAINER" 2>&1 || true
      exit 1
    fi
    sleep 5
    GS_WAIT=$((GS_WAIT + 5))
    if [ "$GS_WAIT" -ge 180 ]; then
      echo "⚠️  GeoServer did not become healthy within 180 seconds"
      echo "--- Last 120 GeoServer log lines ---"
      docker logs --tail 120 "$GEOSERVER_CONTAINER" 2>&1 || true
      exit 1
    fi
  done
else
  echo "Restart skipped. Changes will take effect on the next restart."
fi

echo ""
echo "🎉 Setup complete!"
