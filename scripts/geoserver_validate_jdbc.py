#!/usr/bin/env python3
"""Validate explicit GeoServer JDBC security modes."""

from __future__ import annotations

import base64
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


JDBC_MODES = {"jdbc-role", "jdbc-auth-role", "jdbc-config"}
JDBC_AUTH_MODE = "jdbc-auth-role"
JDBC_CONFIG_MODE = "jdbc-config"
IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def require_identifier(name: str, value: str) -> str:
    if not IDENTIFIER_RE.match(value):
        raise ValueError(f"{name} must be a simple PostgreSQL identifier, got {value!r}")
    return value


def auth_header(user: str, password: str) -> str:
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def rest_status(url: str, user: str, password: str) -> int:
    request = Request(url, headers={"Authorization": auth_header(user, password)}, method="GET")
    try:
        with urlopen(request, timeout=10) as response:
            response.read()
            return response.status
    except HTTPError as exc:
        exc.read()
        return exc.code
    except URLError:
        return 0


def psql_scalar(sql: str) -> str:
    command = [
        "psql",
        "-v",
        "ON_ERROR_STOP=1",
        "-t",
        "-A",
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
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip().splitlines()[-1].strip()


def validate_config(errors: list[str], mode: str) -> None:
    data_dir = Path(env("GEOSERVER_DATA_DIR", "/geoserver_data/data"))
    role_service_name = env("GS_ROLE_SERVICE_NAME", "jdbc_role")
    user_group_service_name = env("JDBC_LOGIN_SERVICE_NAME", "jdbc_login")
    auth_provider_name = env("JDBC_AUTH_SERVICE_NAME", "jdbc_auth")
    config_path = data_dir / "security" / "config.xml"
    role_dir = data_dir / "security" / "role" / role_service_name
    user_group_dir = data_dir / "security" / "usergroup" / user_group_service_name
    auth_dir = data_dir / "security" / "auth" / auth_provider_name

    if not config_path.exists():
        errors.append(f"Missing GeoServer security config: {config_path}")
        return

    try:
        root = ET.parse(config_path).getroot()
    except ET.ParseError as exc:
        errors.append(f"Could not parse GeoServer security config: {exc}")
        return

    active_role_service = (root.findtext("roleServiceName") or "").strip()
    if active_role_service != role_service_name:
        errors.append(f"Expected active role service {role_service_name!r}, got {active_role_service!r}")

    for name in ("config.xml", "rolesddl.xml", "rolesdml.xml"):
        if not (role_dir / name).exists():
            errors.append(f"Missing JDBC role service file: {role_dir / name}")

    if mode == JDBC_AUTH_MODE:
        auth_provider_names = [item.text.strip() for item in root.findall("authProviderNames/string") if item.text]
        if auth_provider_name not in auth_provider_names:
            errors.append(f"Expected auth provider {auth_provider_name!r} in security config, got {auth_provider_names!r}")
        for name in ("config.xml", "usersddl.xml", "usersdml.xml"):
            if not (user_group_dir / name).exists():
                errors.append(f"Missing JDBC user/group service file: {user_group_dir / name}")
        if not (auth_dir / "config.xml").exists():
            errors.append(f"Missing JDBC auth provider file: {auth_dir / 'config.xml'}")


def validate_rest(errors: list[str]) -> None:
    base_url = env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver").rstrip("/")
    user = env("GEOSERVER_ADMIN_USER", "admin")
    password = env("GEOSERVER_ADMIN_PASSWORD", "geoserver")
    status = rest_status(f"{base_url}/rest/about/version", user, password)
    if status != 200:
        errors.append(f"GeoServer REST rejected configured admin credentials: HTTP {status}")


def validate_database(errors: list[str], mode: str) -> None:
    schema = require_identifier("PG_SCHEMA_GEOSERVER", env("PG_SCHEMA_GEOSERVER", "gs_auth_role_schema"))
    admin_user = env("GEOSERVER_ADMIN_USER", "admin")
    admin_role = env("GS_ADMIN_ROLE", "ADMIN")
    role_sql = f"""
SELECT COUNT(*)
FROM {schema}.user_roles
WHERE username = {sql_literal(admin_user)}
  AND rolename = {sql_literal(admin_role)};
"""
    try:
        role_count = psql_scalar(role_sql)
    except Exception as exc:  # noqa: BLE001 - validation should aggregate operator-facing errors.
        errors.append(f"JDBC role database validation failed: {exc}")
        return

    if role_count != "1":
        errors.append(f"Expected one admin JDBC role mapping, got {role_count}")

    if mode == JDBC_AUTH_MODE:
        user_sql = f"""
SELECT COUNT(*)
FROM {schema}.users
WHERE name = {sql_literal(admin_user)}
  AND enabled = 'Y';
"""
        try:
            user_count = psql_scalar(user_sql)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"JDBC user database validation failed: {exc}")
            return
        if user_count != "1":
            errors.append(f"Expected one enabled JDBC admin user, got {user_count}")



def validate_jdbc_config(errors: list[str]) -> None:
    data_dir = Path(env("GEOSERVER_DATA_DIR", "/geoserver_data/data"))
    properties_path = data_dir / "jdbcconfig" / "jdbcconfig.properties"
    expected_schema = env("PG_SCHEMA_JDBCCONF", "gs_jdbcconfig_schema")
    security_schema = env("PG_SCHEMA_GEOSERVER", "gs_auth_role_schema")

    if expected_schema == security_schema:
        errors.append("PG_SCHEMA_JDBCCONF must be separate from PG_SCHEMA_GEOSERVER")

    if not properties_path.exists():
        errors.append(f"Missing JDBCConfig properties file: {properties_path}")
        return

    values: dict[str, str] = {}
    for line in properties_path.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()

    if values.get("enabled") != "true":
        errors.append("jdbcconfig.properties must contain enabled=true")
    if values.get("initdb") != "true":
        errors.append("jdbcconfig.properties must contain initdb=true")
    jdbc_url = values.get("jdbcUrl", "")
    if f"currentSchema={expected_schema}" not in jdbc_url:
        errors.append(f"jdbcconfig.properties jdbcUrl must target PG_SCHEMA_JDBCCONF={expected_schema}")
    if values.get("username") != env("PG_GS_USER"):
        errors.append("jdbcconfig.properties username must match PG_GS_USER")


def main() -> int:
    mode = env("GEOSERVER_SECURITY_MODE", "default")
    if mode not in JDBC_MODES:
        print(f"JDBC validation skipped for GEOSERVER_SECURITY_MODE={mode}")
        return 0

    errors: list[str] = []
    if mode == JDBC_CONFIG_MODE:
        validate_jdbc_config(errors)
        validate_rest(errors)
    else:
        validate_config(errors, mode)
        validate_rest(errors)
        validate_database(errors, mode)

    if errors:
        print("GeoServer JDBC validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"GeoServer JDBC validation passed for mode: {mode}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
