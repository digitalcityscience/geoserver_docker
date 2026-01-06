#!/bin/bash
set -euo pipefail

echo "🚀 GeoServer container starting..."

# -------------------------------------------------------------------
# 0) Sanity (optional but helpful)
# -------------------------------------------------------------------
: "${GEOSERVER_DATA_DIR:=/geoserver_data/data}"
: "${GEOSERVER_CORS_ENABLED:=true}"
: "${GEOSERVER_CORS_ALLOWED_ORIGINS:=*}"
: "${GEOSERVER_CORS_ALLOWED_METHODS:=GET,POST,PUT,DELETE,HEAD,OPTIONS}"
: "${GEOSERVER_CORS_ALLOWED_HEADERS:=*}"

WEB_XML="$CATALINA_HOME/webapps/geoserver/WEB-INF/web.xml"
# -------------------------------------------------------------------
# CORS configuration (web.xml)
# -------------------------------------------------------------------
echo "🌐 Configuring CORS..."

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
# 4) proxyBaseUrl (global.xml) - only if file exists
# -------------------------------------------------------------------
if [ -n "${PROXY_BASE_URL:-}" ]; then
  GLOBAL_XML="${GEOSERVER_DATA_DIR}/global.xml"
  if [ -f "$GLOBAL_XML" ]; then
    echo "🔗 Setting proxyBaseUrl to $PROXY_BASE_URL"
    sed -i "s|<proxyBaseUrl>.*</proxyBaseUrl>|<proxyBaseUrl>${PROXY_BASE_URL}</proxyBaseUrl>|" "$GLOBAL_XML" || true
  else
    echo "ℹ️  global.xml not found yet (first boot) → skipping proxyBaseUrl patch"
  fi
fi

# -------------------------------------------------------------------
# 5) Start Tomcat (PID 1)
# -------------------------------------------------------------------
echo "Starting Tomcat..."
exec catalina.sh run