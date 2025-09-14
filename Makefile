# ============================================================================
# Graphtastic Makefile Best Practices
# - Never use @echo inside a shell block (use shell echo only)
# - All recipes must be tab-indented, not space-indented
# - All targets must be defined only once
# - All .PHONY targets should be grouped together
# - Always quote variables in shell blocks to avoid empty alternations
# - Use 'make lint-makefile' to check for common issues
# ============================================================================

# Always include .env if present
# This allows overriding any defaults set in the Makefile with values from .env
# If .env is not present, the explicit 'export ?=' defaults below will be used.
-include .env

# ============================================================================
# === CORE CONFIGURATION VARIABLES (centralized with defaults) ===
# ============================================================================

# NOTE: the strip function is used to remove any accidental leading/trailing whitespace
# from environment variable values, have caused hard-to-diagnose issues.

# Ensure COMPOSE_FILE is always set and exported for docker compose
export COMPOSE_FILE ?= docker-compose.yml

# --- Core Networking & Compose ---

# Name of the shared Docker network
export EXTERNAL_NETWORK_NAME ?= guac-network

# --- Dgraph Stack Configuration ---
# Comma-separated list of IP CIDRs for Dgraph Alpha access (default: allow all for local dev)
export DGRAPH_ALPHA_WHITELIST ?= 0.0.0.0/0

# 'bind' for host-mounted directories, 'volume' for Docker volumes
export DGRAPH_DATA_MODE ?= bind
export DGRAPH_DATA_VOLUME_ZERO ?= dgraph_zero_data
export DGRAPH_DATA_VOLUME_ALPHA ?= dgraph_alpha_data

# --- GUAC Stack Configuration ---

# Host path for GUAC Postgres data
export GUAC_DATA_PATH ?= ./dgraph-stack/guac-data
export POSTGRES_DB ?= guac
export POSTGRES_USER ?= guac
export POSTGRES_PASSWORD ?= guac

# --- Mesh/Extractor endpoints ---
export MESH_ENDPOINT ?= http://guac-mesh-graphql:4000/graphql
export GUAC_ENDPOINT ?= http://guac-graphql:8080/query

# --- Tooling Configuration ---

# Set to 1 to run tools like extractor locally instead of in containers
export USE_LOCAL_TOOLS ?= 0

# ============================================================================
# === PORT VARIABLES (centralized with defaults) ===
# All port variables are exported as they might be used by docker-compose.yml
# ============================================================================

# Dgraph Zero
export DGRAPH_ZERO_GRPC_PORT ?= 5080
export DGRAPH_ZERO_HTTP_PORT ?= 6080
export DGRAPH_ZERO_GRPC_PORT_HOST ?= 5081
export DGRAPH_ZERO_HTTP_PORT_HOST ?= 6081

# Dgraph Alpha
export DGRAPH_ALPHA_GRPC_PORT ?= 9080
export DGRAPH_ALPHA_HTTP_PORT ?= 8080
export DGRAPH_ALPHA_GRPC_PORT_HOST ?= 9081
export DGRAPH_ALPHA_HTTP_PORT_HOST ?= 8081

# Dgraph Ratel
export DGRAPH_RATEL_PORT ?= 8000
export DGRAPH_RATEL_PORT_HOST ?= 8001

# GUAC GraphQL
export GUAC_GRAPHQL_PORT ?= 8080
export GUAC_GRAPHQL_PORT_HOST ?= 8080

# Mesh GraphQL
export MESH_GRAPHQL_PORT ?= 4000
export MESH_GRAPHQL_PORT_HOST ?= 4000

# Postgres
export POSTGRES_PORT ?= 5432
export POSTGRES_PORT_HOST ?= 5432

# ============================================================================
# === Project-Specific Paths ===
# ============================================================================

DGRAPH_STACK_DIR := dgraph-stack
BUILD_DIR := build
SBOMS_DIR := sboms
BENCHMARK_DIR := guac-mesh-graphql/benchmark
SCHEMA_DIR := schema
OUT_DIR := out

# Dgraph bulk loader specific configuration
DGRAPH_BULK_LOADER_SERVICE := dgraph-bulk-loader
DGRAPH_BULK_ARGS := --map_shards=1 --reduce_shards=1 --zero=dgraph-zero:5080
# ============================================================================
# === PHONY Targets (Grouped) ===
# ============================================================================

.PHONY: help setup up down clean status logs
.PHONY: ingest-sboms extract demo-1m
.PHONY: fetch-benchmark-data validate check-dockerfiles lint-makefile
.PHONY: print-vars print-docker-networks print-docker-volumes
.PHONY: var-% clean-dgraph-zero
.PHONY: generate-compose-config-only

# ============================================================================
# === Utility Targets ===
# ============================================================================

# Target to print the value of any Makefile variable: make var-VARIABLE_NAME
var-%:
	@echo "$($*)"

generate-compose-config-only:
	@echo "--- Generating merged Docker Compose config to docs/docker-compose.merged.yml ---"
	@mkdir -p docs
	docker compose -f "$(COMPOSE_FILE)" config > docs/docker-compose.merged.yml
	@echo "Merged config written to docs/docker-compose.merged.yml"

# Print all environment and port variables grouped by context
print-vars:
	@echo ""
	@echo "[Core Networking & Compose]"
	@echo "  EXTERNAL_NETWORK_NAME = $(EXTERNAL_NETWORK_NAME)"
	@echo "  COMPOSE_FILE         = $(COMPOSE_FILE)"
	@echo ""
	@echo "[Dgraph Stack]"
	@echo "  DGRAPH_ALPHA_WHITELIST = $(DGRAPH_ALPHA_WHITELIST)"
	@echo "  DGRAPH_DATA_MODE       = $(DGRAPH_DATA_MODE)"
	@echo "  DGRAPH_DATA_VOLUME_ZERO = $(DGRAPH_DATA_VOLUME_ZERO)"
	@echo "  DGRAPH_DATA_VOLUME_ALPHA = $(DGRAPH_DATA_VOLUME_ALPHA)"
	@echo ""
	@echo "[Dgraph Ports]"
	@echo "  DGRAPH_ZERO_GRPC_PORT_HOST = $(DGRAPH_ZERO_GRPC_PORT_HOST)"
	@echo "  DGRAPH_ZERO_GRPC_PORT      = $(DGRAPH_ZERO_GRPC_PORT)"
	@echo "  DGRAPH_ZERO_HTTP_PORT_HOST = $(DGRAPH_ZERO_HTTP_PORT_HOST)"
	@echo "  DGRAPH_ZERO_HTTP_PORT      = $(DGRAPH_ZERO_HTTP_PORT)"
	@echo "  DGRAPH_ALPHA_GRPC_PORT_HOST = $(DGRAPH_ALPHA_GRPC_PORT_HOST)"
	@echo "  DGRAPH_ALPHA_GRPC_PORT      = $(DGRAPH_ALPHA_GRPC_PORT)"
	@echo "  DGRAPH_ALPHA_HTTP_PORT_HOST = $(DGRAPH_ALPHA_HTTP_PORT_HOST)"
	@echo "  DGRAPH_ALPHA_HTTP_PORT      = $(DGRAPH_ALPHA_HTTP_PORT)"
	@echo "  DGRAPH_RATEL_PORT_HOST      = $(DGRAPH_RATEL_PORT_HOST)"
	@echo "  DGRAPH_RATEL_PORT           = $(DGRAPH_RATEL_PORT)"
	@echo ""
	@echo "[GUAC Stack]"
	@echo "  POSTGRES_DB        = $(POSTGRES_DB)"
	@echo "  POSTGRES_USER      = $(POSTGRES_USER)"
	@echo "  POSTGRES_PASSWORD  = $(POSTGRES_PASSWORD)"
	@echo "  GUAC_DATA_PATH     = $(GUAC_DATA_PATH)"
	@echo "  POSTGRES_PORT_HOST = $(POSTGRES_PORT_HOST)"
	@echo "  POSTGRES_PORT      = $(POSTGRES_PORT)"
	@echo "  GUAC_GRAPHQL_PORT_HOST = $(GUAC_GRAPHQL_PORT_HOST)"
	@echo "  GUAC_GRAPHQL_PORT      = $(GUAC_GRAPHQL_PORT)"
	@echo ""
	@echo "[Mesh/Extractor]"
	@echo "  MESH_ENDPOINT      = $(MESH_ENDPOINT)"
	@echo "  GUAC_ENDPOINT      = $(GUAC_ENDPOINT)"
	@echo "  MESH_GRAPHQL_PORT_HOST = $(MESH_GRAPHQL_PORT_HOST)"
	@echo "  MESH_GRAPHQL_PORT      = $(MESH_GRAPHQL_PORT)"
	@echo ""
	@echo "[Tooling]"
	@echo "  USE_LOCAL_TOOLS    = $(USE_LOCAL_TOOLS)"
	@echo ""

# Print docker networks with robust pattern
print-docker-networks:
	if [ -n "$(EXTERNAL_NETWORK_NAME)" ]; then \
		pattern="NETWORK|$(EXTERNAL_NETWORK_NAME)|dgraph_internal_net|guac_internal_net"; \
	else \
		pattern="NETWORK|dgraph_internal_net|guac_internal_net"; \
	fi; \
	docker network ls | grep -E "$${pattern}" || true

# Print docker volumes with robust pattern
print-docker-volumes:
	if [ -n "$(DGRAPH_DATA_VOLUME_ZERO)$(DGRAPH_DATA_VOLUME_ALPHA)" ]; then \
		pattern="VOLUME"; \
		[ -n "$(DGRAPH_DATA_VOLUME_ZERO)" ] && pattern="$${pattern}|$(DGRAPH_DATA_VOLUME_ZERO)"; \
		[ -n "$(DGRAPH_DATA_VOLUME_ALPHA)" ] && pattern="$${pattern}|$(DGRAPH_DATA_VOLUME_ALPHA)"; \
	else \
		pattern="VOLUME"; \
	fi; \
	docker volume ls | grep -E "$${pattern}" || true

# Lint Makefile for common issues
lint-makefile:
	@echo "Linting Makefile for common issues..."
	@grep -n '^ ' Makefile && echo 'ERROR: Space-indented recipe found!' && exit 1 || true
	@grep -n '@echo' Makefile | grep '\\$$' && echo 'ERROR: @echo found in shell block!' && exit 1 || true
	@echo "No common Makefile issues found."

# Force remove any existing 'dgraph-zero' container (unmanaged or orphaned)
clean-dgraph-zero:
	@echo "--- Force removing any existing 'dgraph-zero' container ---"
	@docker rm -f dgraph-zero >/dev/null 2>&1 || true
	@echo "--- 'dgraph-zero' cleanup attempt complete. ---"

# ============================================================================
# === Main Targets ===
# ============================================================================

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "=== Main Targets ==="
	@echo "  setup                - Prepare the local environment (e.g., check .env, create networks)."
	@echo "  up                   - Bring up all services (full stack) as defined by $(COMPOSE_FILE)."
	@echo "  down                 - Bring down all services."
	@echo "  clean                - Run 'down', then remove all persistent data and build artifacts."
	@echo "  status               - Show container, network, volume, and config variable status."
	@echo "  logs                 - Tail logs for all running services."
	@echo ""
	@echo "=== Data & Demo Pipeline ==="
	@echo "  demo-1m              - Cleanly loads the 1M RDF benchmark dataset into Dgraph via bulk loader."
	@echo "  ingest-sboms         - Ingest SBOMs from the ./$(SBOMS_DIR) directory into GUAC."
	@echo "  extract              - Run the ETL script to extract from Mesh and generate RDF."
	@echo ""
	@echo "=== Utilities ==="
	@echo "  validate             - Run a series of health checks on the running environment."
	@echo "  fetch-benchmark-data - Download 1million RDF and schemas for benchmarking."
	@echo "  check-dockerfiles    - Check for missing Dockerfiles referenced in compose files."
	@echo "  clean-dgraph-zero    - Force remove only the 'dgraph-zero' container if it's blocking."
	@echo ""
	@echo "=== Environment Variables (current values) ==="
	@$(MAKE) print-vars
	@echo "  See .env.example for all options and documentation."

# Prepare the local environment: create networks, volumes, and directories.
# This target now purely focuses on setting up prerequisites and cleaning up known conflicts.
preflight:
	@echo "--- Initializing shared resources ---"
	# Check for and handle orphaned 'dgraph-zero' container if it exists.
	# This logic tries to gracefully stop it if part of another Compose project,
	# or prompts for force removal if unmanaged/stuck.
	@if docker ps -a --format '{{.Names}}' | grep -q '^dgraph-zero$$'; then \
		echo "WARN: Found a conflicting container named 'dgraph-zero'. This might prevent 'make up' from running."; \
		CONTAINER_INFO=$$(docker inspect dgraph-zero 2>/dev/null); \
		COMPOSE_PROJECT_NAME=$$(echo "$$CONTAINER_INFO" | jq -r '.[0].Config.Labels."com.docker.compose.project" // ""' 2>/dev/null); \
		\
		if [ -n "$$COMPOSE_PROJECT_NAME" ] && [ "$$COMPOSE_PROJECT_NAME" != "$(shell basename $(CURDIR))" ] && [ "$$COMPOSE_PROJECT_NAME" != "$(patsubst %/docker-compose.yml,%,$(COMPOSE_FILE))" ]; then \
			echo "INFO: This 'dgraph-zero' container appears to be part of Docker Compose project: '$$COMPOSE_PROJECT_NAME'."; \
			echo "INFO: Attempting to gracefully stop it using 'docker compose down' for that project..."; \
			if docker compose -p "$$COMPOSE_PROJECT_NAME" down dgraph-zero; then \
				echo "✅ Successfully stopped conflicting 'dgraph-zero' from project '$$COMPOSE_PROJECT_NAME'."; \
			else \
				echo "❌ Failed to gracefully stop 'dgraph-zero' from project '$$COMPOSE_PROJECT_NAME'."; \
				echo "   It might be stuck or unmanaged. Further action is needed."; \
				IS_INTERACTIVE=$$( [ -t 0 ] && echo "true" || echo "false" ); \
				if [ "$$IS_INTERACTIVE" = "true" ]; then \
					read -p "Do you want to force remove it with 'docker rm -f dgraph-zero'? (y/N) " -n 1 -r REPLY; \
					echo; \
					if [[ "$$REPLY" =~ ^[Yy]$$ ]]; then \
						echo "Proceeding with force removal..."; \
						docker rm -f dgraph-zero; \
						echo "✅ Conflicting 'dgraph-zero' container force removed."; \
					else \
						echo "Aborting. Please manually resolve the 'dgraph-zero' conflict before proceeding, or run 'make clean-dgraph-zero'."; \
						exit 1; \
					fi; \
				else \
					echo "Aborting (non-interactive mode). Please manually remove the conflicting 'dgraph-zero' container (e.g., 'docker rm -f dgraph-zero') and retry, or run 'make clean-dgraph-zero'."; \
					exit 1; \
				fi; \
			fi; \
		else \
			echo "INFO: The conflicting 'dgraph-zero' container is either unmanaged by Compose, or part of *this* Compose project but in a bad state."; \
			IS_INTERACTIVE=$$( [ -t 0 ] && echo "true" || echo "false" ); \
			if [ "$$IS_INTERACTIVE" = "true" ]; then \
				read -p "Do you want to force remove it with 'docker rm -f dgraph-zero'? (y/N) " -n 1 -r REPLY; \
				echo; \
				if [[ "$$REPLY" =~ ^[Yy]$$ ]]; then \
					echo "Proceeding with force removal..."; \
					docker rm -f dgraph-zero; \
					echo "✅ Conflicting 'dgraph-zero' container force removed."; \
				else \
					echo "Aborting. Please manually resolve the 'dgraph-zero' conflict before proceeding, or run 'make clean-dgraph-zero'."; \
					exit 1; \
				fi; \
			else \
				echo "Aborting (non-interactive mode). Please manually remove the conflicting 'dgraph-zero' container (e.g., 'docker rm -f dgraph-zero') and retry, or run 'make clean-dgraph-zero'."; \
				exit 1; \
			fi; \
		fi; \
	fi
	# Rest of preflight operations (network, volume, dir creation)
	@docker network create "$(EXTERNAL_NETWORK_NAME)" >/dev/null 2>&1 || true
	@if [ "$(DGRAPH_DATA_MODE)" = "volume" ]; then \
		echo "INFO: Dgraph data mode is 'volume', ensuring volumes exist..."; \
		docker volume create "$(DGRAPH_DATA_VOLUME_ZERO)" >/dev/null 2>&1 || true; \
		docker volume create "$(DGRAPH_DATA_VOLUME_ALPHA)" >/dev/null 2>&1 || true; \
	else \
		echo "INFO: Dgraph data mode is 'bind', ensuring directories exist..."; \
		mkdir -p "$(DGRAPH_STACK_DIR)/dgraph/zero"; \
		mkdir -p "$(DGRAPH_STACK_DIR)/dgraph/alpha"; \
	fi
	mkdir -p "$(SBOMS_DIR)" "$(BUILD_DIR)" "$(SCHEMA_DIR)" "$(OUT_DIR)"

# Setup now simply depends on preflight, the actual setup logic is in preflight.
setup: preflight
	@echo "--- Docker Compose services ready to be brought up ---"

# Bring up all services
up: preflight
	docker compose -f "$(COMPOSE_FILE)" up -d

# Bring down all services
down:
	docker compose -f "$(COMPOSE_FILE)" down --remove-orphans

# Clean all persistent data and build artifacts
clean: down
	@echo "--- Cleaning up persistent data and build artifacts ---"
	@if [ "$(DGRAPH_DATA_MODE)" = "volume" ]; then \
		echo "INFO: Removing Dgraph Docker volumes..."; \
		docker volume rm "$(DGRAPH_DATA_VOLUME_ZERO)" "$(DGRAPH_DATA_VOLUME_ALPHA)" >/dev/null 2>&1 || true; \
	else \
		echo "INFO: Removing Dgraph bind mount directories..."; \
		rm -rf "$(DGRAPH_STACK_DIR)/dgraph/zero" "$(DGRAPH_STACK_DIR)/dgraph/alpha"; \
	fi
	rm -rf "$(BUILD_DIR)" "$(OUT_DIR)" "$(GUAC_DATA_PATH)" "$(BENCHMARK_DIR)"
	@docker network rm "$(EXTERNAL_NETWORK_NAME)" >/dev/null 2>&1 || true
	@echo "--- Cleanup complete ---"

# Show container, network, volume, and config variable status
status:
	@echo "--- Container Status ---"
	docker compose -f "$(COMPOSE_FILE)" ps
	@echo "\n--- Docker Networks ---"
	$(MAKE) print-docker-networks
	@echo "\n--- Volumes ---"
	$(MAKE) print-docker-volumes
	@echo "\n--- Environment Variables (by context) ---"
	$(MAKE) print-vars
	@echo "\n--- Merged Docker Compose Config ---"
	@mkdir -p docs
	docker compose -f "$(COMPOSE_FILE)" config > docs/docker-compose.merged.yaml
	@echo "Merged config written to docs/docker-compose.merged.yaml"

logs: preflight
	docker compose -f "$(COMPOSE_FILE)" logs -f

# ============================================================================
# === Data Pipeline Targets ===
# ============================================================================

ingest-sboms: preflight
	@echo "--- Ingesting SBOMs from ./$(SBOMS_DIR) into GUAC ---"
	docker compose exec guac-graphql /opt/guac/guacone collect files --csub-addr guac-collectsub:2782 --gql-addr http://localhost:$(GUAC_GRAPHQL_PORT)/query /sboms

extract: preflight
	@echo "--- Extracting from Mesh to RDF ---"
	@if [ "$(USE_LOCAL_TOOLS)" = "1" ]; then \
		echo "[local mode] Running extractor script..."; \
		(cd guac-mesh-graphql && npm run extract); \
	else \
		echo "[container mode] Running extractor in Docker..."; \
		docker compose --profile tools -f compose/tools.yml run --rm extractor; \
	fi

demo-1m: preflight clean setup fetch-benchmark-data
	@echo "--- [DEMO] Starting Dgraph Zero for bulk load ---"
	docker compose -f compose/dgraph.yml up -d dgraph-zero
	@echo "--- [DEMO] Waiting for Zero to be ready..."
	@sleep 5
	@echo "--- [DEMO] Running Dgraph Bulk Loader with 1M RDF dataset ---"
	time docker compose --profile tools -f compose/dgraph.yml run --rm \
	  "$(DGRAPH_BULK_LOADER_SERVICE)" dgraph bulk -f /dgraph/benchmark/1million.rdf.gz -s /dgraph/benchmark/1million.schema $(DGRAPH_BULK_ARGS)
	@echo "--- [DEMO] Bulk load finished. Bringing down Zero. ---"
	docker compose -f compose/dgraph.yml down
	@echo "--- [DEMO] Moving generated data into place for Alpha..."
	if [ "$(DGRAPH_DATA_MODE)" = "volume" ]; then \
		echo "ERROR: Bulk loader demo does not support 'volume' mode yet. Please use 'bind' mode."; exit 1; \
	fi
	mv "$(OUT_DIR)/0/p" "$(DGRAPH_STACK_DIR)/dgraph/alpha/"
	rm -rf "$(OUT_DIR)"
	@echo "--- [DEMO] Starting all services with newly loaded data ---"
	$(MAKE) up
	@echo "--- [DEMO] Done. Dgraph is populated. Access Ratel at http://localhost:$(DGRAPH_RATEL_PORT_HOST) ---"

# ============================================================================
# === Benchmarking & Data Utilities Targets ===
# ============================================================================

fetch-benchmark-data: preflight
	@if [ -f "$(BENCHMARK_DIR)/1million.rdf.gz" ]; then \
		echo "INFO: Benchmark data already exists. Skipping download."; \
	else \
		echo "--- Fetching 1million RDF and schemas for benchmarking... ---"; \
		mkdir -p "$(BENCHMARK_DIR)"; \
		wget -q --show-progress -O "$(BENCHMARK_DIR)/1million.rdf.gz" https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.rdf.gz; \
		wget -q --show-progress -O "$(BENCHMARK_DIR)/1million.schema" https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.schema; \
		wget -q --show-progress -O "$(BENCHMARK_DIR)/1million-noindex.schema" https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million-noindex.schema; \
	fi

# ============================================================================
# === Other Utilities Targets ===
# ============================================================================

validate: preflight
	@./scripts/validate.sh

check-dockerfiles: preflight
	@echo "--- Checking for required Dockerfiles referenced in compose files... ---"
	missing=0; \
	for compose in "$(COMPOSE_FILE)" compose/*.yml; do \
	  grep 'build:' "$$compose" | sed 's/.*build:\s*\(.*\)/\1/' | while read -r dir; do \
	    if [ -n "$$dir" ] && [ ! -f "$$dir/Dockerfile" ]; then \
	      echo "❌ Missing Dockerfile: $$dir/Dockerfile (referenced in $${compose})"; \
	      missing=1; \
	    fi; \
	  done; \
	done; \
	if [ "$$missing" -eq 0 ]; then \
	  echo "✅ All referenced Dockerfiles are present."; \
	fi; exit $$missing