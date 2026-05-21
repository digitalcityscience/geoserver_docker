#!/usr/bin/env python3
"""Validate GeoServer runtime mode environment before Tomcat starts."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from urllib.parse import urlparse


ALLOWED_MODES = {"default", "jdbc-role", "jdbc-auth-role", "jdbc-config"}
JDBC_PLUGINS = {"jdbcconfig", "jdbcstore"}
REQUIRED_CORS_HEADERS = {"authorization", "content-type", "x-requested-with"}


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def parse_bool(name: str, default: bool = False) -> bool:
    raw = env(name)
    if raw == "":
        return default
    value = raw.lower()
    if value in {"1", "true", "yes", "y", "on"}:
        return True
    if value in {"0", "false", "no", "n", "off"}:
        return False
    raise ValueError(f"{name} must be a boolean value, got {raw!r}")


def parse_list(raw: str) -> set[str]:
    return {item.strip() for item in raw.split(",") if item.strip()}


def is_production() -> bool:
    return env("ENV").lower() == "prod" or parse_bool("PROD_MODE", False)


def parsed_url(name: str, value: str, errors: list[str]):
    if not value:
        return None

    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        errors.append(f"{name} must be an absolute http(s) URL when set; got {value!r}")
        return None
    return parsed


def image_community_plugins() -> set[str]:
    metadata = Path("/opt/geoserver/.image_plugins")
    if not metadata.exists():
        return set()

    parts = metadata.read_text(encoding="utf-8").strip().split("|")
    if len(parts) < 3:
        return set()
    return parse_list(parts[2])


def expected_flags(mode: str) -> dict[str, bool]:
    return {
        "GEOSERVER_ENABLE_JDBC_ROLE": mode in {"jdbc-role", "jdbc-auth-role"},
        "GEOSERVER_ENABLE_JDBC_AUTH": mode == "jdbc-auth-role",
        "GEOSERVER_ENABLE_JDBC_CONFIG": mode == "jdbc-config",
    }


def collect_errors() -> list[str]:
    errors: list[str] = []
    mode = env("GEOSERVER_SECURITY_MODE", "default")

    if mode not in ALLOWED_MODES:
        errors.append(
            "GEOSERVER_SECURITY_MODE must be one of "
            f"{', '.join(sorted(ALLOWED_MODES))}; got {mode!r}"
        )
        return errors

    try:
        flags = {
            "GEOSERVER_ENABLE_JDBC_ROLE": parse_bool("GEOSERVER_ENABLE_JDBC_ROLE"),
            "GEOSERVER_ENABLE_JDBC_AUTH": parse_bool("GEOSERVER_ENABLE_JDBC_AUTH"),
            "GEOSERVER_ENABLE_JDBC_CONFIG": parse_bool("GEOSERVER_ENABLE_JDBC_CONFIG"),
            "ENABLE_JDBC_LOGIN": parse_bool("ENABLE_JDBC_LOGIN"),
            "ENABLE_JDBC_CONFIG": parse_bool("ENABLE_JDBC_CONFIG"),
        }
    except ValueError as exc:
        return [str(exc)]

    if flags["ENABLE_JDBC_LOGIN"] != flags["GEOSERVER_ENABLE_JDBC_AUTH"]:
        errors.append("ENABLE_JDBC_LOGIN must match GEOSERVER_ENABLE_JDBC_AUTH during the compatibility period")

    if flags["ENABLE_JDBC_CONFIG"] != flags["GEOSERVER_ENABLE_JDBC_CONFIG"]:
        errors.append("ENABLE_JDBC_CONFIG must match GEOSERVER_ENABLE_JDBC_CONFIG during the compatibility period")

    mode_presets = expected_flags(mode)
    for name, preset_value in mode_presets.items():
        if preset_value:
            flags[name] = True

    if flags["GEOSERVER_ENABLE_JDBC_AUTH"]:
        flags["GEOSERVER_ENABLE_JDBC_ROLE"] = True

    runtime_community = parse_list(env("COMMUNITY_PLUGINS"))
    available_community = runtime_community | image_community_plugins()
    selected_jdbc_plugins = runtime_community & JDBC_PLUGINS

    jdbc_enabled = any(
        flags[name]
        for name in (
            "GEOSERVER_ENABLE_JDBC_ROLE",
            "GEOSERVER_ENABLE_JDBC_AUTH",
            "GEOSERVER_ENABLE_JDBC_CONFIG",
        )
    )

    if not jdbc_enabled and selected_jdbc_plugins:
        errors.append(
            "default mode must not request JDBC community plugins: "
            + ", ".join(sorted(selected_jdbc_plugins))
        )

    if flags["GEOSERVER_ENABLE_JDBC_CONFIG"] and "jdbcconfig" not in available_community:
        errors.append("jdbc-config mode requires the jdbcconfig community plugin in the image or COMMUNITY_PLUGINS")

    if jdbc_enabled:
        collect_jdbc_environment_errors(flags, errors)

    collect_proxy_errors(errors)
    collect_cors_csrf_errors(errors)

    return errors


def collect_jdbc_environment_errors(flags: dict[str, bool], errors: list[str]) -> None:
    required = {
        "PG_HOST": env("PG_HOST"),
        "PG_DATABASE": env("PG_DATABASE"),
        "PG_GS_USER": env("PG_GS_USER"),
        "PG_GS_PASSWORD": env("PG_GS_PASSWORD"),
        "PG_SCHEMA_GEOSERVER": env("PG_SCHEMA_GEOSERVER"),
        "GS_ROLE_SERVICE_NAME": env("GS_ROLE_SERVICE_NAME", "jdbc_role"),
        "GS_ADMIN_ROLE": env("GS_ADMIN_ROLE", "ADMIN"),
        "GS_GROUP_ADMIN_ROLE": env("GS_GROUP_ADMIN_ROLE", "GROUP_ADMIN"),
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        errors.append(f"JDBC role/auth/config requires JDBC environment variables: {', '.join(missing)}")

    if flags["GEOSERVER_ENABLE_JDBC_AUTH"]:
        auth_required = {
            "JDBC_LOGIN_SERVICE_NAME": env("JDBC_LOGIN_SERVICE_NAME", "jdbc_login"),
            "JDBC_AUTH_SERVICE_NAME": env("JDBC_AUTH_SERVICE_NAME", "jdbc_auth"),
        }
        missing_auth = [name for name, value in auth_required.items() if not value]
        if missing_auth:
            errors.append(f"JDBC auth requires auth environment variables: {', '.join(missing_auth)}")

    if flags["GEOSERVER_ENABLE_JDBC_CONFIG"]:
        jdbc_config_schema = env("PG_SCHEMA_JDBCCONF")
        if not jdbc_config_schema:
            errors.append("JDBC config requires PG_SCHEMA_JDBCCONF")
        elif jdbc_config_schema == env("PG_SCHEMA_GEOSERVER"):
            errors.append("PG_SCHEMA_JDBCCONF must be separate from PG_SCHEMA_GEOSERVER in jdbc-config mode")


def collect_proxy_errors(errors: list[str]) -> None:
    internal_url = env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver")
    public_url = env("GEOSERVER_PUBLIC_URL")
    proxy_base_url = env("PROXY_BASE_URL")

    parsed_internal = parsed_url("GEOSERVER_INTERNAL_URL", internal_url, errors)
    parsed_public = parsed_url("GEOSERVER_PUBLIC_URL", public_url, errors)
    parsed_proxy = parsed_url("PROXY_BASE_URL", proxy_base_url, errors)

    if parsed_public and parsed_proxy and public_url.rstrip("/") != proxy_base_url.rstrip("/"):
        errors.append("PROXY_BASE_URL must match GEOSERVER_PUBLIC_URL when both are set")

    if is_production() and parsed_internal:
        if parsed_public and internal_url.rstrip("/") == public_url.rstrip("/"):
            errors.append("GEOSERVER_INTERNAL_URL must not point at GEOSERVER_PUBLIC_URL in production")
        if parsed_proxy and internal_url.rstrip("/") == proxy_base_url.rstrip("/"):
            errors.append("GEOSERVER_INTERNAL_URL must not point at PROXY_BASE_URL in production")


def collect_cors_csrf_errors(errors: list[str]) -> None:
    try:
        cors_enabled = parse_bool("GEOSERVER_CORS_ENABLED", True)
        allow_wildcard_cors = parse_bool("GEOSERVER_ALLOW_WILDCARD_CORS", False)
        csrf_disabled = parse_bool("GEOSERVER_CSRF_DISABLED", False)
    except ValueError as exc:
        errors.append(str(exc))
        return

    if not is_production():
        return

    allowed_origins = env("GEOSERVER_CORS_ALLOWED_ORIGINS", "*")
    allowed_headers = parse_list(env("GEOSERVER_CORS_ALLOWED_HEADERS", ""))
    allowed_methods = {method.lower() for method in parse_list(env("GEOSERVER_CORS_ALLOWED_METHODS", ""))}

    if cors_enabled:
        if allowed_origins == "*" and not allow_wildcard_cors:
            errors.append(
                "GEOSERVER_CORS_ALLOWED_ORIGINS must not be '*' in production "
                "unless GEOSERVER_ALLOW_WILDCARD_CORS=true"
            )

        if "*" in allowed_headers:
            errors.append("GEOSERVER_CORS_ALLOWED_HEADERS must be explicit in production")
        elif not REQUIRED_CORS_HEADERS.issubset({header.lower() for header in allowed_headers}):
            errors.append(
                "GEOSERVER_CORS_ALLOWED_HEADERS must include "
                "Authorization,Content-Type,X-Requested-With in production"
            )

        if "options" not in allowed_methods:
            errors.append("GEOSERVER_CORS_ALLOWED_METHODS must include OPTIONS in production")

    public_url = env("GEOSERVER_PUBLIC_URL")
    proxy_base_url = env("PROXY_BASE_URL")
    csrf_whitelist = {host.lower() for host in parse_list(env("GEOSERVER_CSRF_WHITELIST", ""))}
    public_host = ""

    if public_url:
        parsed_public = parsed_url("GEOSERVER_PUBLIC_URL", public_url, errors)
        public_host = (parsed_public.hostname or "").lower() if parsed_public else ""
    elif proxy_base_url:
        parsed_proxy = parsed_url("PROXY_BASE_URL", proxy_base_url, errors)
        public_host = (parsed_proxy.hostname or "").lower() if parsed_proxy else ""

    if public_host and not csrf_disabled and public_host not in csrf_whitelist:
        errors.append("GEOSERVER_CSRF_WHITELIST must include the public GeoServer host in production")

    return


def main() -> int:
    errors = collect_errors()
    if errors:
        print("GeoServer runtime validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    mode = env("GEOSERVER_SECURITY_MODE", "default")
    print(f"GeoServer runtime mode validated: {mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
