# GeoServer Docker Image

[![CI](https://github.com/digitalcityscience/geoserver_docker/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/digitalcityscience/geoserver_docker/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/digitalcityscience/geoserver_docker?sort=semver)](https://github.com/digitalcityscience/geoserver_docker/releases)
[![Image](https://img.shields.io/badge/image-ghcr.io%2Fdigitalcityscience%2Ftosca--geoserver-blue?logo=docker)](https://github.com/digitalcityscience/geoserver_docker/pkgs/container/tosca-geoserver)
[![License: MIT](https://img.shields.io/github/license/digitalcityscience/geoserver_docker)](LICENSE)

The GeoServer image of the [TOSCA platform](https://github.com/digitalcityscience/TOSCA). To run the whole platform, start there; this repository builds and releases the image.

A self-contained GeoServer Docker image based on Tomcat 9 and Java 17. It downloads the selected GeoServer release and installs the configured official and community extensions at build time.

The image can run on its own. PostgreSQL/PostGIS, JDBC security, and JDBCConfig are optional integrations for deployments that need them.

## Quick start: run GeoServer only

For normal use, pull a released image from the [GitHub Container Registry package](https://github.com/digitalcityscience/geoserver_docker/pkgs/container/tosca-geoserver). Use a release tag such as `2.28.5-tosca.1`, not `latest` (see [Versions and releases](#versions-and-releases)).

```bash
docker pull ghcr.io/digitalcityscience/tosca-geoserver:2.28.5
```

Run the published image with a persistent data directory:

```bash
docker run -d \
  --name geoserver \
  -p 8080:8080 \
  -v geoserver_data:/geoserver_data/data \
  ghcr.io/digitalcityscience/tosca-geoserver:2.28.5
```

Open <http://localhost:8080/geoserver>. On first start, GeoServer uses its standard `admin` / `geoserver` credentials. Change them before exposing the service beyond a trusted local environment.

Images are published only from release tags, never from a push to `main`. See [Versions and releases](#versions-and-releases).

## Build an image locally

Build locally only when developing this image or testing an unreleased GeoServer version:

```bash
docker build \
  --build-arg GEOSERVER_VERSION=2.28.5 \
  -t dcs-geoserver:2.28.5 \
  -f docker/Dockerfile .
```

## Local Compose stack (GeoServer + PostGIS)

Use this option when you want a local PostGIS database for spatial stores, or plan to enable the optional JDBC services.

```bash
cp .env.development.example .env.development
make up ENV=dev
```

The stack starts GeoServer at <http://localhost:8080/geoserver> and PostGIS on the port configured by `PG_PORT`. The database initialization creates only GeoServer-specific schemas and roles:

- `PG_SCHEMA_GEOSERVER` for JDBC user and role services
- `PG_SCHEMA_JDBCCONF` for JDBCConfig
- `PG_SCHEMA_GIS` for spatial data GeoServer may read

`.env.development.example` is a template. Copy it to `.env.development` and set passwords and ports appropriate for your machine. `.env.development` is ignored by Git.

Environment files follow one rule in every TOSCA repository: the committed template is `.env.<mode>.example`, your copy is `.env.<mode>`, and the mode is written out in full (`development`, `production`). There is no plain `.env`, `.env.dev`, `.env.prod` or `.env.example`. `make … ENV=dev` reads `.env.development`; `ENV=prod` reads `.env.production`.

For a server deployment, copy `.env.production.example` to `.env.production`, replace every example secret, set an appropriately restrictive CORS allow-list, and run:

```bash
make up ENV=prod
```

## Django development integration (TOSCA Backend)

The [TOSCA Backend](https://github.com/digitalcityscience/TOSCA-Backend) consumes this repository as the `docker/geoserver_docker` Git submodule. Its development Compose file builds GeoServer from that local submodule and starts GeoServer, Django, and their shared PostGIS database together.

The responsibilities are deliberately separated:

- This repository owns the reusable GeoServer image, its plugins, and GeoServer-only standalone examples.
- TOSCA Backend owns its Django service, the shared development database, and Django-specific `PG_API_*` and `PG_SCHEMA_API` settings.

When working on the full application, start the stack from the TOSCA Backend repository, using its `docker-compose-dev.yml`. Do not run this repository's Compose stack at the same time: both stacks use the same default GeoServer, PostGIS, container-name, and port conventions.

To test an image change in the full application, update the submodule checkout in TOSCA Backend to the branch or commit under test, then run the backend development stack. Once the image change is merged, commit the updated submodule reference in TOSCA Backend.

The standalone environment templates in this repository intentionally do not define Django credentials or schemas. They are not required to run the GeoServer image and belong to the application repository that uses them.

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
| `make image` | Build the image as CI does, without Compose or an environment file |
| `make release VERSION=2.28.5-tosca.N` | Tag `main` and push the tag; CI publishes the image |

## Version compatibility

GeoServer 2.28.x requires Java 17 or later. The Dockerfile therefore uses a Java 17 Tomcat 9 image. GeoServer 2.x remains compatible with Tomcat 9.

## Versions and releases

A release is a Git tag `v<GeoServer version>-tosca.<n>`, for example `v2.28.5-tosca.1`: GeoServer 2.28.5, first TOSCA build of it. The next change to the image on the same GeoServer version is `-tosca.2`; a GeoServer upgrade starts again at `-tosca.1`.

| Workflow | Runs on | Does |
|---|---|---|
| [`ci.yml`](.github/workflows/ci.yml) | pull requests, pushes to `main` | secret scan, image build, [smoke test](scripts/ci/smoke-image.sh) — pushes nothing |
| [`release.yml`](.github/workflows/release.yml) | a `v*` tag | checks the tag, builds amd64 and arm64 once, smoke tests that build, pushes it as `tosca-geoserver:<version>`, creates the GitHub Release |

To release:

1. On `main`, add a `## [2.28.5-tosca.N]` section to [CHANGELOG.md](CHANGELOG.md) (through a pull request).
2. On the merged `main`, run `make release VERSION=2.28.5-tosca.N`. It checks that the checkout is clean and exactly `origin/main` and that the Dockerfile's GeoServer version and the changelog match, then creates the tag `v2.28.5-tosca.N` and pushes it.

`make image` builds the image on your machine with the same Dockerfile and build arguments as CI (`IMAGE=name:tag` to choose the tag).

A published version is never overwritten: the release workflow stops if the image tag already exists. The older tags `2.27.2`, `2.28.5` and `latest` were written by the previous workflow on every push to `main`; they stay as they are and are no longer updated.

Community plugins (`jdbcconfig`, `jdbcstore`, `sec-oauth2-openid-connect`) are downloaded as GeoServer nightly snapshots at build time, so two builds of the same commit can contain different plugin builds. The released image fixes them; rebuilding later may not.

