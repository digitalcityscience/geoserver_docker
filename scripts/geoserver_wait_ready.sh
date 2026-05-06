#!/bin/bash
set -euo pipefail

GS_URL="${GEOSERVER_INTERNAL_URL:-http://localhost:8080/geoserver}"
MAX_WAIT="${GEOSERVER_READY_TIMEOUT_SECONDS:-180}"
SLEEP_SECONDS="${GEOSERVER_READY_POLL_SECONDS:-5}"
WAITED=0

web_status() {
  curl -s -o /dev/null -w "%{http_code}" "${GS_URL}/web/" 2>/dev/null || true
}

rest_status() {
  local user="$1"
  local password="$2"
  curl -s -o /dev/null -w "%{http_code}" \
    -u "${user}:${password}" \
    "${GS_URL}/rest/about/version" 2>/dev/null || true
}

echo "Waiting for GeoServer web endpoint at ${GS_URL}/web/"

while true; do
  STATUS="$(web_status)"
  if [[ "${STATUS}" =~ ^(200|302)$ ]]; then
    break
  fi

  sleep "${SLEEP_SECONDS}"
  WAITED=$((WAITED + SLEEP_SECONDS))
  if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
    echo "GeoServer web endpoint did not become ready within ${MAX_WAIT} seconds"
    exit 1
  fi
done

echo "GeoServer web endpoint is ready"

REST_USER="${GEOSERVER_ADMIN_USER:-admin}"
REST_PASSWORD="${GEOSERVER_ADMIN_PASSWORD:-geoserver}"
WAITED=0

while true; do
  REST_STATUS="$(rest_status "${REST_USER}" "${REST_PASSWORD}")"

  if [[ "${REST_STATUS}" =~ ^(200|401|403)$ ]]; then
    if [ "${REST_STATUS}" = "200" ]; then
      echo "GeoServer REST endpoint is ready with configured credentials"
    else
      echo "GeoServer REST endpoint is reachable but configured credentials are not accepted yet"
    fi
    exit 0
  fi

  if [ "${REST_USER}:${REST_PASSWORD}" != "admin:geoserver" ]; then
    REST_STATUS="$(rest_status "admin" "geoserver")"
    if [[ "${REST_STATUS}" =~ ^(200|401|403)$ ]]; then
      if [ "${REST_STATUS}" = "200" ]; then
        echo "GeoServer REST endpoint is ready with first-boot fallback credentials"
      else
        echo "GeoServer REST endpoint is reachable but fallback credentials are not accepted"
      fi
      exit 0
    fi
  fi

  sleep "${SLEEP_SECONDS}"
  WAITED=$((WAITED + SLEEP_SECONDS))
  if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
    echo "GeoServer REST endpoint did not respond with an expected status within ${MAX_WAIT} seconds"
    exit 1
  fi
done
