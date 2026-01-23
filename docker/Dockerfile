# -----------------------------
# Base Tomcat
# -----------------------------
ARG IMAGE_VERSION=9.0.106-jdk11-temurin-jammy
FROM tomcat:${IMAGE_VERSION}
LABEL maintainer="orttak"

# -----------------------------
# Build-time args (IMAGE IDENTITY)
# -----------------------------
ARG GEOSERVER_VERSION=2.27.2
ARG JAVA_OPTS="-Xms512m -Xmx1024m"
# Build-time defaults
ARG DEFAULT_OFFICIAL_PLUGINS="gdal,monitor,vectortiles,mbstyle"
ARG DEFAULT_COMMUNITY_PLUGINS="jdbcconfig,jdbcstore,sec-oauth2-openid-connect"

# -----------------------------
# Runtime ENV (OVERRIDABLE IN DEV)
# -----------------------------
ENV GEOSERVER_VERSION=${GEOSERVER_VERSION}
ENV GEOSERVER_DATA_DIR="/geoserver_data/data"

# Runtime defaults (image içinden gelir)
ENV OFFICIAL_PLUGINS=${DEFAULT_OFFICIAL_PLUGINS}
ENV COMMUNITY_PLUGINS=${DEFAULT_COMMUNITY_PLUGINS}

ENV GEOSERVER_CORS_ENABLED=true
ENV GEOSERVER_CORS_ALLOWED_ORIGINS=*
ENV GEOSERVER_CORS_ALLOWED_METHODS=GET,POST,PUT,DELETE,HEAD,OPTIONS
ENV GEOSERVER_CORS_ALLOWED_HEADERS=*

ENV JAVA_OPTS=${JAVA_OPTS}

# Store image plugin signature (for fast runtime check)
RUN mkdir -p /opt/geoserver && \
    echo "${GEOSERVER_VERSION}|${DEFAULT_OFFICIAL_PLUGINS}|${DEFAULT_COMMUNITY_PLUGINS}" \
    > /opt/geoserver/.image_plugins

# -----------------------------
# System dependencies
# -----------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    curl wget unzip procps \
    python3 python3-pip \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------
# Download & install GeoServer (BUILD-TIME, FIXED)
# -----------------------------
RUN --mount=type=cache,target=/tmp/geoserver-cache \
    cd /usr/local/tomcat/webapps && \
    CACHE_FILE="/tmp/geoserver-cache/geoserver-${GEOSERVER_VERSION}-war.zip" && \
    if [ ! -f "${CACHE_FILE}" ]; then \
        curl -fL https://downloads.sourceforge.net/project/geoserver/GeoServer/${GEOSERVER_VERSION}/geoserver-${GEOSERVER_VERSION}-war.zip \
          -o "${CACHE_FILE}"; \
    fi && \
    cp "${CACHE_FILE}" geoserver.zip && \
    unzip -q geoserver.zip && \
    unzip -q geoserver.war -d geoserver && \
    rm -f geoserver.zip geoserver.war && \
    mkdir -p ${GEOSERVER_DATA_DIR}

# Store image GeoServer version for runtime mismatch warning
RUN mkdir -p /opt/geoserver && \
    echo "${GEOSERVER_VERSION}" > /opt/geoserver/.image_version

# -----------------------------
# Plugin manager (runtime use)
# -----------------------------
COPY plugin_manager /opt/geoserver/plugin_manager

# -----------------------------
# Entrypoint & helper scripts
# -----------------------------
COPY scripts /scripts
RUN chmod +x /scripts/*.sh

# -----------------------------
# Volumes
# -----------------------------
VOLUME ${GEOSERVER_DATA_DIR}

# -----------------------------
# Start (runtime logic in entrypoint)
# -----------------------------
ENTRYPOINT ["/scripts/entrypoint.sh"]