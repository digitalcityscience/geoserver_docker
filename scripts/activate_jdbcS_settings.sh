# bu script bir sekilde patladi. aslinda su burada olusturdugumuz admin kullanicisi reader
# olarak olusturulkdu. normal bu sorunu cozmustuk. jdbc auth ile sistemi kurunca hallediyorduk.
# ama simdi yine patladi.

#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
ENV_FILE="${ENV_FILE:-.env.dev}"

HOST_INIT_DIR="${HOST_INIT_DIR:-./docker/geoserver-init}"
GS_SECURITY_DIR="${GS_SECURITY_DIR:-/geoserver_data/data/security}"

GS_URL="${GS_URL:-http://localhost:8080/geoserver}"
ADMIN_USER="${GEOSERVER_ADMIN_USER:-admin}"
ADMIN_PASS="${GEOSERVER_ADMIN_PASSWORD:-geoserver}"

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
# 1️⃣ Detect containers from compose
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
# 2️⃣ Render templates on HOST
############################################
render() {
  local DIR="$1"
  envsubst < "$DIR/config.xml.template" > "$DIR/config.xml"
}

echo "🧩 Rendering templates (HOST)"

render "$HOST_INIT_DIR/jdbc_login_service/jdbc_login"
render "$HOST_INIT_DIR/jdbc_role_service/jdbc_role"
render "$HOST_INIT_DIR/auth/jdbc_auth"
envsubst < "$HOST_INIT_DIR/security/config.xml.template" \
        > "$HOST_INIT_DIR/security/config.xml"

############################################
# 3️⃣ Copy security artifacts into volume
############################################
docker_cp_dir_if_missing () {
  docker exec "$GEOSERVER_CONTAINER" sh -lc "[ -d '$2' ]" && return
  docker exec "$GEOSERVER_CONTAINER" sh -lc "mkdir -p '$(dirname "$2")'"
  docker cp "$1" "$GEOSERVER_CONTAINER:$2"
}

docker_cp_file_overwrite () {
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
# 4️⃣ USER ACTION REQUIRED (INTENTIONAL)
############################################
############################################
# 4️⃣ USER ACTION REQUIRED + DB POLLING
############################################
echo ""
echo "=================================================="
echo "⚠️  MANUAL STEP REQUIRED (ONCE)"
echo "=================================================="
echo "1) Open GeoServer UI"
echo "2) Security → User Group Services → jdbc_login → Test connection → Save"
echo "3) Security → Role Services → jdbc_role → Test connection → Save"
echo ""
echo "⏳ Waiting for GeoServer to create JDBC tables..."
echo "   (checking every 10 seconds)"
echo "=================================================="

# Required tables
REQUIRED_TABLES=("roles")

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
# 5️⃣ Verify DB tables now exist
############################################
echo "🔎 Checking JDBC tables created by GeoServer"

docker exec -i "$DB_CONTAINER" sh -lc \
"PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
 -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
 -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

SELECT tablename
FROM pg_tables
WHERE schemaname='${PG_SCHEMA_GEOSERVER}';
SQL

############################################
# 7️⃣ Create admin user via JDBC REST
############################################
echo "👤 Ensuring admin user via JDBC REST"

docker exec "$GEOSERVER_CONTAINER" sh -lc "
curl -sf -u '${ADMIN_USER}:${ADMIN_PASS}' \
  -X POST -H 'Content-Type: application/json' \
  '${GS_URL}/rest/security/usergroup/service/${JDBC_LOGIN_SERVICE_NAME}/users' \
  -d '{
    \"user\": {
      \"userName\": \"admin\",
      \"password\": \"geoserver\",
      \"enabled\": true
    }
  }' || echo 'admin already exists'
"
############################################
# 6️⃣ Seed roles + admin mapping
############################################
echo "🧬 Seeding roles and admin mapping"

docker exec -i "$DB_CONTAINER" sh -lc \
"PGPASSWORD='$PG_GS_PASSWORD' psql -v ON_ERROR_STOP=1 \
 -h '${PG_HOST:-db}' -p '${PG_DOCKER_PORT:-5432}' \
 -U '$PG_GS_USER' -d '$PG_DATABASE'" <<SQL

INSERT INTO ${PG_SCHEMA_GEOSERVER}.roles (name, parent)
VALUES ('ADMIN','ADMIN'), ('GROUP_ADMIN','GROUP_ADMIN')
ON CONFLICT DO NOTHING;

INSERT INTO ${PG_SCHEMA_GEOSERVER}.user_roles (username, rolename)
VALUES ('admin','ADMIN')
ON CONFLICT DO NOTHING;
SQL

############################################
# 8️⃣ Activate JDBC Config (inside container)
############################################
echo "⚙️  Activating JDBCConfig inside GeoServer container"

JDBCCONFIG_HOST_SCRIPT="$HOST_INIT_DIR/jdbcConfig/activate_jdbcConfig.sh"
JDBCCONFIG_CONTAINER_SCRIPT="/tmp/activate_jdbcConfig.sh"

# copy script into container
docker cp \
  "$JDBCCONFIG_HOST_SCRIPT" \
  "$GEOSERVER_CONTAINER:$JDBCCONFIG_CONTAINER_SCRIPT"

# ensure executable
docker exec "$GEOSERVER_CONTAINER" sh -lc \
  "chmod +x '$JDBCCONFIG_CONTAINER_SCRIPT'"

# run script inside container (with env already available)
docker exec "$GEOSERVER_CONTAINER" sh -lc \
  "'$JDBCCONFIG_CONTAINER_SCRIPT'"

############################################
# 9️⃣ Reload GeoServer
############################################
echo "🔄 Reloading GeoServer"
docker exec "$GEOSERVER_CONTAINER" sh -lc \
"curl -sf -u '${ADMIN_USER}:${ADMIN_PASS}' -X POST '${GS_URL}/rest/reload' || true"

############################################
# DONE
############################################
echo ""
echo "✅ GeoServer JDBC security fully bootstrapped"
sleep 10
docker compose -f $COMPOSE_FILE restart geoserver