# GeoServer Runtime Modes

This document records the runtime mode names chosen during the Phase 2 cleanup. The implementation is intentionally incremental: existing JDBC assets remain in place, and mode-specific wiring is handled in later phases.

## Mode Names

| Mode | Purpose | Database required | Phase 2 ownership |
| --- | --- | --- | --- |
| `default` | File-backed GeoServer configuration and XML security. | No | Keep as the production default path. |
| `jdbc-role` | File-backed GeoServer users with JDBC role service only. | Yes | Reuse `docker/geoserver-init/jdbc_role_service/jdbc_role/`. |
| `jdbc-auth-role` | JDBC user/group service plus JDBC role service. | Yes | Reuse JDBC login, auth provider, and role templates. |
| `jdbc-config` | Full JDBCConfig/JDBCStore catalog backend. | Yes | Keep advanced and disabled unless explicitly enabled. |

## Default Mode Rules

- Do not require PostgreSQL.
- Do not generate JDBC security files.
- Do not create a `jdbcconfig` directory.
- Keep `global.xml` and security XML file-backed in `GEOSERVER_DATA_DIR`.
- Keep CORS, proxy settings, health checks, admin credential bootstrap, plugin installation, and production validation available.

## JDBC Mode Rules

- JDBC files are present in the image/repository but inactive unless a JDBC mode is selected.
- Existing templates remain the source of truth.
- Rendered `config.xml` files should not become authoritative when a matching `.template` file exists.
- `jdbc-config` is advanced because it can move catalog and global settings out of file-backed XML.
