1. Hostnames (assumed)
   • Keycloak (auth server): https://auth.dcs.hcu-hamburg.de
   • GeoServer (behind nginx): https://dev.geoserver.tosca.dcs.hcu-hamburg.de
   • Realm: prod-realm
   • Client ID (OIDC): geoserver

⸻

1. Keycloak — container & global options

1.1 Run Keycloak with hostname + proxy + SameSite

Make sure the container starts with hostname v2 and cookies that work cross-site:

# keycloak service (compose excerpt)

environment:
KC_HOSTNAME: auth.dcs.hcu-hamburg.de
KC_PROXY: edge
KC_HOSTNAME_STRICT_HTTPS: "true"
KC_HTTP_COOKIE_SAME_SITE: none

# (plus your DB settings)

ports:

- "8765:8080"

Verify inside the container:

docker exec -it kc-server sh -c "/opt/keycloak/bin/kc.sh show-config" | egrep -i 'hostname|proxy|same-site|http|https'

You should see:
• kc.hostname = auth.dcs.hcu-hamburg.de
• kc.proxy-headers = xforwarded
• kc.http-cookie-same-site = none
• kc.hostname-strict-https = true

⸻

2. Keycloak — realm & client configuration

2.1 Create Realm
• Realm name: prod-realm

2.2 Create Client (OIDC)
• Client ID: geoserver
• Type: OpenID Connect
• Access settings
• Root URL: https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver
• Home URL: https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver/web
• Valid redirect URIs: https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver/*
• Valid post logout redirect URIs: same as above (or the /web)
• Web Origins: https://dev.geoserver.tosca.dcs.hcu-hamburg.de
• Admin URL: https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver
• Capability config
• ✅ Standard flow
• ✅ Direct access grants (only if you want password grant for scripts)
• (Implicit/OIDC Device/CIBA off unless needed)
• Client scopes → Dedicated scope
• Add Audience mapper:
• Mapper type: Audience
• Name: geoserver
• Included Client Audience: geoserver
• Add to access token: On
• Add to token introspection: On
• (ID token Off unless UI needs it)

2.3 Roles (optional but used by you)
• Client role on geoserver: ADMIN
Assign this to users that should be admins in GeoServer (and/or map via composites to GeoServer roles).

2.4 Service account (optional)
• Client → Service accounts roles: assign geoserver:ADMIN (if you’ll call Keycloak with client credentials).

2.5 Realm CSP tweak (to allow flows from GeoServer)

Realm settings → Security defenses → Headers → Content-Security-Policy:

frame-src 'self';
frame-ancestors 'self' https://dev.geoserver.tosca.dcs.hcu-hamburg.de;
object-src 'none';
script-src 'self' 'unsafe-inline';
style-src 'self' 'unsafe-inline';
form-action 'self' https://dev.geoserver.tosca.dcs.hcu-hamburg.de

2.6 Discovery (well-known) URL (for reference)

https://auth.dcs.hcu-hamburg.de/realms/prod-realm/.well-known/openid-configuration

⸻

3. NGINX — reverse proxy for GeoServer

Goal: override too-strict CSP from upstream so Chrome allows the POST redirect to Keycloak.

In the server { … } (or specific /geoserver/ location) that fronts GeoServer:

# --- CSP override - required for Keycloak login from GeoServer UI ---

proxy_hide_header Content-Security-Policy;
proxy_hide_header Content-Security-Policy-Report-Only;

add_header Content-Security-Policy \
"default-src 'self'; \
 script-src 'self' 'unsafe-inline' 'unsafe-eval'; \
 style-src 'self' 'unsafe-inline'; \
 img-src 'self' data: https:; \
 font-src 'self' data:; \
 connect-src 'self' https://auth.dcs.hcu-hamburg.de; \
 form-action 'self' https://auth.dcs.hcu-hamburg.de; \
 frame-ancestors 'self';" always;

# (plus your normal proxy_pass to the GeoServer backend)

Reload:

nginx -t && systemctl reload nginx

# or docker compose restart nginx

⸻

4. GeoServer — application settings

4.1 Proxy base URL (important for correct redirects)

In $GEOSERVER_DATA_DIR/global.xml (or via env), set:

<proxyBaseUrl>https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver</proxyBaseUrl>

(You already template this via PROXY_BASE_URL, keep it.)

4.2 OpenID Connect filter (GeoServer UI)
• Enable the OpenID Connect filter (UI: Security → Authentication → Filters)
• Discovery: https://auth.dcs.hcu-hamburg.de/realms/prod-realm/.well-known/openid-configuration
• Client ID: geoserver
• Client Secret: (if confidential; public if only browser auth)
• Principal key: preferred_username
• Role source: Access Token
Role claim path: resource_access.geoserver.roles
• PKCE: S256 (recommended)
• Filter Chains: put the OIDC filter first in web, rest, and default chains.
• Role filter: enable so roles in token are enforced.

GeoServer recognizes only its internal roles (e.g., ROLE_ADMINISTRATOR, ROLE_PUBLISHER, ROLE_READER) unless you add custom role service entries. Use Keycloak composite roles if you want business roles to map to these.

⸻

5. Users & roles
   • Create user(s) in prod-realm.
   • Assign client role geoserver:ADMIN (or composites mapping to GeoServer roles).
   • Login should make them admin in GeoServer if your role mapping aligns (or map to ROLE_ADMINISTRATOR on the GeoServer side).

⸻

6. Test the flows

6.1 Browser login 1. Open Chrome → https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver/web 2. Click Login
• Network tab should show POST to /web/j_spring_oauth2_openid_connect_login → 302 to Keycloak, then back. 3. Verify no CSP errors in Console.
If you see form-action 'self' blocks, re-check NGINX and Realm CSP.

6.2 REST with token (optional)

# Token

curl -s -X POST \
 -d "client_id=geoserver" \
 -d "grant_type=client_credentials" \
 -d "client_secret=YOUR_SECRET" \
 "https://auth.dcs.hcu-hamburg.de/realms/prod-realm/protocol/openid-connect/token" \
| jq -r .access_token > token.txt

# GeoServer API

curl -H "Authorization: Bearer $(cat token.txt)" \
 -H "Accept: application/json" \
 https://dev.geoserver.tosca.dcs.hcu-hamburg.de/geoserver/rest/workspaces

6.3 Logout (SSO)
• Use app logout, then (if needed) call:

https://auth.dcs.hcu-hamburg.de/realms/prod-realm/protocol/openid-connect/logout?id_token_hint=...

⸻

7. Chrome-specific gotchas (why this was failing)
   • CSP form-action blocked the POST to Keycloak → fixed by NGINX CSP override and Realm CSP.
   • Cross-site cookies: Set KC_HTTP_COOKIE_SAME_SITE=none and serve HTTPS everywhere.
   • Hostname awareness: KC_HOSTNAME, KC_PROXY=edge, and strict-https ensure redirect URIs and cookies match your public host.

⸻

8. Quick checklist (copy/paste)
   • KC env: KC_HOSTNAME, KC_PROXY=edge, KC_HOSTNAME_STRICT_HTTPS=true, KC_HTTP_COOKIE_SAME_SITE=none
   • Client geoserver: Standard flow ON; redirects/origins set to GeoServer URL
   • Audience mapper: include geoserver in access token
   • Realm CSP set to allow GeoServer origin (frame/form/script/style)
   • NGINX CSP override for the GeoServer vhost (allow auth.dcs.hcu-hamburg.de in form-action & connect-src)
   • GeoServer OIDC filter first in web/rest/default chains
   • proxyBaseUrl points to the public GeoServer URL
   • Roles aligned (Keycloak → GeoServer)

That’s it — this is the full, reproducible path from zero to a working Chrome-friendly SSO with Keycloak + GeoServer behind NGINX.
