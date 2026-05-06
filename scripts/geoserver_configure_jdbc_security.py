#!/usr/bin/env python3
"""Configure GeoServer JDBC security for explicit JDBC modes.

`jdbc-role` keeps users and groups file-backed and activates only the JDBC role
service. `jdbc-auth-role` renders the JDBC user/group service and auth provider,
creates the required tables when GeoServer has not done so yet, creates the
admin user through GeoServer REST, then switches security config to JDBC auth +
JDBC roles.
"""

from __future__ import annotations

import base64
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from string import Template
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


JDBC_ROLE_MODES = {"jdbc-role", "jdbc-auth-role"}
JDBC_AUTH_MODE = "jdbc-auth-role"
IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
DEFAULT_ADMIN_USER = "admin"
DEFAULT_ADMIN_PASSWORD = "geoserver"


class JdbcSecurityError(RuntimeError):
    """Raised when JDBC security bootstrap cannot complete safely."""


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def parse_list(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def require_identifier(name: str, value: str) -> str:
    if not IDENTIFIER_RE.match(value):
        raise JdbcSecurityError(f"{name} must be a simple PostgreSQL identifier, got {value!r}")
    return value


def render_template(source: Path, target: Path) -> None:
    content = Template(source.read_text(encoding="utf-8")).safe_substitute(os.environ)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def copy_static_files(source_dir: Path, target_dir: Path, names: tuple[str, ...]) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    for name in names:
        shutil.copy2(source_dir / name, target_dir / name)


def ensure_child(root: ET.Element, name: str) -> ET.Element:
    child = root.find(name)
    if child is None:
        child = ET.Element(name)
        root.insert(0, child)
    return child


def set_auth_provider_names(root: ET.Element, names: list[str]) -> None:
    auth_provider_names = ensure_child(root, "authProviderNames")
    auth_provider_names.clear()
    for name in names:
        item = ET.SubElement(auth_provider_names, "string")
        item.text = name


def update_security_config(config_path: Path, role_service_name: str, auth_provider_names: list[str] | None = None) -> None:
    if not config_path.exists():
        raise JdbcSecurityError(f"GeoServer security config does not exist yet: {config_path}")

    tree = ET.parse(config_path)
    root = tree.getroot()
    role_service = ensure_child(root, "roleServiceName")
    role_service.text = role_service_name
    if auth_provider_names is not None:
        set_auth_provider_names(root, auth_provider_names)
    tree.write(config_path, encoding="utf-8", xml_declaration=False)


def psql(sql: str) -> subprocess.CompletedProcess[str]:
    pg_host = env("PG_HOST", "db")
    pg_port = env("PG_DOCKER_PORT", env("POSTGRES_CONTAINER_PORT", "5432"))
    pg_database = env("PG_DATABASE")
    pg_user = env("PG_GS_USER")
    pg_password = env("PG_GS_PASSWORD")

    missing = [
        name
        for name, value in {
            "PG_DATABASE": pg_database,
            "PG_GS_USER": pg_user,
            "PG_GS_PASSWORD": pg_password,
        }.items()
        if not value
    ]
    if missing:
        raise JdbcSecurityError("Missing required JDBC database variables: " + ", ".join(missing))

    command = [
        "psql",
        "-v",
        "ON_ERROR_STOP=1",
        "-h",
        pg_host,
        "-p",
        pg_port,
        "-U",
        pg_user,
        "-d",
        pg_database,
    ]
    process_env = os.environ.copy()
    process_env["PGPASSWORD"] = pg_password
    return subprocess.run(command, input=sql, text=True, capture_output=True, env=process_env, check=False)


def run_psql(sql: str, action: str) -> str:
    result = psql(sql)
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise JdbcSecurityError(f"{action} failed: {stderr}")
    return result.stdout.strip()


def jdbc_schema() -> str:
    return require_identifier("PG_SCHEMA_GEOSERVER", env("PG_SCHEMA_GEOSERVER", "gs_auth_role_schema"))


def ensure_role_tables_and_seed(admin_user: str, admin_role: str, group_admin_role: str) -> None:
    schema = jdbc_schema()
    extra_roles = parse_list(env("GEOSERVER_JDBC_EXTRA_ROLES"))
    roles = [admin_role, group_admin_role, *extra_roles]

    values = ",\n  ".join(f"({sql_literal(role)}, NULL)" for role in roles)
    sql = f"""
CREATE TABLE IF NOT EXISTS {schema}.roles (
  name varchar(64) NOT NULL PRIMARY KEY,
  parent varchar(64)
);

CREATE TABLE IF NOT EXISTS {schema}.role_props (
  rolename varchar(64) NOT NULL,
  propname varchar(64) NOT NULL,
  propvalue varchar(2048),
  PRIMARY KEY (rolename, propname)
);

CREATE TABLE IF NOT EXISTS {schema}.user_roles (
  username varchar(128) NOT NULL,
  rolename varchar(64) NOT NULL,
  PRIMARY KEY (username, rolename)
);

CREATE INDEX IF NOT EXISTS user_roles_idx ON {schema}.user_roles (rolename, username);

CREATE TABLE IF NOT EXISTS {schema}.group_roles (
  groupname varchar(128) NOT NULL,
  rolename varchar(64) NOT NULL,
  PRIMARY KEY (groupname, rolename)
);

CREATE INDEX IF NOT EXISTS group_roles_idx ON {schema}.group_roles (rolename, groupname);

INSERT INTO {schema}.roles (name, parent)
VALUES
  {values}
ON CONFLICT (name) DO NOTHING;

INSERT INTO {schema}.user_roles (username, rolename)
VALUES ({sql_literal(admin_user)}, {sql_literal(admin_role)})
ON CONFLICT (username, rolename) DO NOTHING;
"""
    run_psql(sql, "JDBC role table creation and seed")


def ensure_user_tables() -> None:
    schema = jdbc_schema()
    sql = f"""
CREATE TABLE IF NOT EXISTS {schema}.users (
  name varchar(128) NOT NULL PRIMARY KEY,
  password varchar(254),
  enabled char(1) NOT NULL
);

CREATE TABLE IF NOT EXISTS {schema}.user_props (
  username varchar(128) NOT NULL,
  propname varchar(64) NOT NULL,
  propvalue varchar(2048),
  PRIMARY KEY (username, propname)
);

CREATE INDEX IF NOT EXISTS user_props_idx1 ON {schema}.user_props (propname, propvalue);
CREATE INDEX IF NOT EXISTS user_props_idx2 ON {schema}.user_props (propname, username);

CREATE TABLE IF NOT EXISTS {schema}.groups (
  name varchar(128) NOT NULL PRIMARY KEY,
  enabled char(1) NOT NULL
);

CREATE TABLE IF NOT EXISTS {schema}.group_members (
  groupname varchar(128) NOT NULL,
  username varchar(128) NOT NULL,
  PRIMARY KEY (groupname, username)
);

CREATE INDEX IF NOT EXISTS group_members_idx ON {schema}.group_members (username, groupname);
"""
    run_psql(sql, "JDBC user/group table creation")


def auth_header(user: str, password: str) -> str:
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def rest_request(
    method: str,
    url: str,
    user: str,
    password: str,
    data: str | bytes | None = None,
    content_type: str | None = None,
) -> tuple[int, str]:
    headers = {"Authorization": auth_header(user, password), "Accept": "application/json, text/plain, */*"}
    payload = None
    if data is not None:
        payload = data.encode("utf-8") if isinstance(data, str) else data
    if content_type is not None:
        headers["Content-Type"] = content_type
    request = Request(url, data=payload, headers=headers, method=method)
    try:
        with urlopen(request, timeout=10) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.status, body
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body
    except URLError as exc:
        raise JdbcSecurityError(f"GeoServer REST request failed: {exc}") from exc


def rest_status(url: str, user: str, password: str) -> int:
    status, _ = rest_request("GET", url, user, password)
    return status


def credentials_for_reload(base_url: str) -> tuple[str, str]:
    candidates = (
        (env("GEOSERVER_ADMIN_USER", DEFAULT_ADMIN_USER), env("GEOSERVER_ADMIN_PASSWORD", DEFAULT_ADMIN_PASSWORD)),
        (DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD),
    )
    for user, password in candidates:
        if rest_status(f"{base_url}/rest/about/version", user, password) == 200:
            return user, password
    raise JdbcSecurityError("No usable GeoServer admin credentials were accepted before JDBC reload")


def reload_geoserver(base_url: str) -> None:
    user, password = credentials_for_reload(base_url)
    status, body = rest_request("POST", f"{base_url}/rest/reload", user, password)
    if status not in {200, 201, 202, 204}:
        raise JdbcSecurityError(f"GeoServer reload failed with HTTP {status}: {body}")


def validate_rest_credentials(base_url: str, user: str, password: str) -> None:
    deadline = time.monotonic() + int(env("GEOSERVER_READY_TIMEOUT_SECONDS", "180"))
    last_status = 0
    while time.monotonic() < deadline:
        last_status = rest_status(f"{base_url}/rest/about/version", user, password)
        if last_status == 200:
            return
        time.sleep(int(env("GEOSERVER_READY_POLL_SECONDS", "5")))
    raise JdbcSecurityError(
        "GeoServer REST rejected configured admin credentials after JDBC reload: "
        f"HTTP {last_status}"
    )


def validate_role_seed(admin_user: str, admin_role: str) -> None:
    schema = jdbc_schema()
    sql = f"""
SELECT COUNT(*)
FROM {schema}.user_roles
WHERE username = {sql_literal(admin_user)}
  AND rolename = {sql_literal(admin_role)};
"""
    count = run_psql(sql, "JDBC role seed validation").splitlines()[-1].strip()
    if count != "1":
        raise JdbcSecurityError(f"Expected JDBC ADMIN role mapping for {admin_user!r}, got count {count!r}")


def validate_jdbc_user(admin_user: str) -> None:
    schema = jdbc_schema()
    sql = f"""
SELECT COUNT(*)
FROM {schema}.users
WHERE name = {sql_literal(admin_user)}
  AND enabled = 'Y';
"""
    count = run_psql(sql, "JDBC user validation").splitlines()[-1].strip()
    if count != "1":
        raise JdbcSecurityError(f"Expected enabled JDBC admin user {admin_user!r}, got count {count!r}")


def render_jdbc_role_service(data_dir: Path, init_dir: Path, role_service_name: str) -> None:
    source_dir = init_dir / "jdbc_role_service" / "jdbc_role"
    if not source_dir.exists():
        raise JdbcSecurityError(f"JDBC role template directory is missing: {source_dir}")
    target_dir = data_dir / "security" / "role" / role_service_name
    render_template(source_dir / "config.xml.template", target_dir / "config.xml")
    copy_static_files(source_dir, target_dir, ("rolesddl.xml", "rolesdml.xml"))


def render_jdbc_auth_services(data_dir: Path, init_dir: Path, user_group_service_name: str, auth_provider_name: str) -> None:
    login_source_dir = init_dir / "jdbc_login_service" / "jdbc_login"
    auth_source_dir = init_dir / "auth" / "jdbc_auth"
    if not login_source_dir.exists():
        raise JdbcSecurityError(f"JDBC login template directory is missing: {login_source_dir}")
    if not auth_source_dir.exists():
        raise JdbcSecurityError(f"JDBC auth template directory is missing: {auth_source_dir}")

    login_target_dir = data_dir / "security" / "usergroup" / user_group_service_name
    auth_target_dir = data_dir / "security" / "auth" / auth_provider_name
    render_template(login_source_dir / "config.xml.template", login_target_dir / "config.xml")
    copy_static_files(login_source_dir, login_target_dir, ("usersddl.xml", "usersdml.xml"))
    render_template(auth_source_dir / "config.xml.template", auth_target_dir / "config.xml")


def ensure_jdbc_admin_user(base_url: str, auth_user: str, auth_password: str, service_name: str, admin_user: str, admin_password: str) -> None:
    payload = (
        "<user>"
        f"<userName>{escape_xml(admin_user)}</userName>"
        f"<password>{escape_xml(admin_password)}</password>"
        "<enabled>true</enabled>"
        "</user>"
    )
    encoded_user = quote(admin_user, safe="")
    service = quote(service_name, safe="")
    create_url = f"{base_url}/rest/security/usergroup/service/{service}/users"
    update_url = f"{base_url}/rest/security/usergroup/service/{service}/user/{encoded_user}"

    status, body = rest_request("POST", create_url, auth_user, auth_password, data=payload, content_type="text/xml")
    if status in {200, 201, 409}:
        if status == 409:
            update_status, update_body = rest_request(
                "POST",
                update_url,
                auth_user,
                auth_password,
                data=payload,
                content_type="text/xml",
            )
            if update_status not in {200, 201, 204}:
                raise JdbcSecurityError(f"JDBC admin user update failed with HTTP {update_status}: {update_body}")
        return

    raise JdbcSecurityError(f"JDBC admin user creation failed with HTTP {status}: {body}")


def escape_xml(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def configure_jdbc_security() -> None:
    mode = env("GEOSERVER_SECURITY_MODE", "default")
    data_dir = Path(env("GEOSERVER_DATA_DIR", "/geoserver_data/data"))
    init_dir = Path(env("GEOSERVER_INIT_DIR", "/geoserver-init"))
    role_service_name = env("GS_ROLE_SERVICE_NAME", "jdbc_role")
    admin_role = env("GS_ADMIN_ROLE", "ADMIN")
    group_admin_role = env("GS_GROUP_ADMIN_ROLE", "GROUP_ADMIN")
    admin_user = env("GEOSERVER_ADMIN_USER", DEFAULT_ADMIN_USER)
    admin_password = env("GEOSERVER_ADMIN_PASSWORD", DEFAULT_ADMIN_PASSWORD)
    base_url = env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver").rstrip("/")

    render_jdbc_role_service(data_dir, init_dir, role_service_name)
    ensure_role_tables_and_seed(admin_user, admin_role, group_admin_role)

    if mode == JDBC_AUTH_MODE:
        user_group_service_name = env("JDBC_LOGIN_SERVICE_NAME", "jdbc_login")
        auth_provider_name = env("JDBC_AUTH_SERVICE_NAME", "jdbc_auth")
        render_jdbc_auth_services(data_dir, init_dir, user_group_service_name, auth_provider_name)
        ensure_user_tables()
        reload_geoserver(base_url)
        bootstrap_user, bootstrap_password = credentials_for_reload(base_url)
        ensure_jdbc_admin_user(
            base_url,
            bootstrap_user,
            bootstrap_password,
            user_group_service_name,
            admin_user,
            admin_password,
        )
        validate_jdbc_user(admin_user)
        validate_role_seed(admin_user, admin_role)
        update_security_config(data_dir / "security" / "config.xml", role_service_name, [auth_provider_name])
    else:
        update_security_config(data_dir / "security" / "config.xml", role_service_name)

    reload_geoserver(base_url)
    validate_rest_credentials(base_url, admin_user, admin_password)
    validate_role_seed(admin_user, admin_role)

    if mode == JDBC_AUTH_MODE:
        print(f"JDBC auth + role services configured: {env('JDBC_LOGIN_SERVICE_NAME', 'jdbc_login')} / {role_service_name}")
    else:
        print(f"JDBC role service configured: {role_service_name}")


def main() -> int:
    mode = env("GEOSERVER_SECURITY_MODE", "default")
    if mode not in JDBC_ROLE_MODES:
        print(f"JDBC security configuration skipped for GEOSERVER_SECURITY_MODE={mode}")
        return 0

    try:
        configure_jdbc_security()
    except JdbcSecurityError as exc:
        print(f"JDBC security configuration failed: {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError as exc:
        print(f"JDBC security configuration failed: missing executable or file: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
