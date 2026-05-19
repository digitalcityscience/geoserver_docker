.PHONY: help validate verify verify-jdbc verify-jdbc-role verify-jdbc-auth activate-jdbc build build-cache up up-all start stop down restart ps logs logs-follow health rebuild rmVolumes clean init-dev init-prod shell-geoserver shell-db set-env-dev set-env-prod current-env

# -------------------------------------------------
# 🎯 Smart ENV Handling (Persistent)
# -------------------------------------------------
# Default: dev
# Persisted: .env-selected file (should be gitignored)
# Override: make up ENV=prod (temporary for single command)
ENV_SELECTED_FILE := .env-selected
ENV ?= $(shell [ -f $(ENV_SELECTED_FILE) ] && cat $(ENV_SELECTED_FILE) 2>/dev/null || echo dev)

SERVICE ?= geoserver
COMPOSE ?= docker compose
DOCKER_CONFIG ?= $(CURDIR)/.docker-config
export DOCKER_CONFIG

# Use absolute paths to avoid directory confusion
ENV_FILE := $(CURDIR)/.env.$(ENV)
ENV_PATH := $(abspath $(ENV_FILE))
COMPOSE_FILE := $(CURDIR)/docker-compose-$(ENV).yml

# Safety: allow only dev / prod
ifeq ($(filter $(ENV),dev prod),)
  $(error ❌ Invalid ENV='$(ENV)'. Use 'make set-env-dev' or 'make set-env-prod')
endif

# -------------------------------------------------
# 🛡️ Smart Env Loading (Only for commands that need it)
# -------------------------------------------------
# These commands do NOT require an env file to be present:
SAFE_TARGETS := set-env-dev set-env-prod init-dev init-prod help current-env clean rmVolumes rmvolumes

# Check if the current target is "safe" (doesn't need env file)
IS_SAFE_TARGET := $(filter $(SAFE_TARGETS),$(MAKECMDGOALS))

# Only load/validate env file if target is NOT safe
ifeq ($(IS_SAFE_TARGET),)
  ifneq ("$(wildcard $(ENV_FILE))","")
    include $(ENV_FILE)
    export $(shell sed -n 's/^\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*=.*/\1/p' $(ENV_FILE))
  else
    $(error ❌ Missing $(ENV_FILE). Run 'make init-$(ENV)' first)
  endif

  # Check compose file exists (only for non-safe targets)
  ifeq ("$(wildcard $(COMPOSE_FILE))","")
    $(error ❌ Missing $(COMPOSE_FILE))
  endif
endif

# -------------------------------------------------
# 🔄 ENV Persistence Commands
# -------------------------------------------------
set-env-dev:
	@echo "dev" > $(ENV_SELECTED_FILE)
	@echo "✅ Environment set to: dev (persisted in $(ENV_SELECTED_FILE))"
	@echo "💡 Tip: Add '$(ENV_SELECTED_FILE)' to .gitignore to avoid committing environment choice"

set-env-prod:
	@echo "prod" > $(ENV_SELECTED_FILE)
	@echo "✅ Environment set to: prod (persisted in $(ENV_SELECTED_FILE)) ⚠️"
	@echo "💡 Tip: Run 'make validate' before deploying to production"

current-env:
	@echo "🔧 Current environment: $(ENV)"
	@echo "📄 Env file: $(ENV_FILE)"
	@echo "🐳 Compose file: $(COMPOSE_FILE)"
	@echo "💡 Tip: Use 'make set-env-prod' to switch permanently"

# -------------------------------------------------
# Help
# -------------------------------------------------
help:
	@echo "GeoServer Docker – Makefile Reference"
	@echo ""
	@echo "🎯 Environment (persistent)"
	@echo "  make set-env-dev          Set default to dev (no more ENV=dev typing)"
	@echo "  make set-env-prod         Set default to prod ⚠️"
	@echo "  make current-env          Show current environment"
	@echo ""
	@echo "🚀 Bootstrap"
	@echo "  make init-dev             Create .env.dev from template (if missing)"
	@echo "  make init-prod            Create .env.prod from template (if missing)"
	@echo ""
	@echo "🔄 Lifecycle (SERVICE defaults to geoserver)"
	@echo "  make up                   Start db + geoserver"
	@echo "  make up-all               Same as up (explicit)"
	@echo "  make start / stop / down  Container control"
	@echo "  make restart              Full restart (down + up)"
	@echo ""
	@echo "🔍 Inspection"
	@echo "  make ps                   Show container status"
	@echo "  make logs                 Show geoserver logs (last 100 lines)"
	@echo "  make logs-follow          Follow logs in real-time (Ctrl+C)"
	@echo "  make health               Quick HTTP health check"
	@echo "  make shell-geoserver      Open shell in GeoServer container"
	@echo "  make shell-db             Open shell in PostgreSQL container"
	@echo ""
	@echo "🔨 Build"
	@echo "  make build                Rebuild image (no cache)"
	@echo "  make build-cache          Rebuild image (with cache, faster for dev)"
	@echo "  make rebuild              Build + restart (db+geoserver if SERVICE=geoserver)"
	@echo ""
	@echo "✅ Validation"
	@echo "  make validate             Prod safety checks (if ENV=prod)"
	@echo "  make verify               Runtime validation (any mode)"
	@echo "  make verify-jdbc          Full JDBC validation"
	@echo "  make verify-jdbc-role     Validate JDBC role service only"
	@echo "  make verify-jdbc-auth     Validate JDBC auth service only"
	@echo "  make activate-jdbc        Run manual JDBC activation flow (required for jdbc-role/auth)"
	@echo ""
	@echo "🧹 Cleanup ⚠️"
	@echo "  make rmVolumes            Remove volumes (DATA LOSS)"
	@echo "  make clean                Full cleanup: down -v --remove-orphans"
	@echo ""
	@echo "💡 Quick Start:"
	@echo "  make set-env-dev          # Set dev as default (once)"
	@echo "  make init-dev && make up  # Bootstrap + start"
	@echo "  make logs-follow          # Watch logs"
	@echo "  make shell-geoserver      # Debug inside container"

# -------------------------------------------------
# Validation
# -------------------------------------------------
validate: current-env
	@if [ "$(ENV)" = "prod" ]; then \
		echo "🔎 Running production safety checks..."; \
		set -a; . "$(ENV_PATH)"; set +a; \
		bash scripts/check_prod_env.sh; \
	else \
		echo "ℹ️  ENV=$(ENV): skipping prod checks (use 'make set-env-prod' to enable)"; \
	fi

verify: current-env
	@echo "🔍 Running runtime validation inside GeoServer container..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) exec geoserver python3 /scripts/geoserver_validate_runtime.py

verify-jdbc: current-env
	@echo "🔍 Running JDBC validation inside GeoServer container..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) exec geoserver python3 /scripts/geoserver_validate_jdbc.py || \
	(echo "⚠️  JDBC validation skipped or failed – is JDBC mode enabled?"; exit 0)

verify-jdbc-role: current-env
	@echo "🔍 Running JDBC ROLE validation inside GeoServer container..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) \
		exec -e JDBC_VALIDATE_SCOPE=role -e JDBC_VALIDATE_REQUIRE_ACTIVE_ROLE=false \
		geoserver python3 /scripts/geoserver_validate_jdbc.py || \
	(echo "⚠️  JDBC role validation failed"; exit 0)

verify-jdbc-auth: current-env
	@echo "🔍 Running JDBC AUTH validation inside GeoServer container..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) \
		exec -e JDBC_VALIDATE_SCOPE=auth \
		geoserver python3 /scripts/geoserver_validate_jdbc.py || \
	(echo "⚠️  JDBC auth validation failed"; exit 0)

activate-jdbc: validate
	@echo "🧩 Running JDBC activation flow for $(ENV)..."
	@echo "ℹ️  This is required for jdbc-role and jdbc-auth-role modes."
	cd $(CURDIR) && ENV_FILE=.env.$(ENV) ./scripts/activate_jdbcS_settings.sh

health: current-env
	@echo "🏥 Checking GeoServer at http://localhost:$${GEOSERVER_HOST_PORT:-8080}/geoserver/web/"
	@curl -sf "http://localhost:$${GEOSERVER_HOST_PORT:-8080}/geoserver/web/" > /dev/null && \
		echo "✅ GeoServer is responding" || \
		(echo "❌ GeoServer not reachable – is it running?"; exit 1)

# -------------------------------------------------
# Build
# -------------------------------------------------
build: current-env
	@echo "🐳 Building images (no cache) [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) build --no-cache

build-cache: current-env
	@echo "🐳 Building images (with cache) [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) build

# -------------------------------------------------
# Up / Start
# -------------------------------------------------
up: validate
	@if [ "$(SERVICE)" = "geoserver" ]; then \
		echo "🚀 Starting db + geoserver [$(ENV)]..."; \
		$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d --build db geoserver; \
	else \
		echo "🚀 Starting $(SERVICE) [$(ENV)]..."; \
		$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d --build $(SERVICE); \
	fi

up-all: validate
	@echo "🚀 Starting db + geoserver [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d --build db geoserver

start: current-env
	@echo "▶️  Starting containers [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) start

stop: current-env
	@echo "⏸️  Stopping containers [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) stop

# -------------------------------------------------
# Down / Restart
# -------------------------------------------------
down: current-env
	@echo "🛑 Stopping + removing containers [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down

restart: down up

# -------------------------------------------------
# Inspection (SERVICE defaults to geoserver)
# -------------------------------------------------
ps: current-env
	@echo "📋 Container status [$(ENV)]:"
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) ps

logs: current-env
	@echo "📜 Showing last 100 log lines for $(SERVICE) [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) logs --tail=100 $(SERVICE)

logs-follow: current-env
	@echo "📜 Following $(SERVICE) [$(ENV)] (Ctrl+C to stop)..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) logs -f $(SERVICE)

# -------------------------------------------------
# Rebuild (special handling for geoserver service)
# -------------------------------------------------
rebuild: validate
	@echo "♻️  Rebuilding + restarting $(SERVICE) [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) build --no-cache
	@if [ "$(SERVICE)" = "geoserver" ]; then \
		echo "🚀 Starting db + geoserver [$(ENV)] after rebuild..."; \
		$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d db geoserver; \
	else \
		echo "🚀 Starting $(SERVICE) [$(ENV)] after rebuild..."; \
		$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) up -d $(SERVICE); \
	fi

# -------------------------------------------------
# Volume cleanup ⚠️ (DANGEROUS)
# -------------------------------------------------
rmVolumes: current-env
	@echo "⚠️  Removing volumes [$(ENV)] – ALL DATA WILL BE LOST"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted"; exit 1)
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down -v

rmvolumes: rmVolumes

clean: current-env
	@echo "🧹 Full cleanup [$(ENV)] – removing containers, networks, volumes..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) down -v --remove-orphans

# -------------------------------------------------
# Bootstrap env files (NEVER overwrite existing)
# -------------------------------------------------
init-dev:
	@if [ -f "$(CURDIR)/.env.dev" ]; then \
		echo "ℹ️  $(CURDIR)/.env.dev already exists – not overwriting"; \
		echo "💡 Edit it manually or remove it first to regenerate"; \
	else \
		cp $(CURDIR)/env_dev_sample $(CURDIR)/.env.dev && echo "✅ Created $(CURDIR)/.env.dev from template"; \
	fi

init-prod:
	@if [ -f "$(CURDIR)/.env.prod" ]; then \
		echo "ℹ️  $(CURDIR)/.env.prod already exists – not overwriting"; \
		echo "💡 Edit it manually or remove it first to regenerate"; \
	else \
		cp $(CURDIR)/env_prod_sample $(CURDIR)/.env.prod && echo "✅ Created $(CURDIR)/.env.prod from template"; \
	fi

# -------------------------------------------------
# Shell access
# -------------------------------------------------
shell-geoserver: current-env
	@echo "🐚 Opening shell in geoserver container [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) exec geoserver sh

shell-db: current-env
	@echo "🐚 Opening shell in db container [$(ENV)]..."
	$(COMPOSE) --env-file $(ENV_FILE) -f $(COMPOSE_FILE) exec db sh