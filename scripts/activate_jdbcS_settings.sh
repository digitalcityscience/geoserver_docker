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
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
HOST_INIT_DIR="${HOST_INIT_DIR:-./docker/geoserver-init}"
GS_SECURITY_DIR="${GS_SECURITY_DIR:-/geoserver_data/data/security}"
GS_URL="${GS_URL:-http://localhost:8080/geoserver}"
ADMIN_USER="${GEOSERVER_ADMIN_USER:-admin}"
ADMIN_PASS="${GEOSERVER_ADMIN_PASSWORD:-geoserver}"

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
render "$HOST_INIT_DIR/jdbc_login_service/jdbc_login"
render "$HOST_INIT_DIR/jdbc_role_service/jdbc_role"
render "$HOST_INIT_DIR/auth/jdbc_auth"
envsubst < "$HOST_INIT_DIR/security/config.xml.template" \
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
  "$HOST_INIT_DIR/jdbc_login_service/jdbc_login" \
  "$GS_SECURITY_DIR/usergroup/jdbc_login"

docker_cp_dir_if_missing \
  "$HOST_INIT_DIR/jdbc_role_service/jdbc_role" \
  "$GS_SECURITY_DIR/role/jdbc_role"

docker_cp_dir_if_missing \
  "$HOST_INIT_DIR/auth/jdbc_auth" \
  "$GS_SECURITY_DIR/auth/jdbc_auth"

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
echo "2) Security → User Group Services → jdbc_login → Test connection → Save"
echo "3) Security → Role Services → jdbc_role → Test connection → Save"
echo ""
echo "⏳ Waiting for JDBC tables..."
echo "=================================================="

REQUIRED_TABLES=("roles" "users" "user_roles")

while true; do
  FOUND=0
  TABLES_EXIST=$(
    docker exec -i "$DB_CONTAINER" sh -lc \
    "PGPASSWORD='$PG_GS_PASSWORD' psql -t -A \
      -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
      -U '$PG_GS_USER' -d '$PG_DATABASE' \
      -c \"SELECT tablename FROM pg_tables WHERE schemaname='${PG_SCHEMA_GEOSERVER}';\""
  )

  for tbl in "${REQUIRED_TABLES[@]}"; do
    if echo "$TABLES_EXIST" | grep -qx "$tbl"; then
      FOUND=$((FOUND+1))
    fi
  done

  if [ "$FOUND" -eq "${#REQUIRED_TABLES[@]}" ]; then
    echo "✅ JDBC tables detected: ${REQUIRED_TABLES[*]}"
    break
  fi
  echo "⏱️  Not ready yet… waiting 10s"
  sleep 10
done

############################################
# 6️⃣ Seed roles
############################################
echo "🧬 Seeding roles"
docker exec -i "$DB_CONTAINER" sh -lc \
"PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
 -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
 -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

INSERT INTO ${PG_SCHEMA_GEOSERVER}.roles (name, parent)
VALUES
  ('ADMIN','ROLE_ADMINISTRATOR'),
  ('GROUP_ADMIN','ROLE_GROUP_ADMIN')
ON CONFLICT DO NOTHING;
SQL

############################################
# 7️⃣ Create admin user via REST (FIXED)
############################################
# from .env (fallback)
JDBC_LOGIN_SERVICE_NAME="${JDBC_LOGIN_SERVICE_NAME:-jdbc_login}"

# IMPORTANT: this runs INSIDE the geoserver container, so localhost is correct
USER_API="http://localhost:8080/geoserver/rest/security/usergroup/service/${JDBC_LOGIN_SERVICE_NAME}/users"

echo "👤 Creating user '${ADMIN_USER}' via ${JDBC_LOGIN_SERVICE_NAME}..."

RESPONSE=$(docker exec "$GEOSERVER_CONTAINER" sh -lc "
curl -s -w '\n%{http_code}' \
  -u \"admin:geoserver\" \
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
  401)
    echo "❌ Authentication failed (HTTP 401) - master admin:geoserver rejected"
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

############################################
# 8️⃣ Assign role to admin
############################################
echo "🔗 Assigning ADMIN role to ${ADMIN_USER}"
docker exec -i "$DB_CONTAINER" sh -lc \
"PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
 -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
 -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

INSERT INTO ${PG_SCHEMA_GEOSERVER}.user_roles (username, rolename)
VALUES ('${ADMIN_USER}','ADMIN')
ON CONFLICT DO NOTHING;

-- Verify
SELECT 
  u.name        AS username,
  u.enabled,
  ur.rolename
FROM ${PG_SCHEMA_GEOSERVER}.users u
LEFT JOIN ${PG_SCHEMA_GEOSERVER}.user_roles ur
  ON ur.username = u.name
WHERE u.name = '${ADMIN_USER}';
SQL

############################################
# 9️⃣ Activate JDBCConfig
############################################
echo "⚙️  Activating JDBCConfig"
JDBCCONFIG_HOST_SCRIPT="$HOST_INIT_DIR/jdbcConfig/activate_jdbcConfig.sh"
JDBCCONFIG_CONTAINER_SCRIPT="/tmp/activate_jdbcConfig.sh"

docker cp \
  "$JDBCCONFIG_HOST_SCRIPT" \
  "$GEOSERVER_CONTAINER:$JDBCCONFIG_CONTAINER_SCRIPT"

docker exec "$GEOSERVER_CONTAINER" sh -lc \
  "chmod +x '$JDBCCONFIG_CONTAINER_SCRIPT' && '$JDBCCONFIG_CONTAINER_SCRIPT'"

############################################
# 🔟 Reload GeoServer
############################################
echo "🔄 Reloading GeoServer"
if ! docker exec "$GEOSERVER_CONTAINER" sh -lc \
  "curl -sf -u \"admin:geoserver\" -X POST \"${GS_URL}/rest/reload\""; then
  echo "❌ GeoServer reload failed!"
  exit 1
fi

read -p "User setup is complete. Do you want to restart GeoServer now to apply changes? (y/n): " RESTART_ANSWER
if [[ "$RESTART_ANSWER" =~ ^[Yy]$ ]]; then
  echo "Restarting GeoServer for changes to take effect..."
  docker compose -f "$COMPOSE_FILE" restart geoserver
else
  echo "Restart skipped. Changes will take effect on the next restart."
fi

echo ""
echo "🎉 Setup complete!"