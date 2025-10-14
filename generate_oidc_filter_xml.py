#!/usr/bin/env python3
"""
generate_oidc_filter_xml.py

Reads OIDC/Keycloak settings from environment variables and writes a
GeoServer OpenID Connect filter XML file.

- Idempotent content (same env -> same XML)
- Validates booleans and basic URL shape
- Keeps 'cliendId' tag name (as seen in GeoServer file format)
"""

import os
import sys
import xml.etree.ElementTree as ET
from urllib.parse import urlparse
from dotenv import load_dotenv
load_dotenv(".env.dev")

# ---------- Helpers ----------

def env(name: str, default: str = None, required: bool = False) -> str:
    val = os.environ.get(name, default)
    if required and (val is None or val.strip() == ""):
        print(f"[ERROR] missing required env: {name}", file=sys.stderr)
        sys.exit(2)
    return val

def env_bool(name: str, default: bool = False) -> str:
    """
    Returns 'true'/'false' strings (lowercase) suitable for XML fields.
    Accepted truthy: '1','true','yes','on'
    """
    raw = os.environ.get(name, None)
    if raw is None:
        return "true" if default else "false"
    truthy = {"1", "true", "yes", "on"}
    return "true" if raw.strip().lower() in truthy else "false"

def must_be_url(name: str, value: str):
    if not value:
        print(f"[ERROR] {name} cannot be empty", file=sys.stderr)
        sys.exit(3)
    parsed = urlparse(value)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        print(f"[ERROR] {name} must be an absolute http(s) URL: {value}", file=sys.stderr)
        sys.exit(3)

# ---------- Load config from env ----------

# output path
OUTPUT_XML = env("OIDC_XML_OUT", "./openIdConnectAuthentication.xml")

# optional id (leave empty to skip)
FILTER_ID = os.environ.get("OIDC_FILTER_ID", "")

FILTER_NAME               = env("OIDC_FILTER_NAME", "keycloak-auth")
ROLE_SOURCE               = env("OIDC_ROLE_SOURCE", "AccessToken")

OIDC_CLIENT_ID            = env("OIDC_CLIENT_ID", required=True)
OIDC_CLIENT_SECRET        = env("OIDC_CLIENT_SECRET", required=True)

OIDC_TOKEN_URI            = env("OIDC_TOKEN_URI", required=True)
OIDC_AUTH_URI             = env("OIDC_AUTH_URI", required=True)
OIDC_REDIRECT_URI         = env("OIDC_REDIRECT_URI", required=True)
OIDC_USERINFO_URI         = env("OIDC_USERINFO_URI", required=True)
OIDC_INTROSPECT_URI       = env("OIDC_INTROSPECT_URI", required=True)
OIDC_LOGOUT_URI           = env("OIDC_LOGOUT_URI", required=True)
OIDC_JWKS_URI             = env("OIDC_JWKS_URI", required=True)

OIDC_SCOPES               = env("OIDC_SCOPES", "openid profile email")

OIDC_ENABLE_REDIRECT_ENTRYPOINT = env_bool("OIDC_ENABLE_REDIRECT_ENTRYPOINT", False)
OIDC_FORCE_TOKEN_HTTPS          = env_bool("OIDC_FORCE_TOKEN_HTTPS", True)
OIDC_FORCE_AUTH_HTTPS           = env_bool("OIDC_FORCE_AUTH_HTTPS", True)
OIDC_LOGIN_ENDPOINT             = env("OIDC_LOGIN_ENDPOINT", "/j_spring_oauth2_openid_connect_login")
OIDC_LOGOUT_ENDPOINT            = env("OIDC_LOGOUT_ENDPOINT", "/j_spring_oauth2_openid_connect_logout")
OIDC_ALLOW_UNSECURE_LOGGING     = env_bool("OIDC_ALLOW_UNSECURE_LOGGING", False)
OIDC_PRINCIPAL_KEY              = env("OIDC_PRINCIPAL_KEY", "preferred_username")
OIDC_TOKEN_ROLES_CLAIM          = env("OIDC_TOKEN_ROLES_CLAIM", "resource_access.geoserver.roles")
OIDC_RESPONSE_MODE              = env("OIDC_RESPONSE_MODE", "form_post")
OIDC_POST_LOGOUT_REDIRECT_URI   = env("OIDC_POST_LOGOUT_REDIRECT_URI", OIDC_REDIRECT_URI)
OIDC_SEND_CLIENT_SECRET         = env_bool("OIDC_SEND_CLIENT_SECRET", True)
OIDC_ALLOW_BEARER_TOKENS        = env_bool("OIDC_ALLOW_BEARER_TOKENS", True)
OIDC_USE_PKCE                   = env_bool("OIDC_USE_PKCE", True)
OIDC_ENFORCE_TOKEN_VALIDATION   = env_bool("OIDC_ENFORCE_TOKEN_VALIDATION", True)
OIDC_CACHE_AUTHENTICATION       = env_bool("OIDC_CACHE_AUTHENTICATION", False)

# Basic URL sanity checks
for name, val in [
    ("OIDC_TOKEN_URI", OIDC_TOKEN_URI),
    ("OIDC_AUTH_URI", OIDC_AUTH_URI),
    ("OIDC_REDIRECT_URI", OIDC_REDIRECT_URI),
    ("OIDC_USERINFO_URI", OIDC_USERINFO_URI),
    ("OIDC_INTROSPECT_URI", OIDC_INTROSPECT_URI),
    ("OIDC_LOGOUT_URI", OIDC_LOGOUT_URI),
    ("OIDC_JWKS_URI", OIDC_JWKS_URI),
    ("OIDC_POST_LOGOUT_REDIRECT_URI", OIDC_POST_LOGOUT_REDIRECT_URI),
]:
    must_be_url(name, val)

# ---------- Build XML ----------

root = ET.Element("openIdConnectAuthentication")

if FILTER_ID.strip():
    id_el = ET.SubElement(root, "id")
    id_el.text = FILTER_ID

name_el = ET.SubElement(root, "name")
name_el.text = FILTER_NAME

cls_el = ET.SubElement(root, "className")
cls_el.text = "org.geoserver.security.oauth2.OpenIdConnectAuthenticationFilter"

role_src = ET.SubElement(root, "roleSource", {
    "class": "org.geoserver.security.oauth2.OpenIdConnectFilterConfig$OpenIdRoleSource"
})
role_src.text = ROLE_SOURCE

# NOTE: GeoServer config uses the tag name 'cliendId' (typo in schema), keep it as-is!
client_id_el = ET.SubElement(root, "cliendId")
client_id_el.text = OIDC_CLIENT_ID

client_secret_el = ET.SubElement(root, "clientSecret")
client_secret_el.text = OIDC_CLIENT_SECRET

ET.SubElement(root, "accessTokenUri").text  = OIDC_TOKEN_URI
ET.SubElement(root, "userAuthorizationUri").text = OIDC_AUTH_URI
ET.SubElement(root, "redirectUri").text     = OIDC_REDIRECT_URI
ET.SubElement(root, "checkTokenEndpointUrl").text = OIDC_USERINFO_URI
ET.SubElement(root, "introspectionEndpointUrl").text = OIDC_INTROSPECT_URI
ET.SubElement(root, "logoutUri").text       = OIDC_LOGOUT_URI

ET.SubElement(root, "scopes").text = OIDC_SCOPES

ET.SubElement(root, "enableRedirectAuthenticationEntryPoint").text = OIDC_ENABLE_REDIRECT_ENTRYPOINT
ET.SubElement(root, "forceAccessTokenUriHttps").text  = OIDC_FORCE_TOKEN_HTTPS
ET.SubElement(root, "forceUserAuthorizationUriHttps").text = OIDC_FORCE_AUTH_HTTPS

ET.SubElement(root, "loginEndpoint").text  = OIDC_LOGIN_ENDPOINT
ET.SubElement(root, "logoutEndpoint").text = OIDC_LOGOUT_ENDPOINT

ET.SubElement(root, "allowUnSecureLogging").text = OIDC_ALLOW_UNSECURE_LOGGING

ET.SubElement(root, "principalKey").text = OIDC_PRINCIPAL_KEY
ET.SubElement(root, "jwkURI").text       = OIDC_JWKS_URI

ET.SubElement(root, "tokenRolesClaim").text = OIDC_TOKEN_ROLES_CLAIM
ET.SubElement(root, "responseMode").text    = OIDC_RESPONSE_MODE

ET.SubElement(root, "postLogoutRedirectUri").text = OIDC_POST_LOGOUT_REDIRECT_URI

ET.SubElement(root, "sendClientSecret").text    = OIDC_SEND_CLIENT_SECRET
ET.SubElement(root, "allowBearerTokens").text   = OIDC_ALLOW_BEARER_TOKENS
ET.SubElement(root, "usePKCE").text             = OIDC_USE_PKCE
ET.SubElement(root, "enforceTokenValidation").text = OIDC_ENFORCE_TOKEN_VALIDATION
ET.SubElement(root, "cacheAuthentication").text = OIDC_CACHE_AUTHENTICATION

# Pretty print
ET.indent(root, space="  ")
tree = ET.ElementTree(root)

# ---------- Write ----------
try:
    out_dir = os.path.dirname(os.path.abspath(OUTPUT_XML)) or "."
    os.makedirs(out_dir, exist_ok=True)
    tree.write(OUTPUT_XML, encoding="utf-8", xml_declaration=True)
    print(f"[ok] Wrote OIDC filter XML → {OUTPUT_XML}")
except Exception as e:
    print(f"[ERROR] Failed to write XML: {e}", file=sys.stderr)
    sys.exit(4)