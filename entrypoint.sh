#!/bin/bash
set -e

# Environment variables with defaults
GEOSERVER_ADMIN_USER=${GEOSERVER_ADMIN_USER:-admin}
GEOSERVER_ADMIN_PASSWORD=${GEOSERVER_ADMIN_PASSWORD:-geoserver}
GEOSERVER_DATA_DIR=${GEOSERVER_DATA_DIR:-/geoserver_data/data}
PROXY_BASE_URL=${PROXY_BASE_URL:-}

CATALINA_HOME="/usr/local/tomcat"
export CATALINA_HOME
export CATALINA_TMPDIR="${CATALINA_HOME}/temp"

USERS_XML="${GEOSERVER_DATA_DIR}/security/usergroup/default/users.xml"
WEB_XML="${CATALINA_HOME}/webapps/geoserver/WEB-INF/web.xml"
LOG_FILE="${CATALINA_HOME}/logs/catalina.out"

# 1. Ensure the GeoServer data directory exists and set proper ownership
echo "[INFO] Ensuring GEOSERVER_DATA_DIR exists: $GEOSERVER_DATA_DIR"
mkdir -p "$GEOSERVER_DATA_DIR"

# If the 'tomcat' user exists (common in official Tomcat images), assign ownership
if getent passwd tomcat > /dev/null 2>&1; then
  echo "[INFO] Found 'tomcat' user. Setting ownership..."
  chown -R tomcat:tomcat "$GEOSERVER_DATA_DIR"
  # Ensure Tomcat runtime directories exist and are owned by 'tomcat'
  mkdir -p "${CATALINA_HOME}/logs"
  chown -R tomcat:tomcat "${CATALINA_HOME}/logs" "${CATALINA_HOME}/temp" "${CATALINA_HOME}/work"
fi

# 2. Configure CORS in web.xml (this file is always present after GeoServer deployment)
configure_cors() {
  if [ "$GEOSERVER_CORS_ENABLED" = "true" ] && ! grep -q "DockerGeoServerCorsFilter" "$WEB_XML" 2>/dev/null; then
    echo "[INFO] Injecting CORS filter into web.xml..."
    # Insert CORS filter just before the closing </web-app> tag
    sed -i "\:</web-app>:i\
    <filter>\n\
      <filter-name>DockerGeoServerCorsFilter</filter-name>\n\
      <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>\n\
      <init-param>\n\
        <param-name>cors.allowed.origins</param-name>\n\
        <param-value>${GEOSERVER_CORS_ALLOWED_ORIGINS:-*}</param-value>\n\
      </init-param>\n\
      <init-param>\n\
        <param-name>cors.allowed.methods</param-name>\n\
        <param-value>${GEOSERVER_CORS_ALLOWED_METHODS:-GET,POST,PUT,DELETE,HEAD,OPTIONS}</param-value>\n\
      </init-param>\n\
      <init-param>\n\
        <param-name>cors.allowed.headers</param-name>\n\
        <param-value>${GEOSERVER_CORS_ALLOWED_HEADERS:-origin,content-type,accept,authorization}</param-value>\n\
      </init-param>\n\
    </filter>\n\
    <filter-mapping>\n\
      <filter-name>DockerGeoServerCorsFilter</filter-name>\n\
      <url-pattern>/*</url-pattern>\n\
    </filter-mapping>" "$WEB_XML"
  fi
}

# 3. Configure Proxy Base URL in global.xml (used for correct external URL generation, e.g., in redirects or Keycloak flows)
configure_proxy_base_url() {
  if [ -n "$PROXY_BASE_URL" ]; then
    GLOBAL_XML="$GEOSERVER_DATA_DIR/global.xml"
    if [ -f "$GLOBAL_XML" ]; then
      if grep -q "<proxyBaseUrl>" "$GLOBAL_XML"; then
        echo "[INFO] Updating existing proxyBaseUrl to: $PROXY_BASE_URL"
        sed -i "s|<proxyBaseUrl>.*</proxyBaseUrl>|<proxyBaseUrl>${PROXY_BASE_URL}</proxyBaseUrl>|" "$GLOBAL_XML"
      else
        echo "[INFO] Adding proxyBaseUrl to global.xml"
        # Insert after the <settings> opening tag
        sed -i "/<settings>/a \ \ \ \ <proxyBaseUrl>${PROXY_BASE_URL}</proxyBaseUrl>" "$GLOBAL_XML"
      fi
    else
      echo "[WARN] global.xml not found yet. Skipping proxyBaseUrl config for now."
      # Note: On first startup, GeoServer creates global.xml after Tomcat initializes.
      # Since proxyBaseUrl is mainly used for external redirects (e.g., OAuth2, login),
      # it's safe to configure it after users.xml is ready (which implies global.xml exists).
    fi
  fi
}

# 4. Wait for users.xml to be created by GeoServer during first startup
wait_for_users_xml() {
  local max_wait=90
  local count=0
  echo "[INFO] Waiting for GeoServer to initialize and create users.xml..."
  while [ ! -f "$USERS_XML" ]; do
    if [ $count -ge $max_wait ]; then
      echo "[ERROR] Timeout! users.xml was not created within ${max_wait} seconds."
      echo "Possible causes: Tomcat failed to start, port conflict, or insufficient memory."
      exit 1
    fi
    sleep 3
    ((count += 3))
    echo "[INFO] Still waiting... (${count}s elapsed)"
  done
  echo "[INFO] users.xml found at $USERS_XML"
}

# 5. Update admin password in users.xml (using 'plain:' prefix, supported in GeoServer 2.20+)
update_admin_password() {
  if [ -f "$USERS_XML" ]; then
    # Check if the password is already set to the expected value
    if grep -q "password=\"plain:$GEOSERVER_ADMIN_PASSWORD\"" "$USERS_XML"; then
      echo "[INFO] Admin password is already set correctly."
    else
      echo "[INFO] Updating admin password to: plain:$GEOSERVER_ADMIN_PASSWORD"
      # Replace any existing password value with the new plain-text one
      sed -i "s|password=\"[^\"]*\"|password=\"plain:$GEOSERVER_ADMIN_PASSWORD\"|" "$USERS_XML"
      # Also update the username if needed
      sed -i "s|username=\"[^\"]*\"|username=\"$GEOSERVER_ADMIN_USER\"|" "$USERS_XML"
    fi
  else
    echo "[ERROR] users.xml not found during password update!"
    exit 1
  fi
}

# === MAIN EXECUTION FLOW ===

echo "[INFO] Starting GeoServer entrypoint..."

# Apply CORS and proxy settings early (web.xml is available immediately)
configure_cors
configure_proxy_base_url

# Start Tomcat in the background so GeoServer can initialize its config files
echo "[INFO] Starting Tomcat in background..."
"$CATALINA_HOME/bin/catalina.sh" start

# Wait until GeoServer has created the initial security files (e.g., users.xml)
wait_for_users_xml

# Now that users.xml exists, safely update the admin credentials
update_admin_password

# Ensure the Tomcat log file exists before tailing it
echo "[INFO] Waiting for Tomcat log file..."
while [ ! -f "$LOG_FILE" ]; do
  sleep 2
done

# Hand over control to the log stream (this keeps the container running as PID 1)
echo "[INFO] Handing over to Tomcat logs (PID 1)..."
exec tail -F "$LOG_FILE"