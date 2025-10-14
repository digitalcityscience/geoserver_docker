KC=https://auth.dcs.hcu-hamburg.de/realms/geoserver-realm/protocol/openid-connect/token
curl -s -X POST "$KC" \
 -d grant_type=password \
 -d client_id=geoserver \
 -d client_secret=kdiPeHpRHCy5VRQJugM77QlXa7jo2SA1 \
 -d username=geoclient \
 -d password=145313 | jq -r .access_token > /tmp/tok

asagisina gore token lar calisiyor

KC="https://auth.dcs.hcu-hamburg.de/realms/geoserver-realm/protocol/openid-connect/token"
curl -v -X POST "$KC" \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "grant_type=client_credentials" \
 -d "client_id=geoserver" \
 -d "client_secret=kdiPeHpRHCy5VRQJugM77QlXa7jo2SA1"

https://auth.dcs.hcu-hamburg.de/realms/geoserver-realm/protocol/openid-connect/logout
https://auth.dcs.hcu-hamburg.de/realms/geoserver-realm/protocol/openid-connect/logout?post_logout_redirect_uri=http://localhost:8080/geoserver/&client_id=geoserver

/j_spring_oauth2_openid_connect_logout,/j_spring_oauth2_openid_connect_logout/,/j_spring_security_logout, /j_spring_security_logout/,/logout
/j_spring_security_logout, /j_spring_security_logout/,/logout

https://auth.dcs.hcu-hamburg.de/realms/geoserver-realm/protocol/openid-connect/userinfo
https://auth.dcs.hcu-hamburg.de/realms/geoserver-realm/protocol/openid-connect/token/introspect

Proof Key for Code Exchange Code Challenge Method >> 256 yaptik ve calisiyor > Proof Key of Code Exchange geoserve tarafinda on yaptik

curl -X GET \
 http://localhost:8080/geoserver/rest/workspaces.json \
 -H "Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJJVTAxRVNqVlIydlRyWnZNTjlHaERJZUhYTnowQUxQU2RmUUpPNDQ0QXc4In0.eyJleHAiOjE3NTk0MTUxOTQsImlhdCI6MTc1OTQxNDg5NCwianRpIjoiMTQ4Yjg2NDUtZjkwNC00MjYwLTgzYWMtMGNlN2QyYjg5MTNkIiwiaXNzIjoiaHR0cHM6Ly9hdXRoLmRjcy5oY3UtaGFtYnVyZy5kZS9yZWFsbXMvZ2Vvc2VydmVyLXJlYWxtIiwiYXVkIjpbImdlb3NlcnZlciIsImFjY291bnQiXSwic3ViIjoiM2FmOWU2NzAtYTkyMS00ZjljLTlmNTItODU3YmMyNzY5ODI2IiwidHlwIjoiQmVhcmVyIiwiYXpwIjoiZ2Vvc2VydmVyIiwic2lkIjoiYzM3NGQ2NmUtMDFhMi00ZDU2LWI5ZmQtMWI3MzIwMTE3MTVkIiwiYWNyIjoiMSIsImFsbG93ZWQtb3JpZ2lucyI6WyJodHRwOi8vbG9jYWxob3N0OjgwODAiXSwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbIm9mZmxpbmVfYWNjZXNzIiwiZGVmYXVsdC1yb2xlcy1nZW9zZXJ2ZXItcmVhbG0iLCJ1bWFfYXV0aG9yaXphdGlvbiJdfSwicmVzb3VyY2VfYWNjZXNzIjp7Imdlb3NlcnZlciI6eyJyb2xlcyI6WyJhZG1pbiIsInB1Ymxpc2hlciIsIkFETUlOIl19LCJhY2NvdW50Ijp7InJvbGVzIjpbIm1hbmFnZS1hY2NvdW50IiwibWFuYWdlLWFjY291bnQtbGlua3MiLCJ2aWV3LXByb2ZpbGUiXX19LCJzY29wZSI6InByb2ZpbGUgZW1haWwiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsIm5hbWUiOiJ0ZXN0IG9ydGFrIiwicHJlZmVycmVkX3VzZXJuYW1lIjoiZ2VvY2xpZW50IiwiZ2l2ZW5fbmFtZSI6InRlc3QiLCJmYW1pbHlfbmFtZSI6Im9ydGFrIiwiZW1haWwiOiJvcnR0YWtAZ21haWwuY29tIn0.MRlqauhHrv1SOB0o2WUqII95RbrVh_9xkr5eXj-DCqq16mr6iUN3U89NG69bqgveldg_ye_uhmVNVZ0n3b9zaw0veNDwgC9SDHAs0jh50RsGMofy7-l0BIT1Y7xaUbRPffGv7kFn32Oy8IUKj0EDH3Dbfkj2QOYCDle1NZV-t7lC12aIw_uR5MmYGn15LCXaQL6ahe8DxXnujUx2j3PKVscy_eThOrkxR84l7oYDfY32GfGsH-Z84kKz2i64BlyT5HhTw0aAM04XduuoxTRsgVCt6_iHiSRjMgWcYijtMb1pWSJ0hGvjY1PjEU54QFNxoSI" \
 -H "Accept: application/json"

==

# CSP override - Keycloak login için gerekli

proxy_hide_header Content-Security-Policy;
proxy_hide_header Content-Security-Policy-Report-Only;

add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://auth.dcs.hcu-hamburg.de; form-action 'self' https://auth.dcs.hcu-hamburg.de; frame-ancestors 'self';" always;

yukariyi bizim nginx onune ekledik.
