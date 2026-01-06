#!/bin/sh
set -e

GEOSERVER_DATA_DIR="${GEOSERVER_DATA_DIR:-/geoserver_data/data}"
CFG="${GEOSERVER_DATA_DIR}/jdbcstore/jdbcstore.properties"

# Feature flag
[ "${ENABLE_JDBCSTORE}" != "true" ] && exit 0

# Guard
[ ! -f "$CFG" ] && echo "[JDBCSTORE] jdbcstore.properties not found, skipping" && exit 0

echo "[JDBCSTORE] Activating JDBCStore (minimal)"

# --- Safe defaults ---
sed -i 's/^enabled=.*/enabled=true/' "$CFG"
sed -i 's/^import=.*/import=false/' "$CFG"     # NEVER auto-import on restart
sed -i 's/^initdb=.*/initdb=true/' "$CFG"      # create tables if missing

# --- DB connection (Docker internal) ---
: "${PG_HOST:?PG_HOST is required}"
: "${PG_DOCKER_PORT:=5432}"
: "${PG_DATABASE:?PG_DATABASE is required}"
: "${PG_SCHEMA_GEOSERVER:?PG_SCHEMA_GEOSERVER is required}"
: "${PG_GS_USER:?PG_GS_USER is required}"
: "${PG_GS_PASSWORD:?PG_GS_PASSWORD is required}"

sed -i "s|^jdbcUrl=.*|jdbcUrl=jdbc:postgresql://${PG_HOST}:${PG_DOCKER_PORT}/${PG_DATABASE}?currentSchema=${PG_SCHEMA_GEOSERVER}|" "$CFG"
sed -i "s/^username=.*/username=${PG_GS_USER}/" "$CFG"
sed -i "s/^password=.*/password=${PG_GS_PASSWORD}/" "$CFG"

echo "[JDBCSTORE] JDBCStore ready"