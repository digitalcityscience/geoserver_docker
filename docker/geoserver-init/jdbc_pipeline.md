GeoServer JDBC Security Bootstrap — Short Steps

1. Load env
   Load .env.dev on the host to get DB/JDBC variables.
2. Detect containers
   Auto-detect geoserver and db containers via docker compose.
3. Render configs (host)
   Render all config.xml.template files with envsubst:
   • jdbc_login
   • jdbc_role
   • jdbc_auth
   • security/config.xml
4. Copy to volume
   Copy rendered security folders/files into GeoServer’s security volume using docker cp.
5. Manual UI step (once)
   In GeoServer UI:
   • jdbc_login → Test connection → Save
   • jdbc_role → Test connection → Save
6. Wait for DB tables
   Script polls PostGIS until JDBC tables are created.
7. Create admin user (REST)
   Create/ensure admin user in jdbc_login via GeoServer REST.
8. Seed roles (DB)
   Insert roles (ADMIN, GROUP_ADMIN) and map admin → ADMIN.
9. Reload GeoServer
   Call POST /rest/reload to apply security changes.
10. Optional restart
    docker compose restart geoserver if needed.
