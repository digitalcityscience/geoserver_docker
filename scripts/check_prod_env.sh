#!/bin/bash
set -e

echo "🔎 Checking PRODUCTION environment safety..."

fail() {
  echo "❌ $1"
  exit 1
}

require_env() {
  local name="$1"
  local value="${!name:-}"

  if [ -z "$value" ]; then
    fail "$name must be set in production"
  fi
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

url_host() {
  python3 -c 'from urllib.parse import urlparse; import sys; print(urlparse(sys.argv[1]).hostname or "")' "$1"
}

# 1) PROD_MODE verification
if [ "$PROD_MODE" != "true" ]; then
  fail ".env.prod is active but PROD_MODE=true is not set"
fi

# 2) Weak password list
WEAK_PASSWORDS="geoserver admin password 1234 123456 postgres postgis mobilitydb"

# 3) Scan all env vars containing PASSWORD
while IFS='=' read -r name value; do
  if [[ "$name" == *PASSWORD* ]]; then
    for weak in $WEAK_PASSWORDS; do
      if [ "$value" = "$weak" ]; then
        echo "   ENV VAR : $name"
        echo "   VALUE   : $weak"
        fail "Weak password detected; refusing to start in production"
      fi
    done

    if [[ "$value" == *change_me* ]]; then
      echo "   ENV VAR : $name"
      fail "Placeholder password detected; replace all change_me values before production start"
    fi
  fi
done < <(env)

# 3) Phase 9 production environment contract
require_env GEOSERVER_ADMIN_PASSWORD
require_env GEOSERVER_INTERNAL_URL
require_env GEOSERVER_HOST_PORT
require_env GEOSERVER_CONTAINER_PORT
require_env POSTGRES_HOST_PORT
require_env POSTGRES_CONTAINER_PORT

if [ "${GEOSERVER_ADMIN_PASSWORD}" = "geoserver" ]; then
  fail "GEOSERVER_ADMIN_PASSWORD must not equal geoserver in production"
fi

if [ -n "${GEOSERVER_PORT:-}" ]; then
  fail "GEOSERVER_PORT is ambiguous; use GEOSERVER_HOST_PORT and GEOSERVER_CONTAINER_PORT"
fi

if [ -n "${PG_PORT:-}" ] && [ "${PG_PORT}" != "${POSTGRES_HOST_PORT}" ]; then
  fail "PG_PORT compatibility alias must match POSTGRES_HOST_PORT"
fi

if [ -n "${PG_DOCKER_PORT:-}" ] && [ "${PG_DOCKER_PORT}" != "${POSTGRES_CONTAINER_PORT}" ]; then
  fail "PG_DOCKER_PORT compatibility alias must match POSTGRES_CONTAINER_PORT"
fi

if [ -n "${GEOSERVER_PUBLIC_URL:-}" ] && [ -n "${PROXY_BASE_URL:-}" ] && [ "${GEOSERVER_PUBLIC_URL%/}" != "${PROXY_BASE_URL%/}" ]; then
  fail "PROXY_BASE_URL should match GEOSERVER_PUBLIC_URL in production when both are set"
fi

if [ -n "${GEOSERVER_PUBLIC_URL:-}" ] && [ "${GEOSERVER_INTERNAL_URL%/}" = "${GEOSERVER_PUBLIC_URL%/}" ]; then
  fail "GEOSERVER_INTERNAL_URL must remain an internal/container URL"
fi

if [ -n "${PROXY_BASE_URL:-}" ] && [ "${GEOSERVER_INTERNAL_URL%/}" = "${PROXY_BASE_URL%/}" ]; then
  fail "GEOSERVER_INTERNAL_URL must remain an internal/container URL"
fi

if [ "${GEOSERVER_CORS_ALLOWED_ORIGINS:-}" = "*" ] && ! is_true "${GEOSERVER_ALLOW_WILDCARD_CORS:-false}"; then
  fail "GEOSERVER_CORS_ALLOWED_ORIGINS must not be '*' unless GEOSERVER_ALLOW_WILDCARD_CORS=true"
fi

public_host=""
if [ -n "${GEOSERVER_PUBLIC_URL:-}" ]; then
  public_host="$(url_host "$GEOSERVER_PUBLIC_URL")"
elif [ -n "${PROXY_BASE_URL:-}" ]; then
  public_host="$(url_host "$PROXY_BASE_URL")"
fi
if [ -n "$public_host" ] && ! is_true "${GEOSERVER_CSRF_DISABLED:-false}"; then
  case ",${GEOSERVER_CSRF_WHITELIST:-}," in
    *",$public_host,"*) ;;
    *) fail "GEOSERVER_CSRF_WHITELIST must include the public GeoServer host: $public_host" ;;
  esac
fi

if is_true "${GEOSERVER_ENABLE_JDBC_ROLE:-false}" || is_true "${GEOSERVER_ENABLE_JDBC_AUTH:-false}" || is_true "${GEOSERVER_ENABLE_JDBC_CONFIG:-false}"; then
  require_env PG_HOST
  require_env PG_DATABASE
  require_env PG_GS_USER
  require_env PG_GS_PASSWORD
  require_env PG_SCHEMA_GEOSERVER
fi

if is_true "${GEOSERVER_ENABLE_JDBC_CONFIG:-false}"; then
  require_env PG_SCHEMA_JDBCCONF
  if [ "${PG_SCHEMA_JDBCCONF}" = "${PG_SCHEMA_GEOSERVER}" ]; then
    fail "PG_SCHEMA_JDBCCONF must be separate from PG_SCHEMA_GEOSERVER"
  fi
  case ",${COMMUNITY_PLUGINS:-}," in
    *,jdbcconfig,*) ;;
    *) fail "jdbc-config mode requires COMMUNITY_PLUGINS to include jdbcconfig" ;;
  esac
fi

echo "✅ Production environment validated"
