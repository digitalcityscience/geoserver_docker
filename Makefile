.PHONY: which-env build up down restart logs rebuild rmVolumes password

# -------------------------------------------------
# ENV selection
# -------------------------------------------------
ENV ?= dev
ENV_FILE := .env.$(ENV)

ifneq ("$(wildcard $(ENV_FILE))","")
  include $(ENV_FILE)
  export $(shell sed -n 's/^\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*=.*/\1/p' $(ENV_FILE))
else
  $(error Missing $(ENV_FILE))
endif

# -------------------------------------------------
# Image
# -------------------------------------------------
IMAGE_NAME ?= dcs-geoserver
IMAGE_TAG  ?= $(GEOSERVER_VERSION)

# -------------------------------------------------
# Helpers
# -------------------------------------------------
which-env:
	@echo "🔧 ENV=$(ENV)"
	@echo "📄 ENV_FILE=$(ENV_FILE)"

# -------------------------------------------------
# Build
# -------------------------------------------------
build: which-env
	@echo "🐳 Building images (no cache)"
	docker compose build --no-cache

# -------------------------------------------------
# Up
# -------------------------------------------------
up: which-env
	@if [ "$(ENV)" = "prod" ]; then \
		echo "🔎 Running production safety checks..."; \
		bash scripts/check_prod_env.sh; \
	fi
	@echo "🚀 docker compose up ($(ENV))"
	docker compose --env-file $(ENV_FILE) up -d \
# -------------------------------------------------
# Admin password init (EXPLICIT, SAFE)
# -------------------------------------------------
password:
	@echo "⏳ Waiting for GeoServer..."
	sleep 20
	@echo "🔐 Applying GeoServer admin password via REST"
	docker compose exec -T geoserver /scripts/init_admin_password.sh

# -------------------------------------------------
# Down
# -------------------------------------------------
down:
	@echo "🛑 docker compose down"
	docker compose --env-file $(ENV_FILE) down

# -------------------------------------------------
# Restart
# -------------------------------------------------
restart: down up

# -------------------------------------------------
# Logs
#   make logs            -> all containers
#   make logs geoserver  -> specific container
# -------------------------------------------------
logs:
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then \
		docker compose logs -f; \
	else \
		docker compose logs -f $(filter-out $@,$(MAKECMDGOALS)); \
	fi

# -------------------------------------------------
# Rebuild (safe)
# -------------------------------------------------
rebuild: which-env
	@echo "♻️ Rebuilding images (no cache) and restarting stack"
	docker compose build --no-cache
	docker compose --env-file $(ENV_FILE) up -d

# -------------------------------------------------
# Volume cleanup (EXPLICIT, DANGEROUS)
# -------------------------------------------------
rmVolumes:
	@echo "⚠️  Removing Docker volumes (DATA LOSS)"
	docker compose --env-file $(ENV_FILE) down -v