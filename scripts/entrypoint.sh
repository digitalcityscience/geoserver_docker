#!/bin/bash
set -euo pipefail

echo "GeoServer container starting..."

: "${GEOSERVER_DATA_DIR:=/geoserver_data/data}"
: "${GEOSERVER_INTERNAL_URL:=http://localhost:8080/geoserver}"
: "${GEOSERVER_CORS_ENABLED:=true}"
: "${GEOSERVER_CORS_ALLOWED_ORIGINS:=*}"
: "${GEOSERVER_CORS_ALLOWED_METHODS:=GET,POST,PUT,DELETE,HEAD,OPTIONS}"
: "${GEOSERVER_CORS_ALLOWED_HEADERS:=*}"
: "${GEOSERVER_USE_HEADERS_PROXY_URL:=true}"
: "${GEOSERVER_PUBLIC_URL:=}"
: "${PROXY_BASE_URL:=}"
: "${GEOSERVER_ALLOW_WILDCARD_CORS:=false}"
: "${GEOSERVER_CSRF_WHITELIST:=}"
: "${GEOSERVER_CSRF_DISABLED:=false}"
: "${GEOSERVER_SECURITY_MODE:=default}"
: "${GEOSERVER_ENABLE_JDBC_CONFIG:=false}"
: "${GEOSERVER_ENABLE_JDBC_AUTH:=false}"
: "${GEOSERVER_ENABLE_JDBC_ROLE:=false}"
: "${GEOSERVER_APPLY_JDBC_ON_STARTUP:=false}"
: "${GEOSERVER_CORE_FILE_TIMEOUT_SECONDS:=120}"

if [ -z "${GEOSERVER_DISABLE_DEFAULT_ADMIN:-}" ]; then
  if [ "${GEOSERVER_ADMIN_USER:-admin}" != "admin" ]; then
    GEOSERVER_DISABLE_DEFAULT_ADMIN=true
  else
    GEOSERVER_DISABLE_DEFAULT_ADMIN=false
  fi
fi

case "${GEOSERVER_SECURITY_MODE}" in
  jdbc-role)
    GEOSERVER_ENABLE_JDBC_ROLE=true
    ;;
  jdbc-auth-role)
    GEOSERVER_ENABLE_JDBC_ROLE=true
    GEOSERVER_ENABLE_JDBC_AUTH=true
    ;;
  jdbc-config)
    GEOSERVER_ENABLE_JDBC_CONFIG=true
    ;;
  default|*)
    ;;
esac

if [ "${GEOSERVER_ENABLE_JDBC_AUTH}" = "true" ]; then
  GEOSERVER_ENABLE_JDBC_ROLE=true
fi

: "${ENABLE_JDBC_CONFIG:=${GEOSERVER_ENABLE_JDBC_CONFIG}}"
: "${ENABLE_JDBC_LOGIN:=${GEOSERVER_ENABLE_JDBC_AUTH}}"

export GEOSERVER_DATA_DIR GEOSERVER_INTERNAL_URL
export GEOSERVER_CORS_ENABLED GEOSERVER_CORS_ALLOWED_ORIGINS GEOSERVER_CORS_ALLOWED_METHODS GEOSERVER_CORS_ALLOWED_HEADERS
export GEOSERVER_USE_HEADERS_PROXY_URL GEOSERVER_PUBLIC_URL PROXY_BASE_URL
export GEOSERVER_ALLOW_WILDCARD_CORS GEOSERVER_CSRF_WHITELIST GEOSERVER_CSRF_DISABLED
export GEOSERVER_SECURITY_MODE
export GEOSERVER_ENABLE_JDBC_CONFIG GEOSERVER_ENABLE_JDBC_AUTH GEOSERVER_ENABLE_JDBC_ROLE
export GEOSERVER_APPLY_JDBC_ON_STARTUP
export GEOSERVER_DISABLE_DEFAULT_ADMIN
export ENABLE_JDBC_CONFIG ENABLE_JDBC_LOGIN
export GEOSERVER_CORE_FILE_TIMEOUT_SECONDS

python3 /scripts/geoserver_validate_runtime.py

append_java_opt() {
  local name="$1"
  local value="$2"

  if [[ "${JAVA_OPTS:-}" != *"-D${name}="* ]]; then
    JAVA_OPTS="${JAVA_OPTS:-} -D${name}=${value}"
  fi
}

append_java_opt "GEOSERVER_CSRF_DISABLED" "${GEOSERVER_CSRF_DISABLED}"
if [ -n "${GEOSERVER_CSRF_WHITELIST}" ]; then
  append_java_opt "GEOSERVER_CSRF_WHITELIST" "${GEOSERVER_CSRF_WHITELIST}"
fi
export JAVA_OPTS

mkdir -p "${GEOSERVER_DATA_DIR}"
if [ ! -w "${GEOSERVER_DATA_DIR}" ]; then
  echo "GEOSERVER_DATA_DIR is not writable: ${GEOSERVER_DATA_DIR}" >&2
  exit 1
fi

WEB_XML="$CATALINA_HOME/webapps/geoserver/WEB-INF/web.xml"
# -------------------------------------------------------------------
# CORS configuration (web.xml)
# -------------------------------------------------------------------
echo "Configuring CORS..."

if [ "$GEOSERVER_CORS_ENABLED" = "true" ] && ! grep -q DockerGeoServerCorsFilter "$WEB_XML"; then
  echo "Injecting CORS filter into web.xml..."
  sed -i "\:</web-app>:i\
  <filter>\n\
    <filter-name>DockerGeoServerCorsFilter</filter-name>\n\
    <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>\n\
    <init-param>\n\
      <param-name>cors.allowed.origins</param-name>\n\
      <param-value>${GEOSERVER_CORS_ALLOWED_ORIGINS}</param-value>\n\
    </init-param>\n\
    <init-param>\n\
      <param-name>cors.allowed.methods</param-name>\n\
      <param-value>${GEOSERVER_CORS_ALLOWED_METHODS}</param-value>\n\
    </init-param>\n\
    <init-param>\n\
      <param-name>cors.allowed.headers</param-name>\n\
      <param-value>${GEOSERVER_CORS_ALLOWED_HEADERS}</param-value>\n\
    </init-param>\n\
  </filter>\n\
  <filter-mapping>\n\
    <filter-name>DockerGeoServerCorsFilter</filter-name>\n\
    <url-pattern>/*</url-pattern>\n\
  </filter-mapping>" "$WEB_XML"
else
  echo "CORS already configured or disabled"
fi

# -------------------------------------------------------------------
# Runtime plugin installation (from .env)
# -------------------------------------------------------------------

IMAGE_PLUGINS_FILE="/opt/geoserver/.image_plugins"

# Plugin list requested at runtime.
RUNTIME_OFFICIAL="${OFFICIAL_PLUGINS:-}"
RUNTIME_COMMUNITY="${COMMUNITY_PLUGINS:-}"

# Plugin list baked into the image.
if [ -f "$IMAGE_PLUGINS_FILE" ]; then
  IMAGE_CONTENT="$(cat "$IMAGE_PLUGINS_FILE")"
  IMAGE_VERSION="$(echo "$IMAGE_CONTENT" | cut -d'|' -f1)"
  IMAGE_OFFICIAL="$(echo "$IMAGE_CONTENT" | cut -d'|' -f2)"
  IMAGE_COMMUNITY="$(echo "$IMAGE_CONTENT" | cut -d'|' -f3)"
else
  IMAGE_OFFICIAL=""
  IMAGE_COMMUNITY=""
fi

# If runtime plugins match the image metadata, no additional plugin install is needed.
if [ "$RUNTIME_OFFICIAL" = "$IMAGE_OFFICIAL" ] && [ "$RUNTIME_COMMUNITY" = "$IMAGE_COMMUNITY" ]; then
  echo "Using base plugins from image, no additional plugins needed"
else
  echo "Plugin configuration differs from image..."
  
  # Install only plugins requested at runtime but missing from the image metadata.
  NEW_OFFICIAL=$(comm -23 <(echo "$RUNTIME_OFFICIAL" | tr ',' '\n' | sort) <(echo "$IMAGE_OFFICIAL" | tr ',' '\n' | sort) | tr '\n' ',' | sed 's/,$//')
  NEW_COMMUNITY=$(comm -23 <(echo "$RUNTIME_COMMUNITY" | tr ',' '\n' | sort) <(echo "$IMAGE_COMMUNITY" | tr ',' '\n' | sort) | tr '\n' ',' | sed 's/,$//')
  
  if [ -z "$NEW_OFFICIAL" ] && [ -z "$NEW_COMMUNITY" ]; then
    echo "No additional plugins to install"
  else
    echo "Installing additional plugins..."
    [ -n "$NEW_OFFICIAL" ] && echo "   Additional Official: $NEW_OFFICIAL"
    [ -n "$NEW_COMMUNITY" ] && echo "   Additional Community: $NEW_COMMUNITY"
    
    python3 /opt/geoserver/plugin_manager/cli.py \
      --version "${GEOSERVER_VERSION}" \
      --official "${NEW_OFFICIAL}" \
      --community "${NEW_COMMUNITY}"
    echo "Additional plugins installed"
  fi
fi
# -------------------------------------------------------------------
# Start Tomcat and run post-start bootstrap steps.
# -------------------------------------------------------------------
echo "Starting Tomcat..."

catalina.sh run &
TOMCAT_PID=$!

shutdown_tomcat() {
  if kill -0 "${TOMCAT_PID}" 2>/dev/null; then
    kill "${TOMCAT_PID}" 2>/dev/null || true
  fi
}
trap shutdown_tomcat TERM INT EXIT

/scripts/geoserver_wait_ready.sh

wait_for_file() {
  local file_path="$1"
  local waited=0

  while [ ! -f "${file_path}" ]; do
    sleep 2
    waited=$((waited + 2))
    if [ "${waited}" -ge "${GEOSERVER_CORE_FILE_TIMEOUT_SECONDS}" ]; then
      echo "Timed out waiting for GeoServer core file: ${file_path}" >&2
      return 1
    fi
  done
}

if [ "${GEOSERVER_ENABLE_JDBC_CONFIG}" != "true" ]; then
  wait_for_file "${GEOSERVER_DATA_DIR}/global.xml"
  wait_for_file "${GEOSERVER_DATA_DIR}/security/config.xml"
  wait_for_file "${GEOSERVER_DATA_DIR}/security/usergroup/default/users.xml"
  echo "GeoServer file-backed core configuration is ready"
else
  wait_for_file "${GEOSERVER_DATA_DIR}/security/config.xml"
  wait_for_file "${GEOSERVER_DATA_DIR}/security/usergroup/default/users.xml"
  echo "GeoServer security configuration is ready for JDBCConfig mode"
fi

python3 /scripts/geoserver_set_admin_credentials.py
if [ "${GEOSERVER_APPLY_JDBC_ON_STARTUP}" = "true" ]; then
  echo "GEOSERVER_APPLY_JDBC_ON_STARTUP=true -> applying JDBC bootstrap during startup"
  python3 /scripts/geoserver_configure_jdbc_security.py
  python3 /scripts/geoserver_configure_jdbc_config.py
else
  echo "Skipping JDBC bootstrap on startup (manual activation mode)"
  echo "Run ENV_FILE=.env.<env> ./scripts/activate_jdbcS_settings.sh when you are ready"
fi

if [ -n "${PROXY_BASE_URL:-}" ] || [ "${GEOSERVER_USE_HEADERS_PROXY_URL:-false}" = "true" ]; then
  python3 /scripts/geoserver_apply_proxy_settings.py
fi

if [ -n "${PROXY_BASE_URL:-}" ]; then
  python3 /scripts/geoserver_validate_proxy_settings.py
fi

wait "${TOMCAT_PID}"
