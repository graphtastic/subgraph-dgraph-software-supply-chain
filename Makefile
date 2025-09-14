# Graphtastic GUAC Spoke Makefile Control Plane
#
# This Makefile is the single source of truth for all developer and CI workflows in this project.
# All operational tasks—setup, orchestration, diagnostics, data pipeline, and benchmarking—must be run via these targets.
#
# === Configuration Variables ===
include .env
export

EXTERNAL_NETWORK_NAME ?= graphtastic_net
COMPOSE_FILE ?= docker-compose.yml

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
	@echo "  status               - Show container, network, and volume status (diagnostics)."
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
	@echo "  check-envfile        - Ensure .env exists by copying from .env.example if needed."

# --- Setup & Environment Checks ---
.PHONY: check-envfile
check-envfile:
	@if [ ! -f .env ]; then \
	  echo "INFO: .env not found, creating from .env.example"; \
	  cp .env.example .env; \
	fi

setup: check-envfile
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
up: setup
	docker compose -f $(COMPOSE_FILE) up -d

down:
	docker compose -f $(COMPOSE_FILE) down --remove-orphans

clean:
	@echo "--- Performing a full cleanup ---"
	docker compose -f $(COMPOSE_FILE) down -v --remove-orphans
	rm -rf ./$(DGRAPH_STACK_DIR)
	rm -rf ./$(BUILD_DIR)
	rm -rf ./$(BENCHMARK_DIR)
	rm -rf ./$(OUT_DIR)
	@if [ "$(DGRAPH_DATA_MODE)" = "volume" ]; then \
		docker volume rm $(DGRAPH_DATA_VOLUME_ZERO) >/dev/null 2>&1 || true; \
		docker volume rm $(DGRAPH_DATA_VOLUME_ALPHA) >/dev/null 2>&1 || true; \
	fi

status:
	@echo "--- Container Status ---"
	docker compose -f $(COMPOSE_FILE) ps
	@echo "\n--- Docker Networks ---"
	@docker network ls | grep -E "NETWORK|$(EXTERNAL_NETWORK_NAME)|dgraph_internal_net|guac_internal_net"
	@echo "\n--- Volumes ---"
	@docker volume ls | grep -E "VOLUME|$(DGRAPH_DATA_VOLUME_ZERO)|$(DGRAPH_DATA_VOLUME_ALPHA)"

logs:
	docker compose -f $(COMPOSE_FILE) logs -f

# --- Data Pipeline ---
.PHONY: ingest-sboms extract demo-1m

ingest-sboms:
	@echo "--- Ingesting SBOMs from ./$(SBOMS_DIR) into GUAC ---"
	docker compose exec guac-graphql /opt/guac/guacone collect files --csub-addr guac-collectsub:2782 --gql-addr http://localhost:8080/query /sboms

extract:
	@echo "--- Extracting from Mesh to RDF ---"
	@if [ "$$USE_LOCAL_TOOLS" = "1" ]; then \
		echo "[local mode] Running extractor script..."; \
		(cd guac-mesh-graphql && npm run extract); \
	else \
		echo "[container mode] Running extractor in Docker..."; \
		docker compose --profile tools -f compose/tools.yml run --rm extractor; \
	fi


demo-1m: clean setup fetch-benchmark-data
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
fetch-benchmark-data:
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
validate:
	@./scripts/validate.sh

check-dockerfiles:
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
