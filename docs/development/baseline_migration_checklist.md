# GeoServer Docker Baseline Migration Checklist

This checklist records the Phase 1 baseline audit for the GeoServer Docker refactor. The migration target is a simple file-backed GeoServer default mode, with JDBC behavior kept available only through explicit runtime modes.

## Reference Comparison

- ✅ `Dockerfile`: the `/opt/gq2/dev-geoserver` reference uses a Tomcat JDK 11 image, unpacks the GeoServer WAR into `webapps/geoserver`, mounts `GEOSERVER_DATA_DIR`, and copies plugin JARs directly. The target image already follows the same basic Tomcat/WAR shape, but adds the plugin manager and currently bakes JDBC community plugins by default.
- ✅ `entrypoint.sh`: the reference entrypoint injects CORS, optionally patches `global.xml`, runs the password helper, and starts Tomcat. The target entrypoint keeps CORS and proxy handling, but also includes runtime plugin reconciliation and JDBCConfig-aware proxy behavior.
- ✅ Compose files: the reference compose file starts GeoServer with a data volume and a PostGIS service. The target dev/prod compose files make GeoServer depend on the database health check, which must become mode-specific so default mode can run without PostgreSQL.
- ✅ Plugin strategy: the reference downloads plugins into a local `plugins` folder before build. The target `plugin_manager/` is the preferred single installation path and should be kept, with default plugins changed to non-JDBC plugins only.
- ✅ Admin credentials: the reference uses `set_geoserver_password.py` against GeoServer REST. The target needs a production-safe successor that waits for readiness, uses internal URLs, falls back to `admin:geoserver` only for first bootstrap, and avoids logging secrets.

## JDBC-Specific Current Behavior

- ✅ `docker/Dockerfile` defaults community plugins to `jdbcconfig,jdbcstore,sec-oauth2-openid-connect`.
- ✅ `env_dev_sample` and `env_prod_sample` include JDBC-enabled plugin lists and JDBC flags in places.
- ✅ `docker-compose-dev.yml` and `docker-compose-prod.yml` previously required `db` health before GeoServer started; Phase 8 removed that default-mode dependency.
- ✅ `scripts/entrypoint.sh` detects `${GEOSERVER_DATA_DIR}/jdbcconfig` and switches proxy handling to REST because `global.xml` may not exist.
- ✅ `scripts/activate_jdbcS_settings.sh` activates JDBC login, JDBC role service, and JDBCConfig as one broad workflow.
- ✅ `docker/geoserver-init/security/config.xml.template` assumes a JDBC auth provider and is not valid as the default security manager template.
- ✅ `docker/initdb/init001.sh` bootstraps PostgreSQL schemas/users for GeoServer/JDBC and should be used only when a DB-backed mode is enabled.
- ✅ Rendered JDBC `config.xml` files exist next to templates and can drift from their source templates.

## Default Mode Behaviors To Keep

- ✅ GeoServer installation through Tomcat plus unpacked GeoServer WAR.
- ✅ Plugin installation through `plugin_manager/`, with required non-JDBC plugins baked into the image.
- ✅ File-backed `GEOSERVER_DATA_DIR` and XML security/configuration.
- ✅ Idempotent CORS injection into `WEB-INF/web.xml`.
- ✅ Deterministic reverse-proxy settings through `global.xml` when available and REST after readiness when needed.
- ✅ GeoServer health checks independent from PostgreSQL in default mode.
- ✅ Admin credential bootstrap through REST after GeoServer is ready.
- ✅ Production resource/runtime settings, including JVM options and environment validation.

## Migration Checklist

- ✅ Make `default` mode independent from PostgreSQL.
- ✅ Remove JDBC plugins from the default baked plugin list; keep them behind an explicit JDBC-capable build/runtime path.
- ✅ Preserve `plugin_manager/` as the only plugin download/install mechanism.
- ✅ Keep existing JDBC templates and scripts, but wire them only into `jdbc-role`, `jdbc-auth-role`, or `jdbc-config`.
- ✅ Split broad JDBC activation into smaller mode-specific helpers in later phases.
- ✅ Replace committed rendered JDBC `config.xml` authority with templates/runtime-generated output where practical.
- ✅ Keep CORS, proxy settings, health checks, admin credential bootstrap, and production validation in the default path.
