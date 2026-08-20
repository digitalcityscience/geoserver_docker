# GeoServer Docker Image

A self-contained GeoServer Docker image based on Tomcat 9 and Java 17. It downloads the selected GeoServer release and installs the configured official and community extensions at build time.

The image can run on its own. PostgreSQL/PostGIS, JDBC security, and JDBCConfig are optional integrations for deployments that need them.

## Quick start: run GeoServer only

Build a local image:

```bash
docker build \
  --build-arg GEOSERVER_VERSION=2.28.5 \
  -t dcs-geoserver:2.28.5 \
  -f docker/Dockerfile .
```

Run it with a persistent data directory:

```bash
docker run -d \
  --name geoserver \
  -p 8080:8080 \
  -v geoserver_data:/geoserver_data/data \
  dcs-geoserver:2.28.5
```

Open <http://localhost:8080/geoserver>. On first start, GeoServer uses its standard `admin` / `geoserver` credentials. Change them before exposing the service beyond a trusted local environment.

Published images are available from GitHub Container Registry after the image workflow has run:

```bash
docker pull ghcr.io/digitalcityscience/tosca-geoserver:2.28.5
```

## Local Compose stack (GeoServer + PostGIS)

Use this option when you want a local PostGIS database for spatial stores, or plan to enable the optional JDBC services.

```bash
cp env_dev_sample .env.dev
make up ENV=dev
```

The stack starts GeoServer at <http://localhost:8080/geoserver> and PostGIS on the port configured by `PG_PORT`. The database initialization creates only GeoServer-specific schemas and roles:

- `PG_SCHEMA_GEOSERVER` for JDBC user and role services
- `PG_SCHEMA_JDBCCONF` for JDBCConfig
- `PG_SCHEMA_GIS` for spatial data GeoServer may read

`env_dev_sample` is a template. Copy it to `.env.dev` and set passwords and ports appropriate for your machine. `.env.dev` is ignored by Git.

For a server deployment, copy `env_prod_sample` to `.env.prod`, replace every example secret, set an appropriately restrictive CORS allow-list, and run:

```bash
make up ENV=prod
```

## Optional JDBC security and configuration

GeoServer works without JDBC; its default configuration and users are stored in the data directory. Enable the JDBC path only when you want PostgreSQL-backed users, roles, and/or server configuration.

The Compose templates include the required database, schemas, and extension list. After the stack is running, follow [the JDBC setup guide](./readme_jdbc.md) to activate the services in GeoServer.

## Configure plugins

Set comma-separated plugin identifiers in the environment file:

```env
OFFICIAL_PLUGINS=gdal,monitor,vectortiles,mbstyle
COMMUNITY_PLUGINS=jdbcconfig,jdbcstore,sec-oauth2-openid-connect
```

The plugin manager resolves official extensions for the exact `GEOSERVER_VERSION`; community modules use the corresponding GeoServer series. Changes to these lists require rebuilding the image:

```bash
make rebuild ENV=dev
```

If you regularly use a custom plugin set, update the GitHub Actions workflow and publish an image containing that set. This avoids extension downloads at container startup.

## Common commands

| Command | Description |
| --- | --- |
| `make build ENV=dev` | Build the local GeoServer image |
| `make up ENV=dev` | Start the local GeoServer + PostGIS stack |
| `make down ENV=dev` | Stop the stack while retaining its volumes |
| `make logs geoserver ENV=dev` | Follow GeoServer logs |
| `make rebuild ENV=dev` | Rebuild the image and restart the stack |
| `make rmVolumes ENV=dev` | Remove containers and volumes (data loss) |

## Version compatibility

GeoServer 2.28.x requires Java 17 or later. The Dockerfile therefore uses a Java 17 Tomcat 9 image. GeoServer 2.x remains compatible with Tomcat 9.
