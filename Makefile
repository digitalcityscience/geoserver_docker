.PHONY: which-env build up down restart logs rebuild rmVolumes password

# -------------------------------------------------
# ENV selection (DEFAULT = dev) or prod
# -------------------------------------------------
ENV ?= dev

ENV_FILE := .env.$(ENV)
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
	@echo "🐳 COMPOSE_FILE=$(COMPOSE_FILE)"

# -------------------------------------------------
# Build
# -------------------------------------------------
build: which-env
	@echo "🐳 Building ($(ENV))"
	docker compose \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		build --no-cache

# -------------------------------------------------
# Up
# -------------------------------------------------
up: which-env
	@if [ "$(ENV)" = "prod" ]; then \
		echo "🔎 Running production safety checks..."; \
		bash scripts/check_prod_env.sh; \
	fi
	@echo "🚀 docker compose up ($(ENV))"
	docker compose \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		up -d

# -------------------------------------------------
# Down
# -------------------------------------------------
down: which-env
	@echo "🛑 docker compose down ($(ENV))"
	docker compose \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		down

# -------------------------------------------------
# Restart
# -------------------------------------------------
restart: down up

# -------------------------------------------------
# Logs
# -------------------------------------------------
logs: which-env
	@if [ -z "$(filter-out $@,$(MAKECMDGOALS))" ]; then \
		docker compose \
			--env-file $(ENV_FILE) \
			-f $(COMPOSE_FILE) \
			logs -f; \
	else \
		docker compose \
			--env-file $(ENV_FILE) \
			-f $(COMPOSE_FILE) \
			logs -f $(filter-out $@,$(MAKECMDGOALS)); \
	fi

# -------------------------------------------------
# Rebuild
# -------------------------------------------------
rebuild: which-env
	@echo "♻️ Rebuilding ($(ENV))"
	docker compose \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		build --no-cache
	docker compose \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		up -d

# -------------------------------------------------
# Volume cleanup (DANGEROUS)
# -------------------------------------------------
rmVolumes: which-env
	@echo "⚠️  Removing volumes ($(ENV))"
	docker compose \
		--env-file $(ENV_FILE) \
		-f $(COMPOSE_FILE) \
		down -v