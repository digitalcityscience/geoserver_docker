#!/usr/bin/env python3
"""Bootstrap GeoServer admin credentials through the internal REST API."""

from __future__ import annotations

import base64
import os
import sys
import time
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


DEFAULT_ADMIN_USER = "admin"
DEFAULT_ADMIN_PASSWORD = "geoserver"


@dataclass(frozen=True)
class Response:
    status: int
    body: str


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def parse_bool(name: str, default: bool = False) -> bool:
    raw = env(name)
    if raw == "":
        return default
    return raw.lower() in {"1", "true", "yes", "y", "on"}


def is_production() -> bool:
    return env("ENV").lower() == "prod" or parse_bool("PROD_MODE")


def normalize_url(url: str) -> str:
    return url.rstrip("/")


def auth_header(user: str, password: str) -> str:
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    return f"Basic {token}"


def request(
    method: str,
    url: str,
    user: str,
    password: str,
    data: str | bytes | None = None,
    content_type: str | None = None,
) -> Response:
    payload = None
    headers = {
        "Authorization": auth_header(user, password),
        "Accept": "application/json, application/xml, text/plain, */*",
    }
    if data is not None:
        payload = data.encode("utf-8") if isinstance(data, str) else data
    if content_type is not None:
        headers["Content-Type"] = content_type

    req = Request(url, data=payload, headers=headers, method=method)
    try:
        with urlopen(req, timeout=10) as result:
            body = result.read().decode("utf-8", errors="replace")
            return Response(result.status, body)
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return Response(exc.code, body)
    except URLError as exc:
        raise ConnectionError(str(exc)) from exc


def rest_status(base_url: str, user: str, password: str) -> int:
    try:
        response = request(
            "GET",
            f"{base_url}/rest/about/version",
            user,
            password,
        )
        return response.status
    except ConnectionError:
        return 0


def wait_for_rest(base_url: str, timeout_seconds: int, poll_seconds: int) -> bool:
    print(f"Waiting for GeoServer REST at {base_url}/rest/about/version")
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        configured_user = env("GEOSERVER_ADMIN_USER", DEFAULT_ADMIN_USER)
        configured_password = env("GEOSERVER_ADMIN_PASSWORD", DEFAULT_ADMIN_PASSWORD)
        candidates = [(DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD)]
        if configured_user != DEFAULT_ADMIN_USER:
            candidates.append((configured_user, configured_password))
        for user, password in candidates:
            status = rest_status(base_url, user, password)
            if status in {200, 401, 403}:
                print("GeoServer REST endpoint is reachable")
                return True
        time.sleep(poll_seconds)
    return False


def credentials_work(base_url: str, user: str, password: str) -> bool:
    return rest_status(base_url, user, password) == 200


def credentials_have_admin_access(base_url: str, user: str, password: str) -> bool:
    return rest_status(base_url + "/rest/security/roles.xml", user, password) == 200


def fallback_admin_has_access(base_url: str) -> bool:
    for _ in range(3):
        if credentials_have_admin_access(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD):
            return True
        time.sleep(2)
    return False


def wait_for_admin_access(base_url: str, user: str, password: str, attempts: int = 6) -> bool:
    for _ in range(attempts):
        if credentials_have_admin_access(base_url, user, password):
            return True
        time.sleep(2)
    return False


def update_own_password(base_url: str, auth_user: str, auth_password: str, new_password: str) -> bool:
    attempts = (
        (
            "PUT",
            f"{base_url}/rest/security/self/password",
            new_password,
            "text/plain",
            "self-password-put",
        ),
        (
            "POST",
            f"{base_url}/rest/security/self/password",
            new_password,
            "text/plain",
            "self-password-post",
        ),
        (
            "POST",
            f"{base_url}/rest/security/usergroup/user/{quote(DEFAULT_ADMIN_USER, safe='')}",
            (
                "<user>"
                f"<userName>{escape_xml(DEFAULT_ADMIN_USER)}</userName>"
                f"<password>{escape_xml(new_password)}</password>"
                "<enabled>true</enabled>"
                "</user>"
            ),
            "text/xml",
            "usergroup-user-post",
        ),
    )

    for method, url, payload, content_type, attempt_name in attempts:
        response = request(
            method,
            url,
            auth_user,
            auth_password,
            data=payload,
            content_type=content_type,
        )
        if response.status in {200, 201, 204}:
            return True
        body_preview = (response.body or "").strip().replace("\n", " ")[:240]
        print(
            f"Admin password update attempt '{attempt_name}' failed with HTTP {response.status}. "
            f"Response: {body_preview}",
            file=sys.stderr,
        )

    return False


def ensure_user(base_url: str, auth_user: str, auth_password: str, user: str, password: str) -> bool:
    user_xml = (
        "<user>"
        f"<userName>{escape_xml(user)}</userName>"
        f"<password>{escape_xml(password)}</password>"
        "<enabled>true</enabled>"
        "</user>"
    )
    create = request(
        "POST",
        f"{base_url}/rest/security/usergroup/users/",
        auth_user,
        auth_password,
        data=user_xml,
        content_type="text/xml",
    )
    if create.status in {200, 201}:
        return True

    update = request(
        "POST",
        f"{base_url}/rest/security/usergroup/user/{quote(user, safe='')}",
        auth_user,
        auth_password,
        data=user_xml,
        content_type="text/xml",
    )
    return update.status in {200, 201}


def ensure_role_assignment(base_url: str, auth_user: str, auth_password: str, user: str, role: str) -> bool:
    encoded_role = quote(role, safe="")
    encoded_user = quote(user, safe="")
    endpoints = (
        f"{base_url}/rest/security/roles/role/{encoded_role}/user/{encoded_user}",
        f"{base_url}/rest/security/roles/service/default/role/{encoded_role}/user/{encoded_user}",
    )
    for endpoint in endpoints:
        response = request("POST", endpoint, auth_user, auth_password)
        if response.status in {200, 201, 409}:
            return True
    return False


def set_user_enabled(base_url: str, auth_user: str, auth_password: str, user: str, enabled: bool) -> bool:
    user_xml = (
        "<user>"
        f"<userName>{escape_xml(user)}</userName>"
        f"<enabled>{str(enabled).lower()}</enabled>"
        "</user>"
    )
    response = request(
        "POST",
        f"{base_url}/rest/security/usergroup/user/{quote(user, safe='')}",
        auth_user,
        auth_password,
        data=user_xml,
        content_type="text/xml",
    )
    return response.status in {200, 201, 404}


def escape_xml(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


def warn_or_fail(message: str) -> int:
    if is_production():
        print(message, file=sys.stderr)
        return 1
    print(f"Warning: {message}")
    return 0


def main() -> int:
    base_url = normalize_url(env("GEOSERVER_INTERNAL_URL", "http://localhost:8080/geoserver"))
    target_user = env("GEOSERVER_ADMIN_USER", DEFAULT_ADMIN_USER)
    target_password = env("GEOSERVER_ADMIN_PASSWORD", DEFAULT_ADMIN_PASSWORD)
    disable_default_admin = parse_bool(
        "GEOSERVER_DISABLE_DEFAULT_ADMIN",
        default=target_user != DEFAULT_ADMIN_USER,
    )
    timeout_seconds = int(env("GEOSERVER_READY_TIMEOUT_SECONDS", "180"))
    poll_seconds = int(env("GEOSERVER_READY_POLL_SECONDS", "5"))

    if not target_user:
        return warn_or_fail("GEOSERVER_ADMIN_USER must not be empty")
    if not target_password:
        return warn_or_fail("GEOSERVER_ADMIN_PASSWORD must not be empty")

    if not wait_for_rest(base_url, timeout_seconds, poll_seconds):
        return warn_or_fail("GeoServer REST did not become reachable for admin credential bootstrap")

    if target_user != DEFAULT_ADMIN_USER:
        print("Applying GeoServer admin credentials with first-boot fallback credentials")
        if ensure_user(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD, target_user, target_password):
            if not ensure_role_assignment(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD, target_user, "ADMIN"):
                return warn_or_fail(f"GeoServer ADMIN role could not be assigned to user '{target_user}'")

            if disable_default_admin:
                if set_user_enabled(base_url, target_user, target_password, DEFAULT_ADMIN_USER, False):
                    print("Default GeoServer admin user was disabled")
                else:
                    return warn_or_fail("Default GeoServer admin user could not be disabled")
            elif not wait_for_admin_access(base_url, target_user, target_password):
                print(
                    f"Warning: GeoServer did not immediately accept configured admin credentials "
                    f"for user '{target_user}'; continuing because user and role updates succeeded"
                )

            print(f"GeoServer admin credentials are configured for user '{target_user}'")
            return 0

        print(
            "First-boot fallback credentials could not create or update the configured admin user; "
            "checking whether the configured admin already works"
        )

    if credentials_have_admin_access(base_url, target_user, target_password):
        print(f"GeoServer admin credentials are already configured for user '{target_user}'")
        return 0

    if credentials_work(base_url, target_user, target_password):
        print(
            f"Configured GeoServer user '{target_user}' exists but does not have admin access; "
            "trying first-boot fallback credentials to repair the role assignment"
        )

    if not fallback_admin_has_access(base_url):
        return warn_or_fail("Configured credentials and first-boot fallback credentials were both rejected")

    print("Applying GeoServer admin credentials with first-boot fallback credentials")

    if target_user == DEFAULT_ADMIN_USER:
        if not update_own_password(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD, target_password):
            time.sleep(2)
            if not update_own_password(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD, target_password):
                return warn_or_fail("GeoServer admin password update failed")
    else:
        if not ensure_user(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD, target_user, target_password):
            return warn_or_fail(f"GeoServer admin user '{target_user}' could not be created or updated")
        if not ensure_role_assignment(base_url, DEFAULT_ADMIN_USER, DEFAULT_ADMIN_PASSWORD, target_user, "ADMIN"):
            return warn_or_fail(f"GeoServer ADMIN role could not be assigned to user '{target_user}'")

    if not credentials_work(base_url, target_user, target_password):
        return warn_or_fail(f"GeoServer did not accept configured credentials for user '{target_user}'")

    if disable_default_admin and target_user != DEFAULT_ADMIN_USER:
        if set_user_enabled(base_url, target_user, target_password, DEFAULT_ADMIN_USER, False):
            print("Default GeoServer admin user was disabled")
        else:
            return warn_or_fail("Default GeoServer admin user could not be disabled")

    print(f"GeoServer admin credentials are configured for user '{target_user}'")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
