#!/usr/bin/env python3
"""Configure advanced GeoServer JDBCConfig mode.

This script is intentionally narrow: it only runs for GEOSERVER_SECURITY_MODE=
jdbc-config with GEOSERVER_ENABLE_JDBC_CONFIG=true. JDBCConfig owns catalog and
some global settings, so default, jdbc-role, and jdbc-auth-role must never run
this path.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import base64
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


class JdbcConfigError(RuntimeError):
    """Raised when JDBCConfig cannot be enabled safely."""


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def parse_bool(name: str, default: bool = False) -> bool:
    raw = env(name)
    if raw == "":
        return default
    return raw.lower() in {"1", "true", "yes", "y", "on"}


def require_identifier(name: str, value: str) -> str:
    if not IDENTIFIER_RE.match(value):
        raise JdbcConfigError(f"{name} must be a simple PostgreSQL identifier, got {value!r}")
    return value


def replace_property(path: Path, key: str, value: str) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    prefix = f"{key}="
    replaced = False
    next_lines: list[str] = []
    for line in lines:
        if line.startswith(prefix):
            next_lines.append(f"{key}={value}")
            replaced = True
        else:
            next_lines.append(line)
    if not replaced:
        next_lines.append(f"{key}={value}")
    path.write_text("\n".join(next_lines) + "\n", encoding="utf-8")


def psql(sql: str, action: str) -> None:
    command = [
        "psql",
        "-v",
        "ON_ERROR_STOP=1",
        "-h",
        env("PG_HOST", "db"),
        "-p",
        env("PG_DOCKER_PORT", env("POSTGRES_CONTAINER_PORT", "5432")),
        "-U",
        env("PG_GS_USER"),
        "-d",
        env("PG_DATABASE"),
    ]
    process_env = os.environ.copy()
    process_env["PGPASSWORD"] = env("PG_GS_PASSWORD")
    result = subprocess.run(command, input=sql, text=True, capture_output=True, env=process_env, check=False)
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise JdbcConfigError(f"{action} failed: {stderr}")


def ensure_schema(schema: str) -> None:
    psql(f"CREATE SCHEMA IF NOT EXISTS {schema};\n", "JDBCConfig schema creation")


def configure_properties() -> None:
    data_dir = Path(env("GEOSERVER_DATA_DIR", "/geoserver_data/data"))
    properties_path = data_dir / "jdbcconfig" / "jdbcconfig.properties"
    schema = require_identifier("PG_SCHEMA_JDBCCONF", env("PG_SCHEMA_JDBCCONF", "gs_jdbcconfig_schema"))
    security_schema = env("PG_SCHEMA_GEOSERVER", "gs_auth_role_schema")

    if schema == security_schema:
        raise JdbcConfigError("PG_SCHEMA_JDBCCONF must be separate from PG_SCHEMA_GEOSERVER")

    if not properties_path.exists():
        raise JdbcConfigError(
            "jdbcconfig.properties was not found. Ensure the jdbcconfig plugin is installed "
            "for jdbc-config mode, for example COMMUNITY_PLUGINS=sec-oidc,jdbcconfig."
        )

    required = ["PG_HOST", "PG_DATABASE", "PG_GS_USER", "PG_GS_PASSWORD"]
    missing = [name for name in required if not env(name)]
    if missing:
        raise JdbcConfigError("Missing required JDBCConfig variables: " + ", ".join(missing))

    ensure_schema(schema)
    jdbc_url = (
        f"jdbc:postgresql://{env('PG_HOST', 'db')}:{env('PG_DOCKER_PORT', env('POSTGRES_CONTAINER_PORT', '5432'))}/"
        f"{env('PG_DATABASE')}?currentSchema={schema}"
    )

    replace_property(properties_path, "enabled", "true")
    replace_property(properties_path, "initdb", "true")
    replace_property(properties_path, "import", env("GEOSERVER_JDBC_CONFIG_IMPORT", "false"))
    replace_property(properties_path, "jdbcUrl", jdbc_url)
    replace_property(properties_path, "username", env("PG_GS_USER"))
    replace_property(properties_path, "password", env("PG_GS_PASSWORD"))

    print(f"JDBCConfig properties configured in {properties_path}")


def auth_header(user: str, password: str) -> str:
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def rest_request(method: str, url: str, user: str, password: str) -> int:
    request = Request(url, headers={"Authorization": auth_header(user, password)}, method=method)
    try:
        with urlopen(request, timeout=10) as response:
            response.read()
            return response.status
    except HTTPError as exc:
        exc.read()
        return exc.code
    except URLError as exc:
        raise JdbcConfigError(f"GeoServer REST request failed: {exc}") from exc


def reload_geoserver() -> None:
    base_url = env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver").rstrip("/")
    user = env("GEOSERVER_ADMIN_USER", "admin")
    password = env("GEOSERVER_ADMIN_PASSWORD", "geoserver")
    status = rest_request("POST", f"{base_url}/rest/reload", user, password)
    if status not in {200, 201, 202, 204}:
        raise JdbcConfigError(f"GeoServer reload after JDBCConfig update failed with HTTP {status}")


def main() -> int:
    mode = env("GEOSERVER_SECURITY_MODE", "default")
    if mode != "jdbc-config":
        print(f"JDBCConfig skipped for GEOSERVER_SECURITY_MODE={mode}")
        return 0

    if not parse_bool("GEOSERVER_ENABLE_JDBC_CONFIG"):
        print("JDBCConfig configuration failed: GEOSERVER_ENABLE_JDBC_CONFIG must be true", file=sys.stderr)
        return 1

    try:
        configure_properties()
        reload_geoserver()
    except JdbcConfigError as exc:
        print(f"JDBCConfig configuration failed: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
