# Production-Grade GeoServer Setup (PostgreSQL / JDBC)

Current implementation status:

- `default` mode is the recommended production path while JDBC modes are introduced incrementally.
- `jdbc-role` is implemented first and keeps users/groups file-backed while roles are stored in PostgreSQL.
- `jdbc-auth-role` is available after `jdbc-role` and stores users/groups plus roles in PostgreSQL.
- `jdbc-config` is an advanced explicit mode for catalog/config persistence and should not be enabled as the default production path.

To start the implemented JDBC role mode:

```bash
GEOSERVER_SECURITY_MODE=jdbc-role \
GEOSERVER_ENABLE_JDBC_ROLE=true \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

Validate it from inside the GeoServer container:

```bash
docker-compose --env-file .env.dev -f docker-compose-dev.yml exec geoserver \
  python3 /scripts/geoserver_validate_jdbc.py
```

To start JDBC auth + role mode:

```bash
GEOSERVER_SECURITY_MODE=jdbc-auth-role \
GEOSERVER_ENABLE_JDBC_ROLE=true \
GEOSERVER_ENABLE_JDBC_AUTH=true \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

To start advanced JDBCConfig mode:

```bash
GEOSERVER_SECURITY_MODE=jdbc-config \
GEOSERVER_ENABLE_JDBC_CONFIG=true \
ENABLE_JDBC_CONFIG=true \
COMMUNITY_PLUGINS=sec-oidc,jdbcconfig \
docker-compose --env-file .env.dev -f docker-compose-dev.yml up -d --build db geoserver
```

Use `PG_SCHEMA_JDBCCONF` for JDBCConfig data and keep it separate from `PG_SCHEMA_GEOSERVER`.
In this mode, `global.xml` may no longer be the authoritative source for all settings; proxy settings are applied through REST after startup.

The older all-in-one manual procedure below is kept as historical guidance for full JDBC security/config work. Prefer the explicit mode flags above for the implemented `jdbc-role` and `jdbc-auth-role` paths.

This setup replaces GeoServer’s default XML-based security and configuration with a PostgreSQL-backed (JDBC) system.

Result:
• Users, roles, and config are stored in PostgreSQL
• Settings survive container restarts
• XML-based security is fully disabled
• Ready for Keycloak / OIDC integration

## UI Activation Procedure

> **Note**: Despite correct backend configuration, GeoServer requires explicit UI activation. This is a mandatory step, not an optional convenience.

### Step 0 : Run Script

This script prepares JDBC security and config services.

##### Before running, ensure GeoServer containers are up. Please go to Geoserver URL (e.g. http://localhost:8080/geoserver) and confirm it is running.

**Linux / macOS**

> chmod +x ./scripts/activate_jdbcS_settings.sh
> ENV_FILE=.env.prod ./scripts/activate_jdbcS_settings.sh

If you want development values instead:

> ENV_FILE=.env.dev ./scripts/activate_jdbcS_settings.sh

> Important: Do not use `$ENV_FILE=.env.prod` (with `$` at the beginning). Use `ENV_FILE=.env.prod`.

**Windows**

Use Git Bash or WSL:

> bash ./scripts/activate_jdbcS_settings.sh

### Step 1: Activate JDBC Login Service

1. Navigate to: **Security → User Group Services → jdbc_login**
2. Select the **Settings** tab
3. **Critical UI Behavior Note**: The _Driver Class Name_ field may initially appear empty
   - This is expected behavior due to GeoServer's lazy initialization
   - **Resolution**: Click the **Users** tab, then return to **Settings**
   - The driver class should now auto-populate
4. Click **Test Connection**
   - ✅ **Expected Result**: Green success message confirming database connectivity
5. Click **Save**
   - ⚠️ **Warning**: Test Connection alone is insufficient; Save action commits configuration

### Step 2: Activate JDBC Role Service

1. Navigate to: **Security → Role Services → jdbc_role**
2. Verify _Driver Class Name_ is populated (typically appears immediately)
3. Click **Test Connection**
   - ❌ **If connection fails**:
     - Navigate to any other GeoServer menu item
     - Return to Role Services
     - Retry Test Connection
4. Upon successful connection (green message), click **Save**

### Step 3: Configure Administrator Roles

> **Critical Security Step**: XML-defined roles require explicit UI mapping.

1. Remain in **Security → Role Services → jdbc_role**
2. In the **Administrator Roles** section:
   - Set **Administrator role** to: `ADMIN`
   - Set **Group administrator role** to: `GROUP_ADMIN`
3. Click **Save**
4. **Validation**: Navigate away and return to verify selections persist

### Step 4: Apply Configuration Changes

1. After saving Role Services, a restart prompt will appear in the terminal.
2. Press **y** to confirm restart
3. Allow the GeoServer container to complete restart cycle

> **Why restart is mandatory**: This reloads the security chain with JDBC-backed authentication providers and activates the configuration persistence layer.

⸻

1. Result
   • Credentials defined in .env are now stored in PostgreSQL
   • XML-based security is disabled
   • GeoServer runs fully JDBC-backed
   • Keycloak / OIDC integration can now be added safely

⸻

⚠️ Important
Do not edit JDBC tables manually.
Use GeoServer UI or REST API only.

---

## Executive Summary

This documentation describes a production-ready GeoServer configuration that leverages PostgreSQL as the persistent backend for **both security management and server configuration**. This architecture eliminates file-based dependencies, ensures configuration persistence across container restarts, and provides enterprise-grade reliability for cloud (AWS), on-premises, or Docker deployments.

> **Key Benefit**: Single source of truth in PostgreSQL replaces fragile file-based configurations, enabling true production resilience.

---

## Architecture Overview

### Dual-Schema Design Pattern

This setup implements a strict separation of concerns using two dedicated PostgreSQL schemas:

| Component                   | Schema Name            | Purpose                          | Data Types                                                 |
| --------------------------- | ---------------------- | -------------------------------- | ---------------------------------------------------------- |
| **Security Management**     | `gs_auth_role_schema`  | Authentication and authorization | Users, groups, roles, permissions, relationships           |
| **GeoServer Configuration** | `gs_jdbcconfig_schema` | Server configuration persistence | Workspaces, datastores, layers, styles, services, settings |

> **⚠️ Critical Design Principle**: These schemas **MUST** remain separate. Mixing security and configuration data creates lifecycle conflicts, security vulnerabilities, and maintenance complexity.

### Why This Architecture Matters

After successful implementation:

- ✅ **No file-based dependencies**: All critical data resides in PostgreSQL
- ✅ **Configuration persistence**: Container restarts preserve all settings
- ✅ **Stateless containers**: GeoServer instances become truly ephemeral
- ✅ **Enterprise scalability**: PostgreSQL handles concurrency and replication natively
- ✅ **Disaster recovery**: Full system restoration via database backup/restore

---

## Prerequisites Verification

Before proceeding with UI activation, confirm these foundational elements are in place:

```yaml
Infrastructure Status:
  ✓ PostgreSQL database accessible
  ✓ Dedicated schemas created:
      - gs_auth_role_schema (security)
      - gs_jdbcconfig_schema (configuration)
  ✓ GeoServer containers running
  ✓ JDBC drivers deployed in GeoServer lib directory
  ✓ Initial security services configured via startup scripts
  ✓ File-based login services disabled
```

> 🔍 **Note**: The `./scripts/activate_jdbcS_settings.sh` script should have already set up the initial service definitions in GeoServer’s `security/` and `jdbcconfig/` directories. If not, run it **now**.

---

## Database Schema Reference

### Security Schema (`gs_auth_role_schema`)

**Primary Tables & Use Cases:**

| Table         | Purpose                     | Common Operations                       |
| ------------- | --------------------------- | --------------------------------------- |
| `users`       | User credentials and status | Password resets, account enable/disable |
| `roles`       | Role definitions            | Role creation/deletion                  |
| `user_roles`  | User-role relationships     | Permission assignment                   |
| `groups`      | User groups                 | Group management                        |
| `group_roles` | Group-role mappings         | Bulk permission management              |
| `user_props`  | Extended user metadata      | Integration with external IAM systems   |

**Integration Points:**

- External user provisioning systems (SCIM, LDAP sync)
- Django/IAM system integrations
- Security auditing and compliance reporting
- Automated user lifecycle management

### Configuration Schema (`gs_jdbcconfig_schema`)

**Core Tables(Views) & Use Cases:**

| Table                       | Purpose                    | Common Operations            |
| --------------------------- | -------------------------- | ---------------------------- |
| `workspace`                 | Workspace definitions      | Multi-tenant isolation       |
| `datastore`/`coveragestore` | Data source configurations | Connection parameter updates |
| `featuretype`/`coverage`    | Layer metadata             | Schema modifications         |
| `layer`/`layergroup`        | Published layers           | Layer organization           |
| `style`/`layer_style`       | Styling rules              | Style versioning             |
| `service`/`settings`        | Service configurations     | Performance tuning           |

**Operational Use Cases:**

- Automated backup/restore via SQL dumps
- Configuration version control through database snapshots
- CI/CD pipeline deployments using SQL scripts
- Cross-environment configuration synchronization
- Disaster recovery without manual file restoration

> **⚠️ Critical Warning**: Manual table edits are **not recommended** except for emergency recovery. Always use GeoServer REST API or UI for configuration changes to maintain data integrity.
