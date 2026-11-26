#!/usr/bin/env bash
# Starts a built tosca-geoserver image on an empty data directory and checks
# that it serves GeoServer with the expected version and baked-in plugins.
# Used by the PR and release workflows; runs locally too:
#
#   scripts/ci/smoke-image.sh ghcr.io/digitalcityscience/tosca-geoserver:dev
#
# The container is started with GeoServer's own default admin password, which
# is fine for a throwaway check and is exactly what TOSCA's geoserver-init
# replaces on a real installation.
set -Eeuo pipefail

image=${1:?usage: smoke-image.sh IMAGE}
expected_version=${GEOSERVER_VERSION:-$(sed -n 's/^ARG GEOSERVER_VERSION=//p' "$(dirname "$0")/../../docker/Dockerfile")}
name=tosca-geoserver-smoke-$$
port=${SMOKE_PORT:-18585}

cleanup() {
  if [[ $failed != 0 ]]; then docker logs --tail 80 "$name" 2>&1 || true; fi
  # Started with --rm: stopping it also removes its anonymous data volume.
  docker stop "$name" >/dev/null 2>&1 || true
}
failed=0
trap cleanup EXIT

ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"; failed=1; }
check() { if [[ $3 == *"$2"* ]]; then ok "$1"; else fail "$1" "expected '$2', got '${3:0:200}'"; fi; }

docker run --rm -d --name "$name" -p "127.0.0.1:$port:8080" "$image" >/dev/null
base=http://127.0.0.1:$port/geoserver

echo "Waiting for GeoServer in $image"
for _ in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$base/web/" || true)
  [[ $code == 200 || $code == 302 ]] && break
  sleep 2
done

case $(curl -s -o /dev/null -w '%{http_code}' "$base/web/") in
  200|302) ok "web UI answers" ;;
  *) fail "web UI answers" "GeoServer did not start" ;;
esac
check "reports GeoServer $expected_version" "\"$expected_version\"" \
  "$(curl -s -u admin:geoserver "$base/rest/about/version.json")"
check "WMS capabilities"      WMS_Capabilities \
  "$(curl -s "$base/ows?service=WMS&version=1.3.0&request=GetCapabilities")"
check "vector tiles format"   application/vnd.mapbox-vector-tile \
  "$(curl -s "$base/ows?service=WMS&version=1.3.0&request=GetCapabilities")"

baked=$(docker exec "$name" cat /opt/geoserver/.image_plugins)
libs=$(docker exec "$name" ls /usr/local/tomcat/webapps/geoserver/WEB-INF/lib)
IFS='|' read -r _ official community <<<"$baked"
for p in ${official//,/ } ${community//,/ }; do
  # Plugin names map to jar names with a few exceptions.
  case $p in
    monitor) jar=gs-monitor-core ;;
    sec-oauth2-openid-connect) jar=gs-sec-oauth2-openid-connect-core ;;
    *) jar=gs-$p ;;
  esac
  check "plugin $p installed" "$jar-" "$(grep -- "^$jar-" <<<"$libs" || true)"
done

check "version label" "${EXPECT_IMAGE_VERSION:-}" \
  "$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"

echo
if [[ $failed == 0 ]]; then echo "All checks passed."; else echo "Some checks FAILED."; fi
exit $failed
