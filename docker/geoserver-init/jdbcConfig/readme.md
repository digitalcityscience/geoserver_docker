# JDBCConfig / JDBCStore Notes

`jdbc-config` is an advanced opt-in mode. It is intentionally separate from
`default`, `jdbc-role`, and `jdbc-auth-role` because it can move GeoServer
catalog/configuration state out of file-backed XML and into PostgreSQL.

Current implementation:

- `jdbcconfig` is supported only when `GEOSERVER_SECURITY_MODE=jdbc-config`.
- `GEOSERVER_ENABLE_JDBC_CONFIG=true` is required.
- `COMMUNITY_PLUGINS` must include `jdbcconfig`.
- `PG_SCHEMA_JDBCCONF` must be separate from `PG_SCHEMA_GEOSERVER`.
- Proxy settings are applied through GeoServer REST, not by editing `global.xml`.

Run example:

```bash
GEOSERVER_SECURITY_MODE=jdbc-config \
GEOSERVER_ENABLE_JDBC_CONFIG=true \
ENABLE_JDBC_CONFIG=true \
COMMUNITY_PLUGINS=sec-oidc,jdbcconfig \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

`jdbcstore` remains future work and is not wired into the default startup path.
