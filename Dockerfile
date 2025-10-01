# GeoServer Dockerfile (best-practice)
ARG IMAGE_VERSION=9.0.106-jdk11-temurin-jammy
FROM tomcat:$IMAGE_VERSION
LABEL maintainer="orttak"
# Build-time ARGs
ARG GEOSERVER_VERSION=2.27.2

ARG JAVA_OPTS="-Xms512m -Xmx1024m"

# Runtime ENV
ENV GEOSERVER_DATA_DIR="/geoserver_data/data"
ENV GEOSERVER_CORS_ENABLED=true
ENV GEOSERVER_CORS_ALLOWED_ORIGINS=*
ENV GEOSERVER_CORS_ALLOWED_METHODS=GET,POST,PUT,DELETE,HEAD,OPTIONS
ENV GEOSERVER_CORS_ALLOWED_HEADERS=*
ENV JAVA_OPTS=${JAVA_OPTS}

# Install dependencies
RUN apt-get update && apt-get install -y curl wget unzip procps python3 python3-pip
RUN pip install invoke requests

# Download and unzip GeoServer
RUN cd /usr/local/tomcat/webapps && \
    wget https://sourceforge.net/projects/geoserver/files/GeoServer/${GEOSERVER_VERSION}/geoserver-${GEOSERVER_VERSION}-war.zip -O geoserver.zip && \
    unzip geoserver.zip && unzip geoserver.war -d geoserver && \
    rm geoserver.zip geoserver.war && \
    mkdir -p $GEOSERVER_DATA_DIR

# Add plugins (after download_plugins.sh runs)
COPY ./plugins /usr/local/tomcat/webapps/geoserver/WEB-INF/lib

# Add scripts
COPY entrypoint.sh /usr/local/tomcat/tmp/entrypoint.sh
COPY set_geoserver_password.py /usr/local/tomcat/tmp/
RUN chmod +x /usr/local/tomcat/tmp/entrypoint.sh

VOLUME $GEOSERVER_DATA_DIR

ENV JAVA_OPTS=${JAVA_OPTS}

CMD ["/usr/local/tomcat/tmp/entrypoint.sh"]
