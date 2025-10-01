#!/bin/bash
set -e

echo "Starting GeoServer with CORS config..."

WEB_XML="$CATALINA_HOME/webapps/geoserver/WEB-INF/web.xml"

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
fi

if [ -n "$PROXY_BASE_URL" ]; then
  echo "INFO: Setting proxyBaseUrl in global.xml to $PROXY_BASE_URL"
  sed -i "s|<proxyBaseUrl>.*</proxyBaseUrl>|<proxyBaseUrl>${PROXY_BASE_URL}</proxyBaseUrl>|" $GEOSERVER_DATA_DIR/global.xml
fi

# Run optional password script (if you want)
python3 /usr/local/tomcat/tmp/set_geoserver_password.py || true

# Start Tomcat
exec catalina.sh run
