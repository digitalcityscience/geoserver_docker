.PHONY: help which-env build up down restart logs rebuild rmVolumes password image release

# -------------------------------------------------
# ENV selection (DEFAULT = dev) or prod
# -------------------------------------------------
# ENV=dev  uses .env.development and docker-compose-dev.yml
# ENV=prod uses .env.production  and docker-compose-prod.yml
# Create the file from its committed template, e.g.
#   cp .env.development.example .env.development
ENV ?= dev

ifneq ($(filter $(ENV),dev prod),$(ENV))
  $(error ❌ Invalid ENV=$(ENV). Allowed values: dev, prod)
endif

ENV_NAME := $(if $(filter prod,$(ENV)),production,development)
ENV_FILE := .env.$(ENV_NAME)
COMPOSE_FILE := docker-compose-$(ENV).yml

# `make image`, `make release` and `make help` need no environment file.
NO_ENV_GOALS := image release help
ifeq ($(MAKECMDGOALS),)
  NEEDS_ENV := yes
else ifneq ($(filter-out $(NO_ENV_GOALS),$(MAKECMDGOALS)),)
  NEEDS_ENV := yes
endif

ifdef NEEDS_ENV
# -------------------------------------------------
# Load env file
# -------------------------------------------------
ifneq ("$(wildcard $(ENV_FILE))","")
  include $(ENV_FILE)
  export $(shell sed -n 's/^\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*=.*/\1/p' $(ENV_FILE))
else ifneq ("$(wildcard .env.$(ENV))","")
  $(error ❌ Missing $(ENV_FILE). Environment files are now named with the full mode: mv .env.$(ENV) $(ENV_FILE))
else
  $(error ❌ Missing $(ENV_FILE). Create it: cp $(ENV_FILE).example $(ENV_FILE))
endif

# -------------------------------------------------
# Check compose file
# -------------------------------------------------
ifneq ("$(wildcard $(COMPOSE_FILE))","")
else
  $(error ❌ Missing $(COMPOSE_FILE))
endif
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

# -------------------------------------------------
# Image and release (no environment file needed)
# -------------------------------------------------
IMAGE ?= tosca-geoserver:dev

help:
	@echo "make up|down|restart|logs|build|rebuild|rmVolumes ENV=dev|prod   local Compose stack"
	@echo "make image [IMAGE=name:tag]            build the image as CI does (default tosca-geoserver:dev)"
	@echo "make release VERSION=2.28.5-tosca.N    tag main and push the tag; CI publishes the image"

# The build arguments are the Dockerfile's defaults, which CI uses as well.
image:
	DOCKER_BUILDKIT=1 docker build -f docker/Dockerfile \
	  --build-arg VERSION=local-$$(git rev-parse --short HEAD) \
	  --build-arg REVISION=$$(git rev-parse HEAD)$$([ -z "$$(git status --porcelain)" ] || echo -dirty) \
	  -t $(IMAGE) .
	@echo "Built $(IMAGE). Check it with: scripts/ci/smoke-image.sh $(IMAGE)"

release:
	@scripts/release.sh "$(VERSION)"
