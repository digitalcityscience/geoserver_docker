# 🚀 GeoServer Docker Automation

A ready-to-use Docker setup for GeoServer.

Build custom GeoServer images with selected plugins, run them with PostgreSQL / MobilityDB, and switch easily between development (localhost) and production (domain) setups.

---

### 🧑‍💻 Local Development

```bash
cp env_dev_sample .env.dev
make up ENV=dev
```

👉 Opens at http://localhost:8080/geoserver

---

### 🌐 Server / Production (with domain + reverse proxy)

```bash
cp env_prod_sample .env.prod
make up ENV=prod
```

👉 Review all values inside `.env.prod` carefully before running in production.

---

### ⚙️ Environment Configuration (Important)

This project is fully driven by environment files:
- `.env.dev` → local development (localhost)  
- `.env.prod` → production / server (domain, HTTPS, reverse proxy)

⚠️ Almost all scripts, Makefile targets, and Docker behavior depend on these env files.  
If an env file is missing, misnamed, or not loaded, things will fail — often silently.

---

### 🗄 JDBC / PostgreSQL Setup (Advanced)

**When do you need this?**  
If you want to:
- Store GeoServer users & roles in PostgreSQL  
- Store GeoServer configuration (workspaces, layers, styles, stores) in PostgreSQL  
- Run GeoServer reliably in production (AWS / on-prem / CI/CD)

👉 You must run GeoServer together with PostgreSQL  
👉 You must read **[JDBC documentation](./readme_jdbc.md)**

This setup is **not optional** for JDBC-based security or JDBCConfig.

**What this project supports:**
- JDBC User / Role security (PostgreSQL-backed)  
- JDBCConfig / JDBCStore (GeoServer configuration in DB)  
- Separate schemas for:  
  - Security (users, roles)  
  - GeoServer configuration (workspaces, layers, styles)

📖 All details, caveats, and required UI steps are documented in:  
**`readme_jdbc.md`**

> 💡 If you skip that document, things will look broken — even if they are not.

---

### 📂 Script Location Matters (Very Important)

Some scripts must be executed from the **project root**, next to the env files.

**Example:**
```bash
scripts/activate_jdbcS_settings.sh
```

This script expects:
- `.env.dev` or `.env.prod` to be in the same directory level  
- Environment variables to be auto-loaded

❌ Running it from another folder  
❌ Copying it elsewhere  
❌ Renaming env files  

→ will cause failures.

**Rule of thumb:**  
If the script cannot see the env file, it cannot work.

---

### 🛠 Features
- **Automatic Plugin Installation** – define plugins once, they’re fetched & installed  
- **Custom Version Support** – any GeoServer version via `.env`  
- **Dev-Ready Stack** – includes MobilityDB for PostGIS mobility data testing  
- **Automated Workflow** – Makefile simplifies build / run / clean  
- **JDBC-ready architecture** for production deployments

---

### ▶️ Makefile Tasks

| Command | Description |
|--------|-------------|
| `make which-env ENV=dev` | Shows the active environment and loaded `.env` file |
| `make build ENV=dev` | Builds Docker images without cache |
| `make up ENV=dev` | Starts the stack using `.env.dev` |
| `make up ENV=prod` | Starts the stack using `.env.prod` (runs safety checks) |
| `make down ENV=dev` | Stops all containers |
| `make restart ENV=dev` | Restarts the stack (`down` + `up`) |
| `make logs` | Shows logs from all containers |
| `make logs geoserver` | Shows logs only from the GeoServer container |
| `make rebuild ENV=prod` | Rebuilds images without cache and restarts the stack |
| `make rmVolumes ENV=dev` | ⚠️ **Removes all volumes (DATA LOSS)** |

---

### 📦 GeoServer Plugins (Official & Community)

GeoServer plugins are configured **only via environment files**.  
There is **no manual download**, **no URL handling**, and **no Makefile editing** required.

You only need to edit **one place**:
- `.env.dev` for local development  
- `.env.prod` for production

---

#### Official Plugins

List official plugins as **comma-separated names**:

```env
OFFICIAL_PLUGINS=gdal,monitor,vectortiles,mbstyle
```

**Rules:**
- Use the **plugin identifier**, not the full ZIP name  
- Names must match official GeoServer plugin naming  
- Docker automatically downloads and installs the correct version  
- Plugin version always matches `GEOSERVER_VERSION`

---

#### Community Plugins

Community plugins are also listed as **comma-separated names**:

```env
COMMUNITY_PLUGINS=jdbcconfig,jdbcstore,sec-oauth2-openid-connect
```

**Notes:**
- These are **GeoAssistant community modules**  
- Versions are resolved automatically  
- No URLs are required  
- Community plugins may be less stable than official ones

---

#### Applying Plugin Changes

After changing plugin lists in `.env.dev` or `.env.prod`, you **must rebuild** the image:

```bash
make rebuild ENV=dev
make rebuild ENV=prod
```

Docker will handle:
- Resolving plugin versions  
- Downloading plugin archives  
- Installing them into the GeoServer image

---

#### Important Notes

- Plugin configuration is **environment-specific**  
- Development and production may use **different plugin sets**  
- Manual plugin downloads are **not supported**  
- If a plugin fails to load, check GeoServer logs first  

👉 **Edit the env file — Docker does the rest.**

---

### Final Note

This repository supports:
- Simple local testing  
- Serious JDBC-backed production setups  

—but the **JDBC path requires reading `readme_jdbc.md`**.
