.PHONY: help which-env validate verify verify-jdbc build build-cache up up-all start stop down restart ps logs logs-follow health rebuild rmVolumes clean init-dev init-prod shell-geoserver shell-db

# -------------------------------------------------
# ENV selection (DEFAULT = dev) or prod
# -------------------------------------------------
ENV ?= dev
SERVICE ?= geoserver
COMPOSE ?= docker-compose
DOCKER_CONFIG ?= $(CURDIR)/.docker-config

export DOCKER_CONFIG

ENV_FILE := .env.$(ENV)
ENV_PATH := $(abspath $(ENV_FILE))
COMPOSE_FILE := docker-compose-$(ENV).yml

# Safety: allow only dev / prod
ifeq ($(filter $(ENV),dev prod),)
  $(error ❌ Invalid ENV='$(ENV)'. Use ENV=dev or ENV=prod)
endif

# -------------------------------------------------
# Load env file (fail fast if missing)
# -------------------------------------------------
ifneq ("$(wildcard $(ENV_FILE))","")
  include $(ENV_FILE)
  export $(shell sed -n 's/^\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*=.*/\1/p' $(ENV_FILE))
else
  $(error ❌ Missing $(ENV_FILE). Run 'make init-$(ENV)' first)
endif

# -------------------------------------------------
# Check compose file
# -------------------------------------------------
ifneq ("$(wildcard $(COMPOSE_FILE))","")
else
  $(error ❌ Missing $(COMPOSE_FILE))
endif

# -------------------------------------------------
# Helpers
# -------------------------------------------------
which-env:
	@echo "🔧 ENV=$(ENV)"
	@echo "📄 ENV_FILE=$(ENV_FILE)"
	@echo "📍 ENV_PATH=$(ENV_PATH)"
	@echo "🐳 COMPOSE_FILE=$(COMPOSE_FILE)"
	@echo "🧰 COMPOSE_CMD=$(COMPOSE)"
	@echo "🗂️  DOCKER_CONFIG=$(DOCKER_CONFIG)"
	@echo "🧩 SERVICE=$(SERVICE)"

help:
	@echo "GeoServer Docker – Makefile Reference"
	@echo ""
	@echo "Usage: make <target> [ENV=dev|prod] [SERVICE=...]"
	@echo ""
	@echo "🚀 Bootstrap"
	@echo "  make init-dev                     Create .env.dev from template"
	@echo "  make init-prod                    Create .env.prod from template"
	@echo ""
	@echo "🔄 Lifecycle"
	@echo "  make up [ENV=dev]                 Build + start SERVICE (default: geoserver)"
	@echo "  make up-all [ENV=dev]             Build + start db + geoserver"
	@echo "  make start [ENV=dev]              Start existing containers"
	@echo "  make stop [ENV=dev]               Stop running containers"
	@echo "  make down [ENV=dev]               Stop + remove containers/networks"
	@echo "  make restart [ENV=dev]            Full restart (down + up)"
	@echo ""
	@echo "🔍 Inspection"
	@echo "  make ps [ENV=dev]                 Show container status"
	@echo "  make logs [ENV=dev] [SERVICE=x]   Show logs (tail -n 100)"
	@echo "  make logs-follow [ENV=dev]        Follow logs in real-time (-f)"
	@echo "  make health [ENV=dev]             Quick health check via HTTP"
	@echo "  make shell-geoserver [ENV=dev]    Open shell in GeoServer container"
	@echo "  make shell-db [ENV=dev]           Open shell in PostgreSQL container"
	@echo ""
	@echo "🔨 Build"
	@echo "  make build [ENV=dev]              Build images (no cache)"
	@echo "  make build-cache [ENV=dev]        Build images (with cache, faster for dev)"
	@echo "  make rebuild [ENV=dev]            Rebuild + start SERVICE"
	@echo ""
	@echo "✅ Validation"
	@echo "  make validate [ENV=prod]          Production env safety checks"
	@echo "  make verify [ENV=dev]             Run runtime validation inside container"
	@echo "  make verify-jdbc [ENV=dev]        Validate JDBC mode configuration"
	@echo ""
	@echo "🧹 Cleanup"
	@echo "  make rmVolumes [ENV=dev]          Remove volumes ⚠️ DATA LOSS"
	@echo "  make clean [ENV=dev]              Full cleanup: down -v --remove-orphans"

# -------------------------------------------------
# Validation
# -------------------------------------------------
validate: which-env
	@if [ "$(ENV)" = "prod" ]; then \
		echo "🔎 Running production safety checks..."; \
		set -a; . "$(ENV_PATH)"; set +a; \
		bash scripts/check_prod_env.sh; \
	else \
		echo "ℹ️  ENV=$(ENV): skipping production checks (use ENV=prod to enable)"; \
	fi

# Runtime validation inside container (works for any mode)
verify: which-env
	@echo "🔍 Running runtime validation inside GeoServer container..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		exec geoserver python3 /scripts/geoserver_validate_runtime.py

# JDBC-specific validation (only relevant when JDBC mode is enabled)
verify-jdbc: which-env
	@echo "🔍 Running JDBC validation inside GeoServer container..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		exec geoserver python3 /scripts/geoserver_validate_jdbc.py || \
		(echo "⚠️  JDBC validation skipped or failed – is JDBC mode enabled?"; exit 0)

# Quick HTTP health check (requires curl on host)
health: which-env
	@echo "🏥 Checking GeoServer health at http://localhost:$${GEOSERVER_HOST_PORT:-8080}/geoserver/web/"
	@curl -sf "http://localhost:$${GEOSERVER_HOST_PORT:-8080}/geoserver/web/" > /dev/null && \
		echo "✅ GeoServer is responding" || \
		(echo "❌ GeoServer not reachable – is it running?"; exit 1)

# -------------------------------------------------
# Build
# -------------------------------------------------
build: which-env
	@echo "🐳 Building images (no cache) [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		build --no-cache

build-cache: which-env
	@echo "🐳 Building images (with cache) [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		build

# -------------------------------------------------
# Up
# -------------------------------------------------
up: validate
	@if [ "$(SERVICE)" = "geoserver" ]; then \
		echo "🚀 Starting db + geoserver [$(ENV)]..."; \
		$(COMPOSE) -f $(COMPOSE_FILE) up -d --build db geoserver; \
	else \
		echo "🚀 Starting $(SERVICE) [$(ENV)]..."; \
		$(COMPOSE) -f $(COMPOSE_FILE) up -d --build $(SERVICE); \
	fi

up-all: validate
	@echo "🚀 Starting db + geoserver [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		up -d --build db geoserver

start: which-env
	@echo "▶️  Starting containers [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		start

stop: which-env
	@echo "⏸️  Stopping containers [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		stop

# -------------------------------------------------
# Down / Restart
# -------------------------------------------------
down: which-env
	@echo "🛑 Stopping + removing containers [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		down

restart: down up

# -------------------------------------------------
# Inspection
# -------------------------------------------------
ps: which-env
	@echo "📋 Container status [$(ENV)]:"
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		ps

logs: which-env
	@echo "📜 Showing last 100 log lines for $(SERVICE) [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		logs --tail=100 $(SERVICE)

logs-follow: which-env
	@echo "📜 Following logs for $(SERVICE) [$(ENV)] (Ctrl+C to stop)..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		logs -f $(SERVICE)

# -------------------------------------------------
# Rebuild
# -------------------------------------------------
rebuild: validate
	@echo "♻️  Rebuilding + restarting $(SERVICE) [$(ENV)]..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		build --no-cache
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		up -d $(SERVICE)

# -------------------------------------------------
# Volume cleanup (DANGEROUS)
# -------------------------------------------------
rmVolumes: which-env
	@echo "⚠️  Removing volumes [$(ENV)] – ALL DATA WILL BE LOST"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted"; exit 1)
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		down -v

rmvolumes: rmVolumes

clean: which-env
	@echo "🧹 Full cleanup [$(ENV)] – removing containers, networks, volumes..."
	$(COMPOSE) \
		-f $(COMPOSE_FILE) \
		down -v --remove-orphans

# -------------------------------------------------
# Bootstrap env files
# -------------------------------------------------
init-dev:
	@if [ -f .env.dev ]; then \
		echo "ℹ️  .env.dev already exists"; \
	else \
		cp env_dev_sample .env.dev && echo "✅ Created .env.dev"; \
	fi

init-prod:
	@if [ -f .env.prod ]; then \
		echo "ℹ️  .env.prod already exists"; \
	else \
		cp env_prod_sample .env.prod && echo "✅ Created .env.prod"; \
	fi

# -------------------------------------------------
# Shell access
# -------------------------------------------------
shell-geoserver: which-env
	@echo "🐚 Opening shell in geoserver container [$(ENV)]..."
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		exec geoserver sh

shell-db: which-env
	@echo "🐚 Opening shell in db container [$(ENV)]..."
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		exec db sh