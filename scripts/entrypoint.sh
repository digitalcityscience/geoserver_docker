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
# Runtime plugin installation (from .env)
# -------------------------------------------------------------------

IMAGE_PLUGINS_FILE="/opt/geoserver/.image_plugins"

# Runtime'da istenen plugin listesi
RUNTIME_OFFICIAL="${OFFICIAL_PLUGINS:-}"
RUNTIME_COMMUNITY="${COMMUNITY_PLUGINS:-}"

# Image'a bake edilmiş plugin listesi
if [ -f "$IMAGE_PLUGINS_FILE" ]; then
  IMAGE_CONTENT="$(cat "$IMAGE_PLUGINS_FILE")"
  IMAGE_VERSION="$(echo "$IMAGE_CONTENT" | cut -d'|' -f1)"
  IMAGE_OFFICIAL="$(echo "$IMAGE_CONTENT" | cut -d'|' -f2)"
  IMAGE_COMMUNITY="$(echo "$IMAGE_CONTENT" | cut -d'|' -f3)"
else
  IMAGE_OFFICIAL=""
  IMAGE_COMMUNITY=""
fi

# Eğer runtime ile image aynıysa, hiçbir şey yapma
if [ "$RUNTIME_OFFICIAL" = "$IMAGE_OFFICIAL" ] && [ "$RUNTIME_COMMUNITY" = "$IMAGE_COMMUNITY" ]; then
  echo "✅ Using base plugins from image, no additional plugins needed"
else
  echo "🧩 Plugin configuration differs from image..."
  
  # Sadece FARK olan pluginleri bul (runtime'da olan ama image'da olmayan)
  NEW_OFFICIAL=$(comm -23 <(echo "$RUNTIME_OFFICIAL" | tr ',' '\n' | sort) <(echo "$IMAGE_OFFICIAL" | tr ',' '\n' | sort) | tr '\n' ',' | sed 's/,$//')
  NEW_COMMUNITY=$(comm -23 <(echo "$RUNTIME_COMMUNITY" | tr ',' '\n' | sort) <(echo "$IMAGE_COMMUNITY" | tr ',' '\n' | sort) | tr '\n' ',' | sed 's/,$//')
  
  if [ -z "$NEW_OFFICIAL" ] && [ -z "$NEW_COMMUNITY" ]; then
    echo "✅ No additional plugins to install"
  else
    echo "📦 Installing additional plugins..."
    [ -n "$NEW_OFFICIAL" ] && echo "   Additional Official: $NEW_OFFICIAL"
    [ -n "$NEW_COMMUNITY" ] && echo "   Additional Community: $NEW_COMMUNITY"
    
    python3 /opt/geoserver/plugin_manager/cli.py \
      --version "${GEOSERVER_VERSION}" \
      --official "${NEW_OFFICIAL}" \
      --community "${NEW_COMMUNITY}"
    echo "✅ Additional plugins installed"
  fi
fi
# -------------------------------------------------------------------
# 5) Start Tomcat (PID 1)
# -------------------------------------------------------------------
echo "Starting Tomcat..."
exec catalina.sh run