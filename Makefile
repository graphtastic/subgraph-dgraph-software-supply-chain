# ============================================================================
# Graphtastic Makefile Best Practices
# - Never use @echo inside a shell block (use shell echo only)
# - All recipes must be tab-indented, not space-indented
# - All targets must be defined only once
# - All .PHONY targets should be grouped together
# - Always quote variables in shell blocks to avoid empty alternations
# - Use 'make lint-makefile' to check for common issues
# ============================================================================
# Ensure COMPOSE_FILE is always set
COMPOSE_FILE ?= docker-compose.yml
############################################################
# Mesh/Extractor endpoints
MESH_ENDPOINT ?= http://guac-mesh-graphql:4000/graphql
GUAC_ENDPOINT ?= http://guac-graphql:8080/query
# GUAC Postgres data path
GUAC_DATA_PATH ?= ./dgraph-stack/guac-data

# === PORT VARIABLES (centralized) ===
# Dgraph Zero
DGRAPH_ZERO_GRPC_PORT ?= 5080
DGRAPH_ZERO_HTTP_PORT ?= 6080
DGRAPH_ZERO_GRPC_PORT_HOST ?= 5081
DGRAPH_ZERO_HTTP_PORT_HOST ?= 6081
# Dgraph Alpha
DGRAPH_ALPHA_GRPC_PORT ?= 9080
DGRAPH_ALPHA_HTTP_PORT ?= 8080
DGRAPH_ALPHA_GRPC_PORT_HOST ?= 9081
DGRAPH_ALPHA_HTTP_PORT_HOST ?= 8081
# Dgraph Ratel
DGRAPH_RATEL_PORT ?= 8000
DGRAPH_RATEL_PORT_HOST ?= 8001
# GUAC GraphQL
GUAC_GRAPHQL_PORT ?= 8080
GUAC_GRAPHQL_PORT_HOST ?= 8080
# Mesh GraphQL
MESH_GRAPHQL_PORT ?= 4000
MESH_GRAPHQL_PORT_HOST ?= 4000
# Postgres
POSTGRES_PORT ?= 5432
POSTGRES_PORT_HOST ?= 5432
############################################################
var-%:
	@echo $($*)
# Always include .env if present
-include .env
export

	  echo "==============================="; \
	  echo " WARNING: .env file not found! "; \
	  echo " Proceeding with Makefile defaults."; \
	  echo " To create a .env file, run:"; \
	  echo " The following values are in effect:"; \
	  $(MAKE) print-vars; \
	  echo "(see .env.example for all options)"; \
	  echo "==============================="; \
	fi

# Print all environment and port variables grouped by context
.PHONY: print-vars
print-vars:
	@echo ""
	@echo "[Core Networking & Compose]"
	@echo "  EXTERNAL_NETWORK_NAME = $(EXTERNAL_NETWORK_NAME)"
	@echo "  COMPOSE_FILE         = $(COMPOSE_FILE)"
	@echo ""
	@echo "[Dgraph Stack]"
	@echo "  DGRAPH_ALPHA_WHITELIST = $(DGRAPH_ALPHA_WHITELIST)"
	@echo "  DGRAPH_DATA_MODE       = $(DGRAPH_DATA_MODE)"
	@echo "  DGRAPH_DATA_VOLUME     = $(DGRAPH_DATA_VOLUME)"
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

# Project-specific paths
DGRAPH_STACK_DIR := dgraph-stack
BUILD_DIR := build
SBOMS_DIR := sboms
BENCHMARK_DIR := guac-mesh-graphql/benchmark
SCHEMA_DIR := schema
OUT_DIR := out

# Dgraph bulk loader specific configuration
DGRAPH_BULK_LOADER_SERVICE := dgraph-bulk-loader
DGRAPH_BULK_ARGS := --map_shards=1 --reduce_shards=1 --zero=dgraph-zero:5080

# === Main Targets ===
.PHONY: help setup up down clean status logs

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
	@echo ""
	@echo "=== Environment Variables (current values) ==="
	@$(MAKE) print-vars
	@echo "  See .env.example for all options and documentation."


setup: preflight
	@echo "--- Initializing shared resources ---"
	@docker network create $(EXTERNAL_NETWORK_NAME) >/dev/null 2>&1 || true
	@if [ "$(DGRAPH_DATA_MODE)" = "volume" ]; then \
		echo "INFO: Dgraph data mode is 'volume', ensuring volumes exist..."; \
		docker volume create $(DGRAPH_DATA_VOLUME_ZERO) >/dev/null 2>&1 || true; \
		docker volume create $(DGRAPH_DATA_VOLUME_ALPHA) >/dev/null 2>&1 || true; \
	else \
		echo "INFO: Dgraph data mode is 'bind', ensuring directories exist..."; \
		mkdir -p $(DGRAPH_STACK_DIR)/dgraph/zero; \
		mkdir -p $(DGRAPH_STACK_DIR)/dgraph/alpha; \
	fi
	mkdir -p $(SBOMS_DIR) $(BUILD_DIR) $(SCHEMA_DIR) $(OUT_DIR)

# --- Core Service Management ---
up: preflight setup
	docker compose -f $(COMPOSE_FILE) up -d

preflight:
	@if [ ! -f .env ]; then \
		@echo "--- Container Status ---"
		docker compose -f $(COMPOSE_FILE) ps
		@echo "\n--- Docker Networks ---"
		$(MAKE) print-docker-networks
		@echo "\n--- Volumes ---"
		$(MAKE) print-docker-volumes
		@echo "\n--- Environment Variables (by context) ---"
		$(MAKE) print-vars
		@echo "\n--- Merged Docker Compose Config ---"
		@mkdir -p docs
		docker compose -f $(COMPOSE_FILE) config > docs/docker-compose.merged.yaml
		@echo "Merged config written to docs/docker-compose.merged.yaml"

	# Print all environment and port variables grouped by context
	.PHONY: print-vars
	print-vars:
		@echo "[Core Networking & Compose]"
		@echo "  EXTERNAL_NETWORK_NAME = $(EXTERNAL_NETWORK_NAME)"
		@echo "  COMPOSE_FILE         = $(COMPOSE_FILE)"
		@echo ""
		@echo "[Dgraph Stack]"
		@echo "  DGRAPH_ALPHA_WHITELIST = $(DGRAPH_ALPHA_WHITELIST)"
		@echo "  DGRAPH_DATA_MODE       = $(DGRAPH_DATA_MODE)"
		@echo "  DGRAPH_DATA_VOLUME     = $(DGRAPH_DATA_VOLUME)"
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

	# Print docker networks with robust pattern
	.PHONY: print-docker-networks
	print-docker-networks:
		@if [ -n "$(EXTERNAL_NETWORK_NAME)" ]; then \
			pattern="NETWORK|$(EXTERNAL_NETWORK_NAME)|dgraph_internal_net|guac_internal_net"; \
		else \
			pattern="NETWORK|dgraph_internal_net|guac_internal_net"; \
		fi; \
		docker network ls | grep -E "$${pattern}" || true

	# Print docker volumes with robust pattern
	.PHONY: print-docker-volumes
	print-docker-volumes:
		@if [ -n "$(DGRAPH_DATA_VOLUME_ZERO)$(DGRAPH_DATA_VOLUME_ALPHA)" ]; then \
			pattern="VOLUME"; \
			[ -n "$(DGRAPH_DATA_VOLUME_ZERO)" ] && pattern="$${pattern}|$(DGRAPH_DATA_VOLUME_ZERO)"; \
			[ -n "$(DGRAPH_DATA_VOLUME_ALPHA)" ] && pattern="$${pattern}|$(DGRAPH_DATA_VOLUME_ALPHA)"; \
		else \
			pattern="VOLUME"; \
		fi; \
		docker volume ls | grep -E "$${pattern}" || true

	# Lint Makefile for common issues
	.PHONY: lint-makefile
	lint-makefile:
		@echo "Linting Makefile for common issues..."
		@grep -n '^ ' Makefile && echo 'ERROR: Space-indented recipe found!' && exit 1 || true
		@grep -n '@echo' Makefile | grep '\\' && echo 'ERROR: @echo found in shell block!' && exit 1 || true
		@echo "No common Makefile issues found."
	@echo "--- Merged Docker Compose Config ---"
	@mkdir -p docs
	docker compose -f $(COMPOSE_FILE) config > docs/docker-compose.merged.yaml
	@echo "Merged config written to docs/docker-compose.merged.yaml"

logs: preflight
	docker compose -f $(COMPOSE_FILE) logs -f

# --- Data Pipeline ---
.PHONY: ingest-sboms extract demo-1m

ingest-sboms: preflight
	@echo "--- Ingesting SBOMs from ./$(SBOMS_DIR) into GUAC ---"
	docker compose exec guac-graphql /opt/guac/guacone collect files --csub-addr guac-collectsub:2782 --gql-addr http://localhost:8080/query /sboms

extract: preflight
	@echo "--- Extracting from Mesh to RDF ---"
	@if [ "$$USE_LOCAL_TOOLS" = "1" ]; then \
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
	  $(DGRAPH_BULK_LOADER_SERVICE) dgraph bulk -f /dgraph/benchmark/1million.rdf.gz -s /dgraph/benchmark/1million.schema $(DGRAPH_BULK_ARGS)
	@echo "--- [DEMO] Bulk load finished. Bringing down Zero. ---"
	docker compose -f compose/dgraph.yml down
	@echo "--- [DEMO] Moving generated data into place for Alpha..."
	@if [ "$(DGRAPH_DATA_MODE)" = "volume" ]; then \
		echo "ERROR: Bulk loader demo does not support 'volume' mode yet. Please use 'bind' mode."; exit 1; \
	fi
	mv $(OUT_DIR)/0/p $(DGRAPH_STACK_DIR)/dgraph/alpha/
	rm -rf $(OUT_DIR)
	@echo "--- [DEMO] Starting all services with newly loaded data ---"
	$(MAKE) up
	@echo "--- [DEMO] Done. Dgraph is populated. Access Ratel at http://localhost:8001 ---"


# --- Benchmarking & Data Utilities ---
.PHONY: fetch-benchmark-data
fetch-benchmark-data: preflight
	@if [ -f "$(BENCHMARK_DIR)/1million.rdf.gz" ]; then \
		echo "INFO: Benchmark data already exists. Skipping download."; \
	else \
		echo "--- Fetching 1million RDF and schemas for benchmarking... ---"; \
		mkdir -p $(BENCHMARK_DIR); \
		wget -q --show-progress -O $(BENCHMARK_DIR)/1million.rdf.gz https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.rdf.gz; \
		wget -q --show-progress -O $(BENCHMARK_DIR)/1million.schema https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.schema; \
		wget -q --show-progress -O $(BENCHMARK_DIR)/1million-noindex.schema https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million-noindex.schema; \
	fi

# --- Other Utilities ---
.PHONY: check-dockerfiles validate
validate: preflight
	@./scripts/validate.sh

check-dockerfiles: preflight
	@echo "--- Checking for required Dockerfiles referenced in compose files... ---"
	@missing=0; \
	for compose in $(COMPOSE_FILE) compose/*.yml; do \
	  grep 'build:' $$compose | sed 's/.*build:\s*\(.*\)/\1/' | while read -r dir; do \
	    if [ -n "$$dir" ] && [ ! -f "$$dir/Dockerfile" ]; then \
	      echo "❌ Missing Dockerfile: $$dir/Dockerfile (referenced in $${compose})"; \
	      missing=1; \
	    fi; \
	  done; \
	done; \
	if [ "$$missing" -eq 0 ]; then \
	  echo "✅ All referenced Dockerfiles are present."; \
	fi; exit $$missing
