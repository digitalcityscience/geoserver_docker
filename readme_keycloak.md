## Keycloak Integration (GeoServer – OpenID Connect)

GeoServer is integrated with Keycloak using OpenID Connect (OIDC) for authentication and role-based authorization.

⸻

GeoServer Configuration (OIDC Filter)

GeoServer uses the OpenIdConnectAuthenticationFilter with the following core settings:

To fill in Keycloak server details:
• https://keycloak.domain/realms/realmName/.well-known/openid-configuration

• Client ID: geoserver
• Role source: AccessToken
• Username mapping: preferred_username
• Roles claim: realm_access.roles
• Scopes: openid profile email
• PKCE: enabled
• Bearer tokens: allowed (for API access)

Keycloak endpoints used:
• Authorization endpoint
• Token endpoint
• Userinfo endpoint
• Logout endpoint

The redirectUri must match the GeoServer base URL
(e.g. http://localhost:8080/geoserver/ in development).

⸻

Keycloak Setup (Required)

In Keycloak, the following must be configured:

Realm
• Create a dedicated realm (e.g. geoserver-realm)

Client
• Create a confidential client
• Client ID must match GeoServer (geoserver)
• Enable:
• Standard Flow
• Direct Access Grants (if API access is needed)
• Configure valid redirect URIs:
• http://localhost:8080/geoserver/_ (dev)
• https://<domain>/geoserver/_ (prod)

Roles
• Define realm roles (e.g. ADMIN, GROUP_ADMIN)
• Assign roles to users
• Roles must appear in realm_access.roles

⸻

⚠️ IMPORTANT – Filter Chains

After creating the OIDC filter in GeoServer:

➡️ Go to Security → Filter Chains
➡️ Add keycloak-auth to the right-hand (Selected) column
➡️ Apply it to the relevant chains (e.g. web, rest)

If the filter is not selected in the filter chain, authentication will NOT work.
