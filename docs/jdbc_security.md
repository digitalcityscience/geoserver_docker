# JDBC Security Asset Ownership

The Phase 2 cleanup keeps the existing JDBC assets and assigns them to explicit runtime modes. This avoids duplicating the current JDBC implementation while making the future split easier to review.

## Assets

| Path | Owner mode | Notes |
| --- | --- | --- |
| `docker/geoserver-init/jdbc_role_service/jdbc_role/config.xml.template` | `jdbc-role`, `jdbc-auth-role` | Primary JDBC role service template. |
| `docker/geoserver-init/jdbc_role_service/jdbc_role/rolesddl.xml` | `jdbc-role`, `jdbc-auth-role` | Role schema definition. |
| `docker/geoserver-init/jdbc_role_service/jdbc_role/rolesdml.xml` | `jdbc-role`, `jdbc-auth-role` | Role seed data. |
| `docker/geoserver-init/jdbc_login_service/jdbc_login/config.xml.template` | `jdbc-auth-role` | JDBC user/group service template. |
| `docker/geoserver-init/jdbc_login_service/jdbc_login/usersddl.xml` | `jdbc-auth-role` | User/group schema definition. |
| `docker/geoserver-init/jdbc_login_service/jdbc_login/usersdml.xml` | `jdbc-auth-role` | User/group seed data. |
| `docker/geoserver-init/auth/jdbc_auth/config.xml.template` | `jdbc-auth-role` | JDBC authentication provider template. |
| `docker/geoserver-init/security/config.xml.template` | `jdbc-auth-role` source material | Existing full security template assumes JDBC auth and must not be used as default mode config. |
| `scripts/activate_jdbcS_settings.sh` | compatibility wrapper | Keep temporarily, then split into smaller mode-specific helpers. |
| `docker/initdb/init001.sh` | JDBC-enabled compose variants | PostgreSQL schema/user bootstrap. |
| `docker/geoserver-init/jdbcConfig/activate_jdbcConfig.sh` | `jdbc-config` | Advanced catalog backend activation. |
| `docker/geoserver-init/jdbcConfig/activate_jdbcStore.sh` | future advanced mode | Keep present but do not run by default. |

## Cleanup Notes

- Do not create new JDBC login, role, or auth provider templates from scratch.
- Do not create a second database bootstrap script.
- Do not create another all-in-one JDBC activation script.
- Keep `jdbc-role` as the first JDBC mode to implement because it has the smallest blast radius.

## Phase 10: JDBC Role Mode

`jdbc-role` keeps GeoServer users and groups in the default file-backed XML service and activates only the JDBC role service.

Startup behavior:

- `scripts/geoserver_configure_jdbc_security.py` runs after admin credentials are bootstrapped.
- The existing role template is rendered into `GEOSERVER_DATA_DIR/security/role/${GS_ROLE_SERVICE_NAME}`.
- `rolesddl.xml` and `rolesdml.xml` are copied beside the rendered role service config.
- Required role tables are created in `PG_SCHEMA_GEOSERVER` when missing.
- `GS_ADMIN_ROLE`, `GS_GROUP_ADMIN_ROLE`, and optional `GEOSERVER_JDBC_EXTRA_ROLES` are seeded.
- `GEOSERVER_ADMIN_USER` is mapped to `GS_ADMIN_ROLE`.
- If `GEOSERVER_ADMIN_USER` is changed from `admin`, the built-in `admin` user is disabled by default after the configured admin user is created.
- `security/config.xml` is updated so `roleServiceName` points to the JDBC role service.
- GeoServer is reloaded and REST credentials are checked after the role switch.

Run example:

```bash
GEOSERVER_SECURITY_MODE=jdbc-role \
GEOSERVER_ENABLE_JDBC_ROLE=true \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

Validation:

```bash
docker-compose --env-file .env.dev -f docker-compose-dev.yml exec geoserver \
  python3 /scripts/geoserver_validate_jdbc.py
```

Rollback:

- Set `GEOSERVER_SECURITY_MODE=default`.
- Set `GEOSERVER_ENABLE_JDBC_ROLE=false`.
- Restart GeoServer.
- File-backed users remain in place because `jdbc-role` does not replace the default user/group service.

## Phase 11: JDBC Auth + Role Mode

`jdbc-auth-role` stores GeoServer users/groups and roles in PostgreSQL. It still keeps the GeoServer catalog/config file-backed and does not enable JDBCConfig/JDBCStore.

Startup behavior:

- The Phase 10 JDBC role service bootstrap still runs.
- `scripts/geoserver_configure_jdbc_security.py` also renders:
  - `docker/geoserver-init/jdbc_login_service/jdbc_login/config.xml.template`
  - `docker/geoserver-init/auth/jdbc_auth/config.xml.template`
- `usersddl.xml` and `usersdml.xml` are copied beside the rendered user/group service config.
- Required user/group tables are created when missing.
- GeoServer is reloaded while file-backed admin credentials are still active so the JDBC user/group service is discoverable through REST.
- `GEOSERVER_ADMIN_USER` is created or updated through the GeoServer REST API in the JDBC user/group service. This lets GeoServer encode the password instead of writing plaintext SQL.
- Role seed and admin role mappings are verified in PostgreSQL.
- Only after the JDBC services and admin user are verified, `security/config.xml` is updated to use:
  - `roleServiceName=${GS_ROLE_SERVICE_NAME}`
  - `authProviderNames=${JDBC_AUTH_SERVICE_NAME}`
- GeoServer is reloaded again and REST login is validated with the configured admin credentials.

Run example:

```bash
GEOSERVER_SECURITY_MODE=jdbc-auth-role \
GEOSERVER_ENABLE_JDBC_ROLE=true \
GEOSERVER_ENABLE_JDBC_AUTH=true \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

Validation:

```bash
docker-compose --env-file .env.dev -f docker-compose-dev.yml exec geoserver \
  python3 /scripts/geoserver_validate_jdbc.py
```

Rollback:

- Preferred safe rollback for a test deployment is to set `GEOSERVER_SECURITY_MODE=default`, set all JDBC flags to `false`, and recreate the GeoServer data volume from a known-good backup or fresh default-mode boot.
- If you need to keep the existing volume, restore `GEOSERVER_DATA_DIR/security/config.xml` so `roleServiceName` points to `default` and `authProviderNames` contains the default provider before restarting.
- Keep PostgreSQL schemas intact until default REST login has been verified; they can be reused when returning to `jdbc-auth-role`.

## Phase 12: JDBCConfig Mode

`jdbc-config` is an advanced catalog/config mode. It is not a security mode and it should not be enabled just to get JDBC roles or JDBC users.

Startup behavior:

- `GEOSERVER_SECURITY_MODE=jdbc-config` forces `GEOSERVER_ENABLE_JDBC_CONFIG=true` in the entrypoint.
- `scripts/geoserver_configure_jdbc_config.py` only runs in `jdbc-config` mode.
- `PG_SCHEMA_JDBCCONF` is required and must be different from `PG_SCHEMA_GEOSERVER`.
- The script updates `GEOSERVER_DATA_DIR/jdbcconfig/jdbcconfig.properties`.
- `enabled=true`, `initdb=true`, and the PostgreSQL JDBC URL are written idempotently.
- `GEOSERVER_JDBC_CONFIG_IMPORT=false` is the default to avoid repeated implicit imports on restart.
- Proxy settings continue to be applied through REST after startup.

Run example:

```bash
GEOSERVER_SECURITY_MODE=jdbc-config \
GEOSERVER_ENABLE_JDBC_CONFIG=true \
ENABLE_JDBC_CONFIG=true \
COMMUNITY_PLUGINS=sec-oidc,jdbcconfig \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

Validation:

```bash
docker-compose --env-file .env.dev -f docker-compose-dev.yml exec geoserver \
  python3 /scripts/geoserver_validate_jdbc.py
```

Migration notes:

- First validate default mode with a clean file-backed data directory.
- Back up the GeoServer data volume and PostgreSQL database before enabling `jdbc-config`.
- Enable `jdbc-config` only in a test deployment first.
- Treat `global.xml` as possibly non-authoritative after JDBCConfig is enabled.
- Roll back by restoring the file-backed data volume backup and setting `GEOSERVER_SECURITY_MODE=default`, `GEOSERVER_ENABLE_JDBC_CONFIG=false`, and `ENABLE_JDBC_CONFIG=false`.
