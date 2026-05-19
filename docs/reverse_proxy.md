# Reverse Proxy Notes

The default mode should be deterministic behind a reverse proxy while still running without one in local development.

## URL Responsibilities

| Variable | Purpose |
| --- | --- |
| `GEOSERVER_INTERNAL_URL` | Container/internal URL for bootstrap scripts, readiness checks, and REST automation. |
| `GEOSERVER_PUBLIC_URL` | External URL used by users, clients, OAuth/OIDC redirects, and generated service links. |
| `PROXY_BASE_URL` | GeoServer setting value. In production this should usually match `GEOSERVER_PUBLIC_URL`. |

## Default Behavior

- Patch `global.xml` only after it exists.
- Apply REST settings after GeoServer readiness when `PROXY_BASE_URL` is set.
- Validate persisted REST settings after admin credentials have been applied.
- Use `GEOSERVER_USE_HEADERS_PROXY_URL=true` when the proxy forwards host/protocol headers.
- Keep internal bootstrap calls on the internal URL unless explicitly validating the public proxy path.

## Required Proxy Headers

- `X-Forwarded-Proto`
- `X-Forwarded-Host`
- `X-Forwarded-Port`
- `X-Forwarded-Prefix` when GeoServer is mounted below a path prefix

## Production Checks

- Internal GeoServer URL is reachable.
- REST credentials work.
- Proxy settings persist.
- Generated WMS/WFS links use the expected public base URL.
- OAuth/OIDC redirects use the public URL instead of the Docker network URL.

## CORS and CSRF

- `GEOSERVER_CORS_ALLOWED_ORIGINS=*` is rejected in production unless `GEOSERVER_ALLOW_WILDCARD_CORS=true`.
- `GEOSERVER_CORS_ALLOWED_HEADERS` must be explicit in production and include `Authorization,Content-Type,X-Requested-With`.
- `GEOSERVER_CORS_ALLOWED_METHODS` must include `OPTIONS`.
- `GEOSERVER_CSRF_DISABLED=false` is the default.
- `GEOSERVER_CSRF_WHITELIST` must include the public GeoServer host when `GEOSERVER_PUBLIC_URL` or `PROXY_BASE_URL` is set in production.
- The entrypoint converts `GEOSERVER_CSRF_DISABLED` and `GEOSERVER_CSRF_WHITELIST` into GeoServer JVM system properties through `JAVA_OPTS`.

## Incident Note: Mixed Content Login Form (Resolved)

Symptom observed on the public HTTPS URL:

- Browser blocked login form submission due to mixed content.
- Login form action was generated as `http://.../j_spring_security_check` instead of `https://...`.

Root cause:

- Proxy-related startup logic could override or clear effective proxy behavior during container restarts.
- When `PROXY_BASE_URL` was empty, REST proxy updates could still interfere with persisted settings.

What was changed:

1. `scripts/geoserver_apply_proxy_settings.py`
	- Added safeguard: when `PROXY_BASE_URL` is empty, REST proxy update is skipped to avoid clearing persisted `proxyBaseUrl`.
	- Kept header-proxy behavior (`useHeadersProxyURL`) configurable and applied safely.
2. `scripts/entrypoint.sh`
	- Proxy settings step runs when either `PROXY_BASE_URL` is set or `GEOSERVER_USE_HEADERS_PROXY_URL=true`.
3. `.env.prod`
	- Explicitly set:
	  - `GEOSERVER_PUBLIC_URL=https://geoserver.hagis.dcs.hcu-hamburg.de/geoserver`
	  - `PROXY_BASE_URL=https://geoserver.hagis.dcs.hcu-hamburg.de/geoserver`
	  - `GEOSERVER_USE_HEADERS_PROXY_URL=true`

Result after fix:

- `proxyBaseUrl` and `useHeadersProxyURL` remain correct after restart.
- Public HTTPS login form action is no longer downgraded to HTTP.
- Reverse-proxy access and direct host-port access can coexist without losing persisted proxy settings.
