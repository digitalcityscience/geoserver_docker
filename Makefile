.PHONY: help which-env validate build up up-all start stop down restart ps logs rebuild rmVolumes rmvolumes clean init-dev init-prod shell-geoserver shell-db

# -------------------------------------------------
# ENV selection (DEFAULT = dev) or prod
# -------------------------------------------------
ENV ?= dev
SERVICE ?= geoserver
COMPOSE ?= docker-compose

ENV_FILE := .env.$(ENV)
ENV_PATH := $(abspath $(ENV_FILE))
COMPOSE_FILE := docker-compose-$(ENV).yml

# Safety: allow only dev / prod
ifeq ($(ENV),dev)
  COMPOSE_FILE := docker-compose-dev.yml
endif

ifeq ($(ENV),prod)
  COMPOSE_FILE := docker-compose-prod.yml
endif

# -------------------------------------------------
# Load env file
# -------------------------------------------------
ifneq ("$(wildcard $(ENV_FILE))","")
  include $(ENV_FILE)
  export $(shell sed -n 's/^\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*=.*/\1/p' $(ENV_FILE))
else
  $(error ❌ Missing $(ENV_FILE))
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
	@echo "🧩 SERVICE=$(SERVICE)"

help:
	@echo "Usage: make <target> [ENV=dev|prod] [SERVICE=...]"
	@echo ""
	@echo "Bootstrap"
	@echo "  make init-dev                     Copy env_dev_sample to .env.dev if missing"
	@echo "  make init-prod                    Copy env_prod_sample to .env.prod if missing"
	@echo ""
	@echo "Lifecycle"
	@echo "  make up ENV=dev                   Build and start SERVICE (default: geoserver)"
	@echo "  make up-all ENV=dev               Build and start db + geoserver"
	@echo "  make start ENV=dev                Start existing containers"
	@echo "  make stop ENV=dev                 Stop running containers"
	@echo "  make down ENV=dev                 Stop and remove containers/networks"
	@echo "  make restart ENV=dev              Restart stack (down + up)"
	@echo ""
	@echo "Inspection"
	@echo "  make ps ENV=dev                   Show container status"
	@echo "  make logs ENV=dev                 Follow all logs"
	@echo "  make logs ENV=dev SERVICE=db      Follow one service logs"
	@echo "  make shell-geoserver ENV=dev      Open shell in geoserver container"
	@echo "  make shell-db ENV=dev             Open shell in db container"
	@echo ""
	@echo "Build/Cleanup"
	@echo "  make build ENV=dev                Build images (no cache)"
	@echo "  make rebuild ENV=dev              Rebuild and start SERVICE"
	@echo "  make rmVolumes ENV=dev            Remove volumes (DATA LOSS)"
	@echo "  make clean ENV=dev                down -v --remove-orphans"
	@echo ""
	@echo "Validation"
	@echo "  make validate ENV=prod            Run production env safety checks"

validate: which-env
	@if [ "$(ENV)" = "prod" ]; then \
		echo "🔎 Running production safety checks..."; \
		if [ ! -f "$(ENV_PATH)" ]; then \
			echo "❌ Missing env file: $(ENV_PATH)"; \
			exit 1; \
		fi; \
		set -a; . "$(ENV_PATH)"; set +a; \
		bash scripts/check_prod_env.sh; \
	else \
		echo "ℹ️  ENV=$(ENV): production safety checks are skipped"; \
	fi

# -------------------------------------------------
# Build
# -------------------------------------------------
build: which-env
	@echo "🐳 Building ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		build --no-cache

# -------------------------------------------------
# Up
# -------------------------------------------------
up: validate
	@echo "🚀 docker compose up ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		up -d --build $(SERVICE)

up-all: validate
	@echo "🚀 docker compose up all core services ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		up -d --build db geoserver

start: which-env
	@echo "▶️  docker compose start ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		start

stop: which-env
	@echo "⏸️  docker compose stop ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		stop

# -------------------------------------------------
# Down
# -------------------------------------------------
down: which-env
	@echo "🛑 docker compose down ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		down

# -------------------------------------------------
# Restart
# -------------------------------------------------
restart: down up

ps: which-env
	@echo "📋 docker compose ps ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		ps

# -------------------------------------------------
# Logs
# -------------------------------------------------
logs: which-env
	@echo "📜 docker compose logs ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		logs -f $(SERVICE)

# -------------------------------------------------
# Rebuild
# -------------------------------------------------
rebuild: which-env
	@echo "♻️ Rebuilding ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		build --no-cache
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		up -d $(SERVICE)

# -------------------------------------------------
# Volume cleanup (DANGEROUS)
# -------------------------------------------------
rmVolumes: which-env
	@echo "⚠️  Removing volumes ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		down -v

rmvolumes: rmVolumes

clean: which-env
	@echo "🧹 Full cleanup ($(ENV))"
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		down -v --remove-orphans

init-dev:
	@if [ -f .env.dev ]; then \
		echo "ℹ️  .env.dev already exists"; \
	else \
		cp env_dev_sample .env.dev; \
		echo "✅ Created .env.dev from env_dev_sample"; \
	fi

init-prod:
	@if [ -f .env.prod ]; then \
		echo "ℹ️  .env.prod already exists"; \
	else \
		cp env_prod_sample .env.prod; \
		echo "✅ Created .env.prod from env_prod_sample"; \
	fi

shell-geoserver: which-env
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		exec geoserver sh

shell-db: which-env
	$(COMPOSE) \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		exec db sh
