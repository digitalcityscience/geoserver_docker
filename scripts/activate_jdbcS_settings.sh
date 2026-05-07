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

# jdbc-auth-role always performs the full auth provider switch in a single run.
# There is no staged mode: the admin user is created in the DB via REST while
# file-based login is still active, then the JDBC auth provider is activated.
APPLY_JDBC_AUTH_PROVIDER=false
if [ "$MODE_ENABLE_AUTH" = true ]; then
  APPLY_JDBC_AUTH_PROVIDER=true
fi

if [ "${GEOSERVER_ENABLE_JDBC_CONFIG:-false}" = "true" ] || [ "$SECURITY_MODE" = "jdbc-config" ]; then
  MODE_ENABLE_CONFIG=true
else
  MODE_ENABLE_CONFIG=false
fi

echo "🧭 Using compose file: $COMPOSE_FILE"
echo "🔐 Security mode: $SECURITY_MODE"
echo "🔑 Security auth provider in config: $SECURITY_AUTH_PROVIDER_NAME"
if [ "$MODE_ENABLE_AUTH" = true ]; then
  echo "🧩 Flow: role+auth (jdbc_role + jdbc_login + jdbc_auth)"
else
  echo "🧩 Flow: role-only (jdbc_role)"
fi


if [ "$MODE_ENABLE_ROLE" != true ] && [ "$MODE_ENABLE_CONFIG" != true ]; then
  echo "❌ activate_jdbcS_settings.sh only supports jdbc-role, jdbc-auth-role, or jdbc-config flows"
  echo "   Current GEOSERVER_SECURITY_MODE=$SECURITY_MODE"
  exit 1
fi

ACTIVE_JDBC_SCHEMA="${PG_SCHEMA_GEOSERVER}"

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

############################################
# JDBC ROLE operations
############################################
render "$HOST_INIT_DIR/jdbc_role_service/jdbc_role"

############################################
# JDBC AUTH operations
############################################
if [ "$MODE_ENABLE_AUTH" = true ]; then
  render "$HOST_INIT_DIR/jdbc_login_service/jdbc_login"
  render "$HOST_INIT_DIR/auth/jdbc_auth"
fi
# When jdbc-auth-role is active, the security config already points to the JDBC
# auth provider (SECURITY_AUTH_PROVIDER_NAME=jdbc_auth). For jdbc-role-only mode
# it remains "default" (file-based login). No staged override needed.
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

############################################
# JDBC ROLE operations
############################################
docker_cp_dir_if_missing \
  "$HOST_INIT_DIR/jdbc_role_service/jdbc_role" \
  "$GS_SECURITY_DIR/role/jdbc_role"

############################################
# JDBC AUTH operations
############################################
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
# 5️⃣ Manual UI: Test connection + Save → wait for JDBC tables
############################################
echo ""
echo "=================================================="
echo "⚠️  MANUAL STEP REQUIRED ⚠️"
echo "=================================================="
echo "1) Open GeoServer UI"
if [ "$MODE_ENABLE_AUTH" = true ]; then
  echo "2) Security → Role Services → jdbc_role → Test connection → Save"
  echo "3) Security → User Group Services → jdbc_login → Test connection → Save"
else
  echo "2) Security → Role Services → jdbc_role → Test connection → Save"
fi
echo ""
if [ "$MODE_ENABLE_AUTH" = true ]; then
  echo "⏳ Waiting for JDBC ROLE + JDBC AUTH tables..."
else
  echo "⏳ Waiting for JDBC ROLE tables..."
fi
echo "=================================================="
echo "ℹ️  Tip: complete Step 2 first. After role tables are ready, complete Step 3."

# Required tables split by concern for clearer progress logs:
#   JDBC ROLE: roles, user_roles
#   JDBC AUTH: users (only in jdbc-auth-role mode)
ROLE_REQUIRED_TABLES=("roles" "user_roles")
AUTH_REQUIRED_TABLES=()
if [ "$MODE_ENABLE_AUTH" = true ]; then
  AUTH_REQUIRED_TABLES=("users")
fi
REQUIRED_TABLES=("${ROLE_REQUIRED_TABLES[@]}" "${AUTH_REQUIRED_TABLES[@]}")

# Poll until GeoServer has created the expected tables via Test connection.
# Fail fast with diagnostics instead of waiting forever.
TABLE_WAIT_TIMEOUT_SECONDS="${TABLE_WAIT_TIMEOUT_SECONDS:-300}"
TABLE_WAIT_ELAPSED=0
AUTH_TABLE_BOOTSTRAP_AFTER_SECONDS="${AUTH_TABLE_BOOTSTRAP_AFTER_SECONDS:-40}"
AUTH_TABLE_BOOTSTRAP_DONE=false
TABLE_DEBUG_VERBOSE="${TABLE_DEBUG_VERBOSE:-false}"

while true; do
  FOUND=0
  FOUND_ROLE=0
  FOUND_AUTH=0
  TABLES_EXIST=$(
    docker exec -i "$DB_CONTAINER" sh -lc \
    "PGPASSWORD='$PG_GS_PASSWORD' psql -t -A \
      -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
      -U '$PG_GS_USER' -d '$PG_DATABASE' \
      -c \"SELECT schemaname || '|' || tablename FROM pg_tables WHERE schemaname IN ('${ACTIVE_JDBC_SCHEMA}','public');\""
  )

  MISSING_TABLES=()
  MISSING_ROLE_TABLES=()
  MISSING_AUTH_TABLES=()

  for tbl in "${ROLE_REQUIRED_TABLES[@]}"; do
    if echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|$tbl"; then
      FOUND_ROLE=$((FOUND_ROLE+1))
    else
      MISSING_ROLE_TABLES+=("$tbl")
    fi
  done

  for tbl in "${AUTH_REQUIRED_TABLES[@]}"; do
    if echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|$tbl"; then
      FOUND_AUTH=$((FOUND_AUTH+1))
    else
      MISSING_AUTH_TABLES+=("$tbl")
    fi
  done

  FOUND=$((FOUND_ROLE + FOUND_AUTH))
  MISSING_TABLES=("${MISSING_ROLE_TABLES[@]}" "${MISSING_AUTH_TABLES[@]}")

  if [ "$FOUND" -eq "${#REQUIRED_TABLES[@]}" ]; then
    if [ "$MODE_ENABLE_AUTH" = true ]; then
      echo "✅ JDBC ROLE tables detected: ${ROLE_REQUIRED_TABLES[*]}"
      echo "✅ JDBC AUTH tables detected: ${AUTH_REQUIRED_TABLES[*]}"
    else
      echo "✅ JDBC ROLE tables detected: ${ROLE_REQUIRED_TABLES[*]}"
    fi
    break
  fi

  HAS_ROLE_TABLES=false
  HAS_AUTH_USERS=false
  if echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|roles" \
     && echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|user_roles"; then
    HAS_ROLE_TABLES=true
  fi
  if echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|users"; then
    HAS_AUTH_USERS=true
  fi

  # jdbc-auth-role fallback: if role tables exist but auth tables are still missing,
  # bootstrap auth tables automatically to avoid an endless UI wait state.
  if [ "$MODE_ENABLE_AUTH" = true ] \
     && [ "$AUTH_TABLE_BOOTSTRAP_DONE" = false ] \
     && [ "$TABLE_WAIT_ELAPSED" -ge "$AUTH_TABLE_BOOTSTRAP_AFTER_SECONDS" ] \
     && echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|roles" \
     && echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|user_roles" \
     && ! echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|users"; then
    echo "🛠️  Auto-bootstrapping missing JDBC auth tables in '${ACTIVE_JDBC_SCHEMA}'"
    if docker exec -i "$DB_CONTAINER" sh -lc \
      "PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
        -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
        -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL
CREATE TABLE IF NOT EXISTS ${ACTIVE_JDBC_SCHEMA}.users (
  name varchar(128) NOT NULL PRIMARY KEY,
  password varchar(254),
  enabled char(1) NOT NULL
);

CREATE TABLE IF NOT EXISTS ${ACTIVE_JDBC_SCHEMA}.user_props (
  username varchar(128) NOT NULL,
  propname varchar(64) NOT NULL,
  propvalue varchar(2048),
  PRIMARY KEY (username, propname)
);

CREATE INDEX IF NOT EXISTS user_props_idx1 ON ${ACTIVE_JDBC_SCHEMA}.user_props (propname, propvalue);
CREATE INDEX IF NOT EXISTS user_props_idx2 ON ${ACTIVE_JDBC_SCHEMA}.user_props (propname, username);

CREATE TABLE IF NOT EXISTS ${ACTIVE_JDBC_SCHEMA}.groups (
  name varchar(128) NOT NULL PRIMARY KEY,
  enabled char(1) NOT NULL
);

CREATE TABLE IF NOT EXISTS ${ACTIVE_JDBC_SCHEMA}.group_members (
  groupname varchar(128) NOT NULL,
  username varchar(128) NOT NULL,
  PRIMARY KEY (groupname, username)
);

CREATE INDEX IF NOT EXISTS group_members_idx ON ${ACTIVE_JDBC_SCHEMA}.group_members (username, groupname);
SQL
    then
      echo "✅ JDBC auth table bootstrap completed"
      AUTH_TABLE_BOOTSTRAP_DONE=true
      echo "🔁 Re-checking JDBC tables after bootstrap..."
      sleep 2
      continue
    else
      echo "⚠️  JDBC auth table bootstrap failed; continuing wait loop"
    fi
    AUTH_TABLE_BOOTSTRAP_DONE=true
  fi

  if [ "$MODE_ENABLE_AUTH" = true ] \
     && echo "$TABLES_EXIST" | grep -qx "public|users" \
     && ! echo "$TABLES_EXIST" | grep -qx "${ACTIVE_JDBC_SCHEMA}|users"; then
    echo "⚠️  'users' table exists in public, but not in '${ACTIVE_JDBC_SCHEMA}'."
    echo "   This usually means jdbc_login test/save did not create tables in the target schema."
  fi

  if [ "$TABLE_DEBUG_VERBOSE" = "true" ] && [ -n "$TABLES_EXIST" ]; then
    echo "🔎 Visible tables in '${ACTIVE_JDBC_SCHEMA}' and public:"
    echo "$TABLES_EXIST" | sed 's/^/   - /'
  elif [ "$TABLE_DEBUG_VERBOSE" = "true" ]; then
    echo "🔎 No JDBC tables visible yet in '${ACTIVE_JDBC_SCHEMA}' or public"
  fi

  if [ "$HAS_ROLE_TABLES" != "true" ]; then
    echo "➡️  Waiting for Role Service setup."
    echo "   Go to: Security → Role Services → jdbc_role → Test connection → Save"
  elif [ "$MODE_ENABLE_AUTH" = true ] && [ "$HAS_AUTH_USERS" != "true" ]; then
    echo "➡️  Role tables are ready. Now complete User Group setup."
    echo "   Go to: Security → User Group Services → jdbc_login → Test connection → Save"
  fi

  if [ "$MODE_ENABLE_AUTH" = true ]; then
    echo "⏱️  Not ready yet in '${ACTIVE_JDBC_SCHEMA}' — JDBC ROLE: ${FOUND_ROLE}/${#ROLE_REQUIRED_TABLES[@]}, JDBC AUTH: ${FOUND_AUTH}/${#AUTH_REQUIRED_TABLES[@]}"
    if [ "${#MISSING_ROLE_TABLES[@]}" -gt 0 ]; then
      echo "   Missing JDBC ROLE tables: ${MISSING_ROLE_TABLES[*]}"
    fi
    if [ "${#MISSING_AUTH_TABLES[@]}" -gt 0 ]; then
      echo "   Missing JDBC AUTH tables: ${MISSING_AUTH_TABLES[*]}"
    fi
  else
    echo "⏱️  Not ready yet in '${ACTIVE_JDBC_SCHEMA}' — JDBC ROLE: ${FOUND_ROLE}/${#ROLE_REQUIRED_TABLES[@]}"
    if [ "${#MISSING_ROLE_TABLES[@]}" -gt 0 ]; then
      echo "   Missing JDBC ROLE tables: ${MISSING_ROLE_TABLES[*]}"
    fi
  fi

  if [ "$TABLE_WAIT_ELAPSED" -ge "$TABLE_WAIT_TIMEOUT_SECONDS" ]; then
    if [ "$MODE_ENABLE_AUTH" = true ]; then
      echo "❌ Timed out waiting for JDBC ROLE/AUTH tables after ${TABLE_WAIT_TIMEOUT_SECONDS}s"
    else
      echo "❌ Timed out waiting for JDBC ROLE tables after ${TABLE_WAIT_TIMEOUT_SECONDS}s"
    fi
    echo "   Expected schema: ${ACTIVE_JDBC_SCHEMA}"
    if [ "${#MISSING_ROLE_TABLES[@]}" -gt 0 ]; then
      echo "   Missing JDBC ROLE tables: ${MISSING_ROLE_TABLES[*]}"
    fi
    if [ "${#MISSING_AUTH_TABLES[@]}" -gt 0 ]; then
      echo "   Missing JDBC AUTH tables: ${MISSING_AUTH_TABLES[*]}"
    fi
    echo "   Re-run GeoServer UI in this order:"
    echo "   1) Role Services -> jdbc_role -> Test connection -> Save"
    if [ "$MODE_ENABLE_AUTH" = true ]; then
      echo "   2) User Group Services -> jdbc_login -> Test connection -> Save"
    fi
    exit 1
  fi

  sleep 10
  TABLE_WAIT_ELAPSED=$((TABLE_WAIT_ELAPSED + 10))
done

############################################
# 6️⃣ Seed roles
############################################
############################################
# JDBC ROLE operations
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

############################################
# JDBC AUTH operations
############################################
if [ "$MODE_ENABLE_AUTH" = true ] && [ "$APPLY_JDBC_AUTH_PROVIDER" = true ]; then
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
  }' 2>&1
")
  CURL_EXIT=$?

  if [ "$CURL_EXIT" -ne 0 ]; then
    echo "❌ curl request failed while creating JDBC user (exit $CURL_EXIT)"
    echo "$RESPONSE"
    exit 1
  fi

  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if ! echo "$HTTP_CODE" | grep -Eq '^[0-9]{3}$'; then
    echo "❌ Could not parse HTTP status from JDBC user create response"
    echo "$RESPONSE"
    exit 1
  fi

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
############################################
# JDBC ROLE operations
############################################
echo "🔗 Assigning ADMIN role to ${ADMIN_USER}"
if [ "$MODE_ENABLE_AUTH" = true ] && [ "$APPLY_JDBC_AUTH_PROVIDER" = true ]; then
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

echo "🔄 Restarting DB + GeoServer to apply JDBC changes..."
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

if [ "$MODE_ENABLE_AUTH" = true ]; then
  echo "🔍 Running JDBC ROLE + JDBC AUTH validation..."
else
  echo "🔍 Running JDBC ROLE validation..."
fi
if [ "$MODE_ENABLE_AUTH" = true ]; then
  JDBC_VALIDATE_SCOPE="auto"
else
  JDBC_VALIDATE_SCOPE="role"
fi

if ! docker compose -f "$COMPOSE_FILE" exec \
  -e JDBC_VALIDATE_SCOPE="$JDBC_VALIDATE_SCOPE" \
  -e JDBC_VALIDATE_REQUIRE_ACTIVE_ROLE=false \
  geoserver python3 /scripts/geoserver_validate_jdbc.py; then
  echo "❌ JDBC validation failed"
  exit 1
fi

echo ""
echo "🎉 Setup complete!"
