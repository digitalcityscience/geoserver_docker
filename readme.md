🚀 GeoServer Docker Automation

A ready-to-use Docker setup for GeoServer.
Build custom GeoServer images with selected plugins, run them with PostgreSQL/MobilityDB, and switch easily between development (localhost) and production (domain) setups.

⸻

⚡ Quick Start

Just pick your environment when starting:

🧑‍💻 Local Development

copy env_dev_sample as .env.dev

make up ENV=dev

👉 Opens at http://localhost:8080/geoserver

⸻

🌐 Server / Production (with domain + reverse proxy)

copy env_prod_sample as .env.prod

make up ENV=prod

👉 Check the all details of env files for production.

⸻

🛠 Features
	•	Automatic Plugin Installation – define plugins once, they’re fetched & installed
	•	Custom Version Support – any GeoServer version via .env
	•	Dev-Ready Stack – includes MobilityDB for PostGIS mobility data testing
	•	Automated Workflow – Makefile simplifies build/run/clean

⸻

📂 Repository Structure

geoserver-docker/

├── docker-compose.yml          # Local stack (GeoServer + MobilityDB)

├── Dockerfile                  # Custom GeoServer image build

├── Makefile                    # Automation for setup/build/run/clean

├── download_plugins.sh          # Script to fetch plugins

├── entrypoint.sh                # Custom entrypoint (GeoServer bootstrap)

├── set_geoserver_password.py    # Utility to reset admin password

├── readme.md                    # This file

Generated/ignored at runtime:

├── geoserver_data/             # GeoServer data directory (ignored)

├── plugins/                    # Downloaded plugin JARs (ignored)


⸻

⚙️ Environment Configuration

The system uses separate env files:
	•	.env.dev → localhost development
	•	.env.prod → server/prod with domain + HTTPS

⸻

▶️ Makefile Tasks

	•	make setup – create geoserver_data/ and plugins/ if missing
	
	•	make plugins – download GeoServer plugins (from PLUGINS list)
	
	•	make build – build the Docker image with plugins
	
	•	make up ENV=dev – run stack with .env.dev
	
	•	make up ENV=prod – run stack with .env.prod
	
	•	make down – stop containers
	
	•	make clean – stop & remove containers, volumes, and image
	
	•	make rebuild ENV=prod – full rebuild cycle

⸻

📦 Plugin Setup

To customize plugins:
	•	Edit the PLUGINS list at the top of the Makefile, or
	•	Run manually:

✅ Tip: Ensure plugins/ is not in .dockerignore, otherwise they won’t be included in the image.

⸻

📌 Plugin Naming Guide

When adding plugins to the PLUGINS list (or running download_plugins.sh),
use the plugin name exactly as it appears in the ZIP filename on the GeoServer SourceForge extensions page.

Rule:

geoserver-<VERSION>-<PLUGIN>-plugin.zip → <PLUGIN>


⸻

Examples (GeoServer 2.27.2)

ZIP filename	 Plugin name to use

- geoserver-2.27.2-mbstyle-plugin.zip	> mbstyle

- geoserver-2.27.2-vectortiles-plugin.zip	> vectortiles

- geoserver-2.27.2-csw-iso-plugin.zip	> csw-iso
⸻

Example Usage

Download VectorTiles + MBStyle for GeoServer 2.27.2 >>  ./download_plugins.sh "2.27.2" "vectortiles mbstyle"

Download NetCDF and OGC API Features  >> ./download_plugins.sh "2.27.2" "netcdf ogcapi-features"

---

🌍 Community Modules (Optional)

In addition to official GeoServer plugins (downloaded via the PLUGINS list), you can also include community modules by specifying their full URLs.
These are usually published under the GeoServer build server.

📌 Example: OAuth2 / OpenID Connect plugin (community)


 
Community plugins (full URLs, space separated, NOT commas!)

COM_PLUGINS = \
  https://build.geoserver.org/geoserver/2.27.x/community-latest/geoserver-2.27-SNAPSHOT-sec-oauth2-openid-connect-plugin.zip

Notes:

	•	Multiple URLs must be space-separated (not commas).
	
	•	Community plugins are less stable than official ones and may change between versions.
	
	•	These will be automatically downloaded and extracted into the plugins/ folder during make build.

✅ Example with multiple community plugins:

make COM_PLUGINS="https://url/plugin1.zip https://url/plugin2.zip"


⸻
