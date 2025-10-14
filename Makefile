.PHONY: setup plugins build up down clean rebuild which-env print-env

# ---- Profile selection ----
ENV ?= dev
ENV_FILE := .env.$(ENV)

# Load env file (fail fast)
ifneq ("$(wildcard $(ENV_FILE))","")
  include $(ENV_FILE)
  export $(shell sed -n 's/^\s*\([A-Za-z_][A-Za-z0-9_]*\)\s*=.*/\1/p' $(ENV_FILE))
else
  $(error Missing $(ENV_FILE). Create it from .env.sample)
endif

# ---- Plugins ----
# Official (SourceForge) plugins (space separated, short names)
PLUGINS ?= mbstyle vectortiles wfsoutput

# Community plugins (full URLs, space separated, NOT commas!)
# Example:
# COM_PLUGINS = https://example.com/plugin1.zip https://example.com/plugin2.zip
COM_PLUGINS ?= \
  https://build.geoserver.org/geoserver/2.27.x/community-latest/geoserver-2.27-SNAPSHOT-sec-oauth2-openid-connect-plugin.zip

IMAGE_NAME ?= dcs-geoserver
IMAGE_TAG ?= $(GEOSERVER_VERSION)

which-env:
	@echo "Using $(ENV_FILE)"

print-env:
	@echo "GEOSERVER_VERSION=$(GEOSERVER_VERSION)"
	@echo "PROXY_BASE_URL=$(PROXY_BASE_URL)"
	@echo "POSTGRES_DB=$(POSTGRES_DB)"
	@echo "POSTGRES_USER=$(POSTGRES_USER)"

setup:
	@echo "🔧 Checking required directories..."
	@[ -d ./geoserver_data ] || (echo "📁 Creating ./geoserver_data" && mkdir -p ./geoserver_data)
	@[ -d ./plugins ] || (echo "📁 Creating ./plugins" && mkdir -p ./plugins)

plugins: setup
	@echo "⬇️  Downloading official plugins for GeoServer $(GEOSERVER_VERSION) → $(PLUGINS)"
	@test -x ./download_plugins.sh || chmod +x ./download_plugins.sh
	./download_plugins.sh "$(GEOSERVER_VERSION)" "$(PLUGINS)"
	@if [ -n "$(COM_PLUGINS)" ]; then \
		echo "⬇️  Downloading community plugins (full URLs): $(COM_PLUGINS)"; \
		for url in $(COM_PLUGINS); do \
			echo "Fetching $$url"; \
			fname=$$(basename "$$url"); \
			curl -fsSL "$$url" -o "$$fname"; \
			unzip -o "$$fname" -d ./plugins; \
			rm -f "$$fname"; \
		done; \
		echo "✅ Community plugins ready in ./plugins"; \
	else \
		echo "ℹ️  No community plugins requested (COM_PLUGINS is empty)"; \
	fi

build: setup plugins
	@echo "🐳 Building image: $(IMAGE_NAME):$(IMAGE_TAG)"
	docker build \
        --no-cache \
        --build-arg GEOSERVER_VERSION=$(GEOSERVER_VERSION) \
        -t $(IMAGE_NAME):$(IMAGE_TAG) \
        .

up: which-env
	@echo "🚀 docker compose up with $(ENV_FILE)"
	@echo "Using $(ENV_FILE)"
	docker compose --env-file $(ENV_FILE) up -d --build

down:
	@echo "🧹 docker compose down"
	docker compose --env-file $(ENV_FILE) down

clean: down
	@echo "🧹 removing image $(IMAGE_NAME):$(IMAGE_TAG)"
	docker image rm $(IMAGE_NAME):$(IMAGE_TAG) || true

rebuild: clean build up