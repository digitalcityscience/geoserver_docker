import os
import sys
import requests
from requests.auth import HTTPBasicAuth

def update_geoserver_password(
    geoserver_url,
    admin_user,
    admin_pass,
    new_user,
    new_pass
):
    url = f"{geoserver_url}/rest/security/self/password"
    headers = {"Content-Type": "text/plain"}
    response = requests.put(
        url,
        data=new_pass,
        headers=headers,
        auth=HTTPBasicAuth(admin_user, admin_pass)
    )
    if response.status_code == 200:
        print("✅ GeoServer password updated successfully.")
    else:
        print(f"❌ Failed to update password: {response.status_code} {response.text}")
        sys.exit(1)

if __name__ == "__main__":
    # Read from environment or arguments
    GEOSERVER_URL = os.environ.get("GEOSERVER_URL", "http://localhost:8080/geoserver")
    ADMIN_USER = os.environ.get("GEOSERVER_ADMIN_USER", "admin")
    ADMIN_PASS = os.environ.get("GEOSERVER_ADMIN_PASSWORD", "geoserver")
    NEW_USER = os.environ.get("GEOSERVER_NEW_USER", ADMIN_USER)
    NEW_PASS = os.environ.get("GEOSERVER_NEW_PASSWORD", "newpassword")

    update_geoserver_password(
        GEOSERVER_URL,
        ADMIN_USER,
        ADMIN_PASS,
        NEW_USER,
        NEW_PASS
    )