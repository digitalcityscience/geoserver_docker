# Changelog

All notable changes to the `tosca-geoserver` image. Versions are
`<GeoServer version>-tosca.<n>`; see [Versions and releases](readme.md#versions-and-releases).

## [Unreleased]

## [2.28.5-tosca.1] - 2026-11-26

First release under the `<GeoServer version>-tosca.<n>` scheme. The existing
`2.28.5` and `latest` images in GHCR stay as they are.

### Added
- Release workflow: images are published only from a `v*` tag, after a smoke
  test of the exact build that is pushed, together with a GitHub Release.
- Pull request CI: secret scan, image build and smoke test; nothing is pushed.
- The image carries its version and Git commit as OCI labels
  (`org.opencontainers.image.version`, `.revision`) and as
  `TOSCA_GEOSERVER_VERSION` / `TOSCA_GEOSERVER_REVISION`.

### Changed
- Pushes to `main` no longer publish images; `2.28.5` and `latest` are no
  longer overwritten.

### Removed
- The rendered JDBC `config.xml` files are no longer tracked; they are
  generated from their templates by `scripts/activate_jdbcS_settings.sh`.

GeoServer 2.28.5 on Tomcat 9.0.106 / Java 17 with the official plugins `gdal`,
`monitor`, `vectortiles`, `mbstyle` and the community plugins `jdbcconfig`,
`jdbcstore`, `sec-oauth2-openid-connect` — unchanged.
