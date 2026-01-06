#!/bin/sh
set -e

echo "=== JDBCConfig bootstrap (original) ==="

GEOSERVER_DATA_DIR="${GEOSERVER_DATA_DIR:-/geoserver_data/data}"
CFG="${GEOSERVER_DATA_DIR}/jdbcconfig/jdbcconfig.properties"

[ "${ENABLE_JDBC_CONFIG}" != "true" ] && exit 0
[ ! -f "$CFG" ] && exit 1

# enable JDBCConfig
sed -i 's/^enabled=.*/enabled=true/' "$CFG"

# import file-based config into DB (GeoServer expects this)
sed -i 's/^import=.*/import=false/' "$CFG"

# let GeoServer create tables
sed -i 's/^initdb=.*/initdb=true/' "$CFG"

# JDBC connection
sed -i "s|^jdbcUrl=.*|jdbcUrl=jdbc:postgresql://${PG_HOST}:${PG_DOCKER_PORT}/${PG_DATABASE}?currentSchema=${PG_SCHEMA_JDBCCONF}|" "$CFG"
sed -i "s/^username=.*/username=${PG_GS_USER}/" "$CFG"
sed -i "s/^password=.*/password=${PG_GS_PASSWORD}/" "$CFG"

echo "=== JDBCConfig bootstrap DONE ==="