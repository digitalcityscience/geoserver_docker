# -----------------------------
# Base Tomcat
# -----------------------------
ARG IMAGE_VERSION=9.0.106-jdk11-temurin-jammy
FROM tomcat:${IMAGE_VERSION}

LABEL maintainer="orttak"

# -----------------------------
# Build-time args
# -----------------------------
ARG GEOSERVER_VERSION=2.27.2
ARG JAVA_OPTS="-Xms512m -Xmx1024m"

# -----------------------------
# Runtime ENV
# -----------------------------
ENV GEOSERVER_VERSION=${GEOSERVER_VERSION}
ENV GEOSERVER_DATA_DIR="/geoserver_data/data"

ENV GEOSERVER_CORS_ENABLED=true
ENV GEOSERVER_CORS_ALLOWED_ORIGINS=*
ENV GEOSERVER_CORS_ALLOWED_METHODS=GET,POST,PUT,DELETE,HEAD,OPTIONS
ENV GEOSERVER_CORS_ALLOWED_HEADERS=*

ENV JAVA_OPTS=${JAVA_OPTS}

# -----------------------------
# System dependencies
# -----------------------------
RUN apt-get update && apt-get install -y \
    curl wget unzip procps \
    python3 python3-pip \
    && apt-get install -y gettext-base \
    && rm -rf /var/lib/apt/lists/* 
# -----------------------------
# Download & install GeoServer
# -----------------------------
RUN cd /usr/local/tomcat/webapps && \
    wget -q https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/geoserver-${GEOSERVER_VERSION}-war.zip \
      -O geoserver.zip && \
    unzip -q geoserver.zip && \
    unzip -q geoserver.war -d geoserver && \
    rm -f geoserver.zip geoserver.war && \
    mkdir -p ${GEOSERVER_DATA_DIR}

# -----------------------------
# Plugin manager (Python stays)
# -----------------------------
COPY plugin_manager /opt/geoserver/plugin_manager

# -----------------------------
# Security + entrypoint scripts (XML-based password init)
# -----------------------------
COPY scripts /scripts
RUN chmod +x /scripts/*.sh

# -----------------------------
# Volumes
# -----------------------------
VOLUME ${GEOSERVER_DATA_DIR}
RUN python3 /opt/geoserver/plugin_manager/main.py \
  --version ${GEOSERVER_VERSION} \
  --community "${COMMUNITY_PLUGINS}" \
  --official "${OFFICIAL_PLUGINS}"
# -----------------------------
# Start (entrypoint handles password init + then Tomcat)
# -----------------------------
ENTRYPOINT ["/scripts/entrypoint.sh"]