GeoServer ↔ OpenID Connect (Keycloak) — Minimal

Purpose
Enable SSO for GeoServer using an OpenID Connect (OIDC) provider (e.g., Keycloak). Most endpoints are discovered automatically via the OIDC discovery URL.

⸻

1. Discovery (Recommended)

Use the OIDC discovery endpoint:

https://<OIDC_HOST>/realms/<REALM>/.well-known/openid-configuration

This provides token, authorization, userinfo, and logout endpoints.

⸻

2. Authentication Filter

Configure an OpenID Connect Authentication Filter in GeoServer.

Key settings
• Filter name: oidc-auth
• Class: OpenIdConnectAuthenticationFilter
• Client ID: <CLIENT_ID>
• Client Secret: <CLIENT_SECRET>
• Scopes: openid profile email
• Principal key: preferred_username
• Role source: AccessToken
• Roles claim: realm_access.roles
• PKCE: enabled
• Bearer tokens: allowed

⸻

3. Endpoints (from discovery)

Typically resolved automatically:
• Authorization endpoint
• Token endpoint
• UserInfo endpoint
• Logout endpoint

(Manual override only if discovery is unavailable.)

⸻

4. Redirect URI

Set to GeoServer base URL:

http(s)://<GEOSERVER_HOST>/geoserver/

Must match the client configuration in the IdP.

⸻

5. Roles & Authorization
   • Roles are read from the access token claim (e.g., realm_access.roles).
   • Map IdP roles to GeoServer roles via Role Service (e.g., JDBC Role Service).

⸻

6. Security Chain

Place the OIDC filter in the authentication chain before basic auth (if mixed mode is needed).

⸻

7. Notes / Best Practices
   • Keep client secrets out of source control (use env vars).
   • Prefer discovery URL over hardcoded endpoints.
   • Enable PKCE for public/SPA-like flows.
   • Test login, role mapping, and logout once after setup.

⸻

Result
Users authenticate via OIDC, GeoServer trusts the IdP, extracts username and roles from tokens, and enforces authorization based on mapped roles.
