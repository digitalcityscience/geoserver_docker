#!/usr/bin/env python3
"""Apply GeoServer proxy settings through file-backed XML and REST."""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def parse_bool(raw: str) -> bool:
    return raw.lower() in {"1", "true", "yes", "y", "on"}


def patch_global_xml(global_xml: Path, proxy_base_url: str, use_headers_proxy_url: bool) -> bool:
    if not global_xml.exists():
        return False

    tree = ET.parse(global_xml)
    root = tree.getroot()

    if proxy_base_url:
        proxy_node = root.find("settings/proxyBaseUrl")
        if proxy_node is None:
            settings = root.find("settings")
            if settings is None:
                settings = ET.SubElement(root, "settings")
            proxy_node = ET.SubElement(settings, "proxyBaseUrl")
        proxy_node.text = proxy_base_url

    headers_node = root.find("settings/useHeadersProxyURL")
    if headers_node is None:
        settings = root.find("settings")
        if settings is None:
            settings = ET.SubElement(root, "settings")
        headers_node = ET.SubElement(settings, "useHeadersProxyURL")
    headers_node.text = "true" if use_headers_proxy_url else "false"

    tree.write(global_xml, encoding="UTF-8", xml_declaration=True)
    print(f"Patched proxy settings in {global_xml}")
    return True


def rest_put_settings(gs_url: str, username: str, password: str, proxy_base_url: str, use_headers_proxy_url: bool) -> bool:
    settings_payload: dict[str, object] = {
        "useHeadersProxyURL": use_headers_proxy_url,
    }
    if proxy_base_url:
        settings_payload["proxyBaseUrl"] = proxy_base_url

    payload = json.dumps({"global": {"settings": settings_payload}}).encode("utf-8")
    credentials = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        f"{gs_url.rstrip('/')}/rest/settings",
        data=payload,
        method="PUT",
        headers={
            "Authorization": f"Basic {credentials}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError as exc:
        print(f"Proxy REST update failed with HTTP {exc.code}", file=sys.stderr)
    except urllib.error.URLError as exc:
        print(f"Proxy REST update failed: {exc.reason}", file=sys.stderr)
    return False


def apply_rest(proxy_base_url: str, use_headers_proxy_url: bool) -> bool:
    gs_url = env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver")
    username = env("GEOSERVER_ADMIN_USER", "admin")
    password = env("GEOSERVER_ADMIN_PASSWORD", "geoserver")

    if rest_put_settings(gs_url, username, password, proxy_base_url, use_headers_proxy_url):
        print("Applied proxy settings through GeoServer REST with configured credentials")
        return True

    if f"{username}:{password}" != "admin:geoserver":
        if rest_put_settings(gs_url, "admin", "geoserver", proxy_base_url, use_headers_proxy_url):
            print("Applied proxy settings through GeoServer REST with first-boot fallback credentials")
            return True

    return False


def main() -> int:
    proxy_base_url = env("PROXY_BASE_URL")
    use_headers_proxy_url = parse_bool(env("GEOSERVER_USE_HEADERS_PROXY_URL", "true"))
    if not proxy_base_url and not use_headers_proxy_url:
        print("PROXY_BASE_URL is empty and GEOSERVER_USE_HEADERS_PROXY_URL=false; proxy settings skipped")
        return 0

    data_dir = Path(env("GEOSERVER_DATA_DIR", "/geoserver_data/data"))
    global_xml = data_dir / "global.xml"

    patched_xml = patch_global_xml(global_xml, proxy_base_url, use_headers_proxy_url)
    applied_rest = False
    if proxy_base_url:
        applied_rest = apply_rest(proxy_base_url, use_headers_proxy_url)
    else:
        print("PROXY_BASE_URL is empty; skipping REST proxy update to avoid clearing persisted proxyBaseUrl")

    if applied_rest or patched_xml:
        return 0

    print("Proxy settings could not be applied through global.xml or REST", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
