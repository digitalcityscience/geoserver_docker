# GeoServer Docker 

> 🎯 **In one sentence:**  
> Run GeoServer 2.28.3 in Docker. Works out of the box. Add PostgreSQL later if you need it.

---

## 🚀 Get Started in 3 Minutes

### For Development
```bash
# 1. Clone the repo
git clone <your-repo-url> && cd geoserver-docker

# 2. Create your dev environment file
make init-dev

# 3. Start GeoServer
make up
```

✅ **You're done!**  
🌐 Open: http://localhost:8080/geoserver  
🔐 Login: `admin` / `geoserver`

### For Production
```bash
# 1. Create your prod environment file
make init-prod

# 2. EDIT .env.prod – set strong passwords and your domain
vim .env.prod

# 3. Run safety checks (mandatory)
make validate ENV=prod

# 4. Start
make up ENV=prod
```

---

## 🎮 Makefile Cheat Sheet

> 💡 `ENV` defaults to `dev`. You can skip it for local work.

### Everyday Commands
```bash
make up                     # Start GeoServer (dev)
make up ENV=prod            # Start GeoServer (production)
make up-all                 # Start GeoServer + PostgreSQL (dev)
make down                   # Stop containers
make restart                # Restart everything
make logs-follow            # Watch logs in real-time (Ctrl+C to stop)
make health                 # Quick "is it alive?" check
```

### When You Change Code or Config
```bash
make rebuild                # Rebuild image + restart GeoServer
make rebuild ENV=prod       # Same, for production
```

### Debugging & Inspection
```bash
make ps                     # See what's running
make logs                   # Show last 100 log lines
make shell-geoserver        # Open terminal inside GeoServer container
make shell-db               # Open terminal inside PostgreSQL container
make verify                 # Run internal validation checks
```

### Cleanup ⚠️
```bash
make clean                  # Remove containers, networks, volumes (DATA LOSS)
make rmVolumes              # Remove volumes only (asks for confirmation)
```

### Help
```bash
make help                   # Show all commands
make which-env              # See which .env and compose files are loaded
```

---

## ⚙️ Only 5 Settings You Need to Change

Open `.env.dev` or `.env.prod` and edit these:

| Variable | Example | What it does |
|----------|---------|-------------|
| `GEOSERVER_ADMIN_PASSWORD` | `MySecurePass!2024` | Sets the admin password (change this!) |
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
| `jdbc-role` | JDBC ROLE in DB, users in files | ✅ Yes | You want role/permission mappings in PostgreSQL. |
| `jdbc-auth-role` | JDBC ROLE + JDBC AUTH in DB | ✅ Yes | You want both users and roles managed from PostgreSQL. |
| `jdbc-config` | Everything in DB | ✅ Yes | Advanced use only. You know what you're doing. |

> 🚦 **Golden Rule:** Always start with `default`. Get it working. Then switch modes if you truly need to.

---

### 🔁 How to Switch Modes 

```bash
# 1. Edit your .env file
GEOSERVER_SECURITY_MODE=jdbc-role
GEOSERVER_ENABLE_JDBC_ROLE=true

# 2. Rebuild and start with database
make up-all ENV=dev

# 3. Verify the mode is active
make verify-jdbc ENV=dev
```

> 💡 **Tip:** Use `make up-all` (not just `up`) when enabling any JDBC mode, because PostgreSQL must be running.

### 🧭 JDBC ROLE vs JDBC AUTH (Quick Mental Model)

- **JDBC ROLE** = role tables and mappings (`roles`, `user_roles`) managed in PostgreSQL.
- **JDBC AUTH** = user/group tables (`users`, `groups`, etc.) managed in PostgreSQL.
- `jdbc-role` enables only **JDBC ROLE**.
- `jdbc-auth-role` enables both **JDBC ROLE** and **JDBC AUTH**.

---

### 📋 Mode-Specific Environment Variables

| Mode | Required `.env` settings |
|------|-------------------------|
| `jdbc-role` | `GEOSERVER_ENABLE_JDBC_ROLE=true` + `GEOSERVER_JDBC_ROLE_AUTO_ACTIVATE=false` (recommended) |
| `jdbc-auth-role` | `GEOSERVER_ENABLE_JDBC_ROLE=true` + `GEOSERVER_ENABLE_JDBC_AUTH=true` |
| `jdbc-config` | `GEOSERVER_ENABLE_JDBC_CONFIG=true` + `COMMUNITY_PLUGINS=sec-oidc,jdbcconfig` |

> ⚠️ **Important for `jdbc-config`:** This mode also requires `BUILD_JDBC_PLUGINS=true` in your Dockerfile build args, otherwise the required plugins won't be available at runtime.

> ℹ️ **Important for `jdbc-role`:** Startup now prepares JDBC role files/tables by default and keeps file-based login active. Complete activation with `ENV_FILE=.env.prod ./scripts/activate_jdbcS_settings.sh` and GeoServer UI steps. Set `GEOSERVER_JDBC_ROLE_AUTO_ACTIVATE=true` only if you explicitly want automatic switch-over at startup.

> ℹ️ **Important for `jdbc-auth-role`:** Run `ENV_FILE=.env.prod ./scripts/activate_jdbcS_settings.sh` and follow UI steps in this order:
> 1. `Security → Role Services → jdbc_role → Test connection → Save`
> 2. `Security → User Group Services → jdbc_login → Test connection → Save`
>
> The script then validates JDBC ROLE + JDBC AUTH and proceeds with admin bootstrap.

---

### 🔄 Switching Back to `default` Mode

```bash
# 1. Edit your .env file
GEOSERVER_SECURITY_MODE=default
GEOSERVER_ENABLE_JDBC_ROLE=false
GEOSERVER_ENABLE_JDBC_AUTH=false
GEOSERVER_ENABLE_JDBC_CONFIG=false

# 2. Rebuild and restart (without DB dependency)
make rebuild ENV=dev
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
> - Need full config-as-code with database versioning? → **Read `readme_jdbc.md` first, then evaluate `jdbc-config`**```

---

## ⚠️ PRODUCTION CHECKLIST – DO NOT SKIP

Before you deploy to production (`ENV=prod`), verify **every item below**:

### 🔐 Security
- [ ] `GEOSERVER_ADMIN_PASSWORD` is **NOT** `geoserver` (use a strong, unique password)
- [ ] `GEOSERVER_CORS_ALLOWED_ORIGINS` does **NOT** contain `*` (list exact domains only)
- [ ] `GEOSERVER_CSRF_WHITELIST` includes your public domain
- [ ] `.env.prod` is **NOT** committed to Git (check `.gitignore`)

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
make validate ENV=prod

# After startup, verify inside the container:
make verify ENV=prod
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

### Quick Diagnostic Commands
```bash
make health                     # Is GeoServer responding?
make logs                       # What did it say on startup?
make verify                     # Are runtime settings valid?
make shell-geoserver            # Debug inside the container
```

---


---

> ℹ️ **Stack:** GeoServer 2.28.3 • Tomcat 9 • JDK 17 • Docker  
> 🔄 **Last Updated:** May 2026  
> 🛠️ **Managed via Makefile** – run `make help` for quick reference  
> 📄 **License:** MIT – use, modify, and deploy freely