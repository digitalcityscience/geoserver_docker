# GeoServer Docker – Simple, Production-Ready

> 🎯 **In one sentence:**  
> Run GeoServer 2.28.3 in Docker. Works out of the box. Add PostgreSQL later if you need it.

---

## 🚀 Get Started in 3 Minutes

### Step 1: Set Your Environment (Do This Once)
```bash
# For development (default):
make set-env-dev

# For production (when ready):
make set-env-prod
```
> 💡 This sets your default environment permanently.

### Step 2: Bootstrap & Start
```bash
# Development:
make init-dev    # Create .env.dev from template
make up          # Start GeoServer + PostgreSQL

# Production:
make init-prod   # Create .env.prod from template
vim .env.prod    # Edit passwords, URLs, etc.
make validate    # Run safety checks (mandatory)
make up          # Start
```

✅ **Done!**  
🌐 Open: http://localhost:8080/geoserver  
🔐 Login: `admin` / `geoserver`

> 🔄 **Check your current environment anytime:**  
> `make current-env`

---

## 🎮 Makefile Cheat Sheet

### 🎯 Environment Management (Persistent)
```bash
make set-env-dev          # Set dev as default (no more ENV=dev typing)
make set-env-prod         # Set prod as default ⚠️
make current-env          # Show which environment is active
```

### 🔄 Lifecycle (SERVICE defaults to `geoserver`)
```bash
make up                   # Start db + geoserver
make up-all               # Same as up (explicit)
make start / stop / down  # Container control
make restart              # Full restart (down + up)
```

### 🔍 Inspection & Debugging
```bash
make ps                   # Show container status
make logs                 # Show geoserver logs (last 100 lines)
make logs-follow          # Follow logs in real-time (Ctrl+C to stop)
make health               # Quick HTTP health check
make shell-geoserver      # Open shell inside GeoServer container
make shell-db             # Open shell inside PostgreSQL container
```

### 🔨 Build & Rebuild
```bash
make build                # Rebuild image (no cache – clean build)
make build-cache          # Rebuild image (with cache – faster for dev)
make rebuild              # Build + restart (db+geoserver if SERVICE=geoserver)
```

### ✅ Validation
```bash
make validate             # Production safety checks (auto-runs if ENV=prod)
make verify               # Runtime validation inside container
make verify-jdbc          # Full JDBC mode validation
make verify-jdbc-role     # Validate JDBC role service only
make verify-jdbc-auth     # Validate JDBC auth service only
```

### 🧹 Cleanup ⚠️
```bash
make rmVolumes            # Remove volumes (CONFIRMATION REQUIRED – DATA LOSS)
make clean                # Full cleanup: down -v --remove-orphans
```

### 💡 Pro Tips
```bash
# Override environment temporarily (doesn't change default):
make up ENV=prod          # Use prod just for this command

# Target a different service:
make logs SERVICE=db      # Show database logs instead of geoserver

# Quick status check:
make current-env && make ps && make health
```

---

## ⚙️ Only 5 Settings You Need to Change

Edit these in `.env.dev` or `.env.prod`:

| Variable | Example | What it does |
|----------|---------|-------------|
| `GEOSERVER_ADMIN_PASSWORD` | `MySecurePass!2024` | Sets the admin password (**change this!**) |
| `GEOSERVER_PUBLIC_URL` | `https://maps.yourcompany.com/geoserver` | The URL users see in their browser |
| `PROXY_BASE_URL` | `https://maps.yourcompany.com/geoserver` | Base URL for all generated links (WMS, REST, etc.) |
| `GEOSERVER_CORS_ALLOWED_ORIGINS` | `https://app.yourcompany.com` | Which websites can call your GeoServer API |
| `GEOSERVER_SECURITY_MODE` | `default` | How GeoServer stores config (`default`, `jdbc-role`, etc.) |

> ✅ All other settings have safe defaults. Leave them alone until you need them.

---

## 🔄 Runtime Modes – Pick One

Set `GEOSERVER_SECURITY_MODE` in your `.env` file.

| Mode | Where settings are stored | Needs PostgreSQL? | Use this when… |
|------|--------------------------|-------------------|----------------|
| `default` ⭐ | Simple files (XML) | ❌ No | **Start here.** Works for 90% of cases. |
| `jdbc-role` | Roles in DB, users in files | ✅ Yes | You want role/permission mappings in PostgreSQL. |
| `jdbc-auth-role` | Users + Roles in DB | ✅ Yes | You want full user/role management from PostgreSQL. |
| `jdbc-config` | Everything in DB | ✅ Yes | Advanced use only. You know what you're doing. |

> 🚦 **Golden Rule:** Always start with `default`. Get it working. Then switch modes if you truly need to.

---

### 🔁 How to Switch Modes

```bash
# 1. Edit your .env file
GEOSERVER_SECURITY_MODE=jdbc-role
GEOSERVER_ENABLE_JDBC_ROLE=true

# 2. Rebuild and start with database
make up-all

# 3. Run JDBC activation (required)
make activate-jdbc

# 4. Verify the mode is active
make verify-jdbc
```

> 💡 **Tip:** Use `make up-all` (not just `up`) when enabling any JDBC mode, because PostgreSQL must be running.

---

### 🧭 JDBC ROLE vs JDBC AUTH (Quick Mental Model)

| Component | What it manages | Table examples |
|-----------|----------------|----------------|
| **JDBC ROLE** | Role definitions and user→role mappings | `roles`, `user_roles`, `group_roles` |
| **JDBC AUTH** | User/group accounts and credentials | `users`, `groups`, `user_props` |

- `jdbc-role` mode → Enables **JDBC ROLE** only (users stay file-backed)
- `jdbc-auth-role` mode → Enables **JDBC ROLE + JDBC AUTH** (full DB-backed security)

---

### 📋 Mode-Specific Environment Variables

| Mode | Required `.env` settings |
|------|-------------------------|
| `jdbc-role` | `GEOSERVER_ENABLE_JDBC_ROLE=true` |
| `jdbc-auth-role` | `GEOSERVER_ENABLE_JDBC_ROLE=true` + `GEOSERVER_ENABLE_JDBC_AUTH=true` |
| `jdbc-config` | `GEOSERVER_ENABLE_JDBC_CONFIG=true` + `COMMUNITY_PLUGINS=sec-oidc,jdbcconfig` |

> ⚠️ **Important for `jdbc-config`:** This mode also requires `BUILD_JDBC_PLUGINS=true` in your Dockerfile build args, otherwise the required plugins won't be available at runtime.

> ⚠️ **Required for `jdbc-role` / `jdbc-auth-role`:**  
> Backend config alone is **not enough**. After `make up-all`, you **must** run JDBC activation and complete the UI steps.  
> **Without this step, JDBC ROLE / JDBC AUTH will not work.**
> ```bash
> make activate-jdbc
> ```
> This target runs:
> ```bash
> ENV_FILE=.env.<selected-env> ./scripts/activate_jdbcS_settings.sh
> ```
> Then follow the UI activation guide in [`readme_jdbc.md`](./readme_jdbc.md).

---

### 🔄 Switching Back to `default` Mode

```bash
# 1. Edit your .env file
GEOSERVER_SECURITY_MODE=default
GEOSERVER_ENABLE_JDBC_ROLE=false
GEOSERVER_ENABLE_JDBC_AUTH=false
GEOSERVER_ENABLE_JDBC_CONFIG=false

# 2. Rebuild and restart (no DB dependency)
make rebuild
```

> ℹ️ Your file-based config (`global.xml`, `users.xml`, etc.) will be used again. JDBC-backed data remains in PostgreSQL but is ignored until you re-enable the mode.

---

### 📚 Need More Detail?

For complete JDBC setup instructions, UI activation steps, schema design, and troubleshooting:

👉 **See [`readme_jdbc.md`](./readme_jdbc.md)**

That guide covers:
- ✅ Step-by-step UI activation (mandatory for JDBC modes)
- ✅ Dual-schema architecture (`gs_auth_role_schema` vs `gs_jdbcconfig_schema`)
- ✅ Database table reference and integration patterns
- ✅ Keycloak/OIDC integration prerequisites

---

> 🎯 **Quick Decision Helper:**  
> - Just testing or running a simple instance? → **Stay on `default`**  
> - Need to sync roles across multiple GeoServer instances? → **Try `jdbc-role`**  
> - Building a multi-tenant SaaS with centralized user management? → **Consider `jdbc-auth-role`**  
> - Need full config-as-code with database versioning? → **Read `readme_jdbc.md` first, then evaluate `jdbc-config`**

---

## ⚠️ PRODUCTION CHECKLIST – DO NOT SKIP

Before you deploy to production (`make set-env-prod`), verify **every item below**:

### 🔐 Security
- [ ] `GEOSERVER_ADMIN_PASSWORD` is **NOT** `geoserver` (use a strong, unique password)
- [ ] `GEOSERVER_CORS_ALLOWED_ORIGINS` does **NOT** contain `*` (list exact domains only)
- [ ] `GEOSERVER_CSRF_WHITELIST` includes your public domain
- [ ] `.env.prod` is **NOT** committed to Git (check `.gitignore`)
- [ ] `.env-selected` is in `.gitignore` (prevents accidental env commits)

### 🌐 Networking & Proxy
- [ ] `GEOSERVER_PUBLIC_URL` and `PROXY_BASE_URL` use `https://` and your real domain
- [ ] Your reverse proxy (Nginx, Traefik, etc.) forwards these headers:
  - `X-Forwarded-Proto`
  - `X-Forwarded-Host`
  - `X-Forwarded-Port`
- [ ] You have tested login and map requests **through the proxy**, not just localhost

### 🗄️ Data & Persistence
- [ ] You have a backup strategy for the `geoserver-data` Docker volume
- [ ] You know how to restore from backup (test this in staging first)
- [ ] PostgreSQL (if using JDBC) has its own backup schedule

### ✅ Validation
```bash
# Run this before every production deploy:
make validate

# After startup, verify inside the container:
make verify
```

> ❗ If any check fails, **do not proceed**. Fix the issue first.

---

## 🐛 Quick Troubleshooting

| Problem | Likely Cause | One-Line Fix |
|---------|-------------|--------------|
| Can't login, password rejected | First boot didn't apply new password | Check logs: `make logs-follow` |
| Browser shows "Mixed Content" warning | Login form uses `http` on `https` site | Ensure proxy sends `X-Forwarded-Proto: https` |
| CORS error in browser console | `GEOSERVER_CORS_ALLOWED_ORIGINS` doesn't match your frontend | Add exact origin: `https://app.yourcompany.com` |
| JDBC mode won't connect | PostgreSQL not ready or wrong credentials | Use `make up-all` to start DB + GeoServer together |
| Startup is very slow first time | Plugins downloading at runtime | Set `BUILD_JDBC_PLUGINS=true` in Dockerfile to bake them in |
| "Permission denied" on data directory | Volume mounted with wrong user | Ensure volume is writable by UID 1000 (Tomcat) |
| "Invalid ENV" error | `.env-selected` has wrong value | Run `make set-env-dev` or `make set-env-prod` |

### Quick Diagnostic Commands
```bash
make current-env          # Which environment am I in?
make health               # Is GeoServer responding?
make logs                 # What did it say on startup?
make verify               # Are runtime settings valid?
make shell-geoserver      # Debug inside the container
```
---

> ℹ️ **Stack:** GeoServer 2.28.3 • Tomcat 9 • JDK 17 • Docker  
> 🔄 **Last Updated:** May 2026  
> 🛠️ **Managed via Makefile** – run `make help` for quick reference  
> 📄 **License:** MIT – use, modify, and deploy freely  
> 🔐 **Remember:** Set your environment once with `make set-env-dev`, then just `make up` and work.