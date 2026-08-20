#!/bin/bash
set -e

############################################
# ENV
############################################
GS_USER="${PG_GS_USER:-geoserver}"
GS_PASS="${PG_GS_PASSWORD:-postgres_gs}"

SCHEMA_GS="${PG_SCHEMA_GEOSERVER:-gs_auth_role_schema}"
SCHEMA_GIS="${PG_SCHEMA_GIS:-gis_schema}"
SCHEMA_JDBCCONF="${PG_SCHEMA_JDBCCONF:-gs_jdbcconfig_schema}"

echo "Initializing database schemas:"
echo "  GeoServer  -> $SCHEMA_GS"
echo "  JDBCConfig -> $SCHEMA_JDBCCONF"
echo "  GIS        -> $SCHEMA_GIS"

echo "Creating users:"
echo "  GeoServer user -> $GS_USER"

############################################
# INIT
############################################
psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" <<-EOSQL

-- 0) PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1) Schemas
CREATE SCHEMA IF NOT EXISTS $SCHEMA_GS;
CREATE SCHEMA IF NOT EXISTS $SCHEMA_JDBCCONF;
CREATE SCHEMA IF NOT EXISTS $SCHEMA_GIS;

-- 2) Roles
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$GS_USER') THEN
    CREATE ROLE $GS_USER LOGIN PASSWORD '$GS_PASS';
  END IF;
END
\$\$;

-- 3) Permissions
GRANT ALL ON SCHEMA $SCHEMA_GS       TO $GS_USER;
GRANT ALL ON SCHEMA $SCHEMA_JDBCCONF TO $GS_USER;

GRANT USAGE ON SCHEMA $SCHEMA_GIS TO $GS_USER;

-- 4) search_path (KRİTİK)
ALTER ROLE $GS_USER  SET search_path = $SCHEMA_GS, $SCHEMA_JDBCCONF, public;

-- 5) public / PostGIS permissions (GeoServer için şart)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $GS_USER;
GRANT SELECT ON spatial_ref_sys TO $GS_USER;

GRANT CREATE ON SCHEMA public TO $GS_USER;
GRANT ALL ON ALL TABLES    IN SCHEMA public TO $GS_USER;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO $GS_USER;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO $GS_USER;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO $GS_USER;

EOSQL

echo "Database initialization completed successfully."
