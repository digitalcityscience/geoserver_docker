#!/usr/bin/env python3
"""Validate GeoServer reverse-proxy settings after bootstrap."""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def parse_bool(raw: str, default: bool = False) -> bool:
    if raw == "":
        return default
    return raw.lower() in {"1", "true", "yes", "y", "on"}


def is_production() -> bool:
    return env("ENV").lower() == "prod" or parse_bool(env("PROD_MODE"))


def request(url: str, user: str, password: str, accept: str = "application/json") -> tuple[int, str]:
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Basic {token}",
            "Accept": accept,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return response.status, response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", errors="replace")
    except urllib.error.URLError as exc:
        print(f"GeoServer proxy validation request failed: {exc.reason}", file=sys.stderr)
        return 0, ""


def fail_or_warn(message: str) -> int:
    if is_production():
        print(message, file=sys.stderr)
        return 1
    print(f"Warning: {message}")
    return 0


def settings_match(body: str, proxy_base_url: str, use_headers_proxy_url: bool) -> bool:
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return False

    settings = payload.get("global", {}).get("settings", {})
    actual_proxy_base_url = str(settings.get("proxyBaseUrl", "")).rstrip("/")
    actual_use_headers_proxy_url = parse_bool(str(settings.get("useHeadersProxyURL", "")))
    return (
        actual_proxy_base_url == proxy_base_url.rstrip("/")
        and actual_use_headers_proxy_url == use_headers_proxy_url
    )


def main() -> int:
    proxy_base_url = env("PROXY_BASE_URL")
    if not proxy_base_url:
        print("PROXY_BASE_URL is empty; proxy validation skipped")
        return 0

    base_url = env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver").rstrip("/")
    public_url = env("GEOSERVER_PUBLIC_URL", proxy_base_url).rstrip("/")
    user = env("GEOSERVER_ADMIN_USER", "admin")
    password = env("GEOSERVER_ADMIN_PASSWORD", "geoserver")
    use_headers_proxy_url = parse_bool(env("GEOSERVER_USE_HEADERS_PROXY_URL"), True)

    status, _ = request(f"{base_url}/rest/about/version", user, password)
    if status != 200:
        return fail_or_warn("GeoServer REST credentials failed during proxy validation")

    status, body = request(f"{base_url}/rest/settings.json", user, password)
    if status != 200:
        return fail_or_warn(f"GeoServer settings could not be read during proxy validation: HTTP {status}")

    if not settings_match(body, proxy_base_url, use_headers_proxy_url):
        return fail_or_warn("GeoServer proxy settings did not persist")

    status, capabilities = request(
        f"{base_url}/ows?service=WMS&version=1.3.0&request=GetCapabilities",
        user,
        password,
        accept="application/xml,text/xml,*/*",
    )
    if status == 200 and public_url not in capabilities and proxy_base_url.rstrip("/") not in capabilities:
        return fail_or_warn("GeoServer WMS capabilities do not include the configured public/proxy URL")

    if status not in {200, 401, 403}:
        return fail_or_warn(f"GeoServer WMS capabilities check returned unexpected HTTP {status}")

    print("GeoServer proxy settings validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
