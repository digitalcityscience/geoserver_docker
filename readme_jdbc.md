# Production-Grade GeoServer Setup (PostgreSQL / JDBC)

This setup supports two independent PostgreSQL integrations:

- **JDBC security** stores GeoServer users, groups, authentication, and roles in PostgreSQL.
- **JDBCConfig** is an optional extension that stores the GeoServer catalog and server configuration in PostgreSQL.

## What `ENABLE_JDBC_CONFIG` controls

`ENABLE_JDBC_CONFIG` controls **only JDBCConfig**. It does not enable or disable JDBC login, authentication, or roles.

| Value | Where GeoServer stores workspaces, stores/datastores, layers, styles, services, and settings | JDBC users and roles |
| --- | --- | --- |
| `false` | Files in `GEOSERVER_DATA_DIR` (normally `/geoserver_data/data`) | Can still use PostgreSQL through `jdbc_login`, `jdbc_auth`, and `jdbc_role` |
| `true` | PostgreSQL schema `PG_SCHEMA_JDBCCONF` through the JDBCConfig extension | Unchanged; JDBC security remains a separate choice |

For a first JDBC rollout, keep `ENABLE_JDBC_CONFIG=false` and enable only JDBC role/auth. This gives PostgreSQL-backed security while leaving the catalog file-backed and easy to inspect or recover. Enable JDBCConfig later only when you specifically want catalog data such as workspaces, datastore/store connections, layers, and styles persisted in PostgreSQL.

Result when only JDBC security is enabled:

- Users and roles are stored in PostgreSQL.
- GeoServer catalog/configuration remains in the mounted data directory.
- JDBCConfig tables are not created or used.

## UI Activation Procedure

> **Note**: Despite correct backend configuration, GeoServer requires explicit UI activation. This is a mandatory step, not an optional convenience.

### Step 0 : Run Script

This script prepares JDBC security and config services.

##### Before running, ensure GeoServer containers are up. Please go to Geoserver URL (e.g. http://localhost:8080/geoserver) and confirm it is running.

**Linux / macOS**

> chmod +x ./scripts/activate_jdbcS_settings.sh
> ./scripts/activate_jdbcS_settings.sh

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

> **Why restart is mandatory**: This reloads the security chain with JDBC-backed authentication providers. It does not enable JDBCConfig unless `ENABLE_JDBC_CONFIG=true`.

⸻

1. Result
   • Credentials defined in .env are now stored in PostgreSQL
   • XML-based security is disabled
   • GeoServer roles and authentication run JDBC-backed
   • Workspace, store, layer, and style configuration stays file-backed unless `ENABLE_JDBC_CONFIG=true`
   • Keycloak / OIDC integration can now be added safely

⸻

⚠️ Important
Do not edit JDBC tables manually.
Use GeoServer UI or REST API only.

---

## Executive Summary

This documentation describes a GeoServer setup that uses PostgreSQL for security management and can optionally use it for server/catalog configuration through JDBCConfig. The two features can be adopted independently.

> **Key Benefit**: Start with JDBC security alone; enable JDBCConfig only when PostgreSQL-backed catalog persistence is a deliberate requirement.

---

## Architecture Overview

### Dual-Schema Design Pattern

This setup implements a strict separation of concerns using two dedicated PostgreSQL schemas:

| Component                   | Schema Name            | Purpose                          | Data Types                                                 |
| --------------------------- | ---------------------- | -------------------------------- | ---------------------------------------------------------- |
| **Security Management**     | `gs_auth_role_schema`  | Authentication and authorization | Users, groups, roles, permissions, relationships           |
| **GeoServer Configuration** | `gs_jdbcconfig_schema` | Optional JDBCConfig persistence (`ENABLE_JDBC_CONFIG=true`) | Workspaces, datastores, layers, styles, services, settings |

> **⚠️ Critical Design Principle**: These schemas **MUST** remain separate. Mixing security and configuration data creates lifecycle conflicts, security vulnerabilities, and maintenance complexity.

### Why This Architecture Matters

When both JDBC security and JDBCConfig are enabled:

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
- TOSCA Backend / Django and external IAM integrations
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
