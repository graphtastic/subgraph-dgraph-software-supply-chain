# Graphtastic GUAC Spoke Makefile Control Plane
#
# This Makefile is the single source of truth for all developer and CI workflows in this project.
# All operational tasks—setup, orchestration, diagnostics, data pipeline, and benchmarking—must be run via these targets.
#
# === Configuration Variables ===
EXTERNAL_NETWORK_NAME ?= graphtastic_net
COMPOSE_FILE ?= docker-compose.yml

# Project-specific paths
DGRAPH_STACK_DIR := dgraph-stack
BUILD_DIR := build
SBOMS_DIR := sboms
BENCHMARK_DIR := guac-mesh-graphql/benchmark
SCHEMA_DIR := schema

# Dgraph bulk loader specific configuration
DGRAPH_BULK_LOADER_SERVICE := dgraph-bulk-loader
DGRAPH_BULK_ARGS := --map_shards=1 --reduce_shards=1

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
	@echo "=== Service Management ==="
	@echo "  svc-up SVC=compose/xx.yml [SERVICE=service]   - Bring up a specific compose file (and optionally a service)."
	@echo "  svc-down SVC=compose/xx.yml [SERVICE=service] - Bring down a specific compose file (and optionally a service)."
	@echo "  svc-logs SVC=compose/xx.yml [SERVICE=service] - Tail logs for a specific compose file (and optionally a service)."
	@echo ""
	@echo "=== Data Pipeline ==="
	@echo "  ingest-sboms         - Ingest SBOMs from the ./$(SBOMS_DIR) directory into GUAC."
	@echo "                         (Note: Targets GUAC's internal GraphQL API on localhost:8080 within its container)"
	@echo "  extract              - Run the ETL script to extract from Mesh and generate RDF."
	@echo "  seed                 - Perform a full, clean data seed from SBOMs to Dgraph (end-to-end pipeline)."
	@echo ""
	@echo "=== Benchmarking & Utilities ==="
	@echo "  fetch-benchmark-data - Download 1million RDF and schemas for benchmarking."
	@echo "  wipe-dgraph-data     - Remove all Dgraph persistent data and build output (for benchmarking)."
	@echo "  benchmark-bulk-indexed   - Benchmark Dgraph bulk loader with indexed schema (wipes data first)."
	@echo "  benchmark-bulk-noindex   - Benchmark Dgraph bulk loader with no-index schema (wipes data first)."
	@echo "  stop-alpha           - Stop only Dgraph Alpha containers."
	@echo "  start-alpha          - Start only Dgraph Alpha containers."
	@echo "  stop-zero            - Stop only Dgraph Zero containers."
	@echo "  start-zero           - Start only Dgraph Zero containers."
	@echo "  check-dockerfiles    - Check for missing Dockerfiles referenced in compose files."
	@echo "  check-envfile        - Ensure .env exists by copying from .env.example if needed."
	@echo ""
	@echo "=== Notes ==="
	@echo " - All targets are orchestrated via Docker Compose and follow the Principle of the Makefile Control Plane."
	@echo " - Never run 'docker' or 'docker compose' directly—always use these targets."
	@echo " - For more details, run: make help"

# --- Setup & Environment Checks ---

# Ensure .env exists by copying from .env.example if needed
.PHONY: check-envfile
check-envfile:
	@echo "Checking for .env file..."
	@if [ -f .env.example ] && [ ! -f .env ]; then \
	  echo ".env not found, copying from .env.example..."; \
	  cp .env.example .env; \
	fi

setup: check-envfile
	@echo "--- Initializing shared resources ---"
	# Create the external network required by some compose files (e.g., dgraph.yml, mesh.yml).
	# This uses a direct 'docker network create' as docker-compose itself does not create
	# networks declared as 'external: true'.
	@docker network create $(EXTERNAL_NETWORK_NAME) >/dev/null 2>&1 || true
	# GUAC Postgres uses bind mount only for persistent data (see compose/guac.yml)
	# TODO: Add volume creation logic for GUAC Postgres when/if volume mode is supported


# --- Core Service Management ---
up:
	docker compose -f $(COMPOSE_FILE) up -d

down:
	docker compose -f $(COMPOSE_FILE) down

clean:
	@echo "--- Performing a full cleanup ---"
	docker compose -f $(COMPOSE_FILE) down -v --remove-orphans
	rm -rf ./$(DGRAPH_STACK_DIR)
	rm -rf ./$(BUILD_DIR)
	rm -rf ./$(BENCHMARK_DIR)
	# TODO: Add volume removal logic for GUAC Postgres when volume mode is supported

status:
	@echo "--- Container Status ---"
	docker compose -f $(COMPOSE_FILE) ps
	@echo "--- Docker Networks ---"
	docker network ls
	@echo "--- Namespaced dgraph-net Network Inspect ---"
	docker network inspect subgraph-dgraph-software-supply-chain_dgraph-net | jq '.[0].Containers' || docker network inspect subgraph-dgraph-software-supply-chain_dgraph-net
	@echo "--- External graphtastic_net Network Inspect ---"
	docker network inspect $(EXTERNAL_NETWORK_NAME) | jq '.[0].Containers' || docker network inspect $(EXTERNAL_NETWORK_NAME)
	@echo "--- Volumes ---"
	docker volume ls
	@echo "--- Disk Usage ($(DGRAPH_STACK_DIR), $(BUILD_DIR), $(SBOMS_DIR)) ---"
	du -sh ./$(DGRAPH_STACK_DIR) 2>/dev/null || true
	du -sh ./$(BUILD_DIR) 2>/dev/null || true
	du -sh ./$(SBOMS_DIR) 2>/dev/null || true

logs:
	@echo "--- Tailing logs for all running services ---"
	docker compose -f $(COMPOSE_FILE) logs -f

# --- Generic Service Management ---
.PHONY: svc-up svc-down svc-logs
svc-up:
	@if [ -z "$(SVC)" ]; then \
		echo "Error: SVC (compose file) is required. Example: make svc-up SVC=compose/dgraph.yml"; exit 1; \
	fi; \
	docker compose -f $(SVC) up -d $(SERVICE)

svc-down:
	@if [ -z "$(SVC)" ]; then \
		echo "Error: SVC (compose file) is required. Example: make svc-down SVC=compose/dgraph.yml"; exit 1; \
	fi; \
	docker compose -f $(SVC) down $(SERVICE)

svc-logs:
	@if [ -z "$(SVC)" ]; then \
		echo "Error: SVC (compose file) is required. Example: make svc-logs SVC=compose/dgraph.yml"; exit 1; \
	fi; \
	docker compose -f $(SVC) logs -f $(SERVICE)

# --- Dgraph Specific Utilities ---
.PHONY: stop-alpha start-alpha stop-zero start-zero wipe-dgraph-data
stop-alpha:
	docker compose -f compose/dgraph.yml stop dgraph-alpha || true

start-alpha:
	docker compose -f compose/dgraph.yml start dgraph-alpha || true

stop-zero:
	docker compose -f compose/dgraph.yml stop dgraph-zero || true

start-zero:
	docker compose -f compose/dgraph.yml start dgraph-zero || true

# Remove Dgraph persistent data (for benchmarking bulk loader)
wipe-dgraph-data:
	rm -rf ./$(DGRAPH_STACK_DIR)
	rm -rf ./$(BUILD_DIR)


# --- Benchmarking & Data Utilities ---
.PHONY: fetch-benchmark-data benchmark-bulk-indexed benchmark-bulk-noindex

# Fetch benchmarking RDF and schema files for Dgraph
fetch-benchmark-data:
	@echo "Creating benchmark directory and fetching 1million RDF and schemas..."
	mkdir -p $(BENCHMARK_DIR)
	@echo "Downloading 1million.rdf.gz..."
	wget -O $(BENCHMARK_DIR)/1million.rdf.gz https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.rdf.gz
	@echo "Downloading 1million.schema..."
	wget -O $(BENCHMARK_DIR)/1million.schema https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.schema
	@echo "Downloading 1million-noindex.schema..."
	wget -O $(BENCHMARK_DIR)/1million-noindex.schema https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million-noindex.schema
	@echo "Benchmark RDF and schema files downloaded to $(BENCHMARK_DIR)/."

# Internal macro to run Dgraph bulk loader benchmarks
define _run-benchmark-bulk
	$(MAKE) clean
	@echo "[Benchmark] Bringing up Dgraph Zero only..."
	docker compose -f compose/dgraph.yml up -d dgraph-zero
	@echo "[Benchmark] Bulk loading with $(1)..."
	time docker compose -f $(COMPOSE_FILE) run --rm \
	  -v $(CURDIR)/$(BENCHMARK_DIR):/dgraph/benchmark \
	  $(DGRAPH_BULK_LOADER_SERVICE) dgraph bulk -f /dgraph/benchmark/1million.rdf.gz -s $(2) $(DGRAPH_BULK_ARGS)
	$(MAKE) down
endef

benchmark-bulk-indexed:
	$(call _run-benchmark-bulk,indexed schema,/dgraph/benchmark/1million.schema)

benchmark-bulk-noindex:
	$(call _run-benchmark-bulk,no-index schema,/dgraph/benchmark/1million-noindex.schema)

# --- Data Pipeline ---
.PHONY: ingest-sboms extract seed

ingest-sboms:
	@echo "--- Ingesting SBOMs from ./$(SBOMS_DIR) into GUAC ---"
	# This command runs inside the guac-graphql container and targets GUAC's
	# own internal GraphQL API, which typically runs on localhost:8080 within the container.
	docker compose exec guac-graphql /opt/guac/guacone collect files --csub-addr guac-collectsub:2782 --gql-addr http://localhost:8080/query --add-vuln-on-ingest --add-license-on-ingest --add-eol-on-ingest /sboms

extract:
	@echo "--- Extracting from Mesh to RDF ---"
       # Containerized by default for reproducibility; set USE_LOCAL_TOOLS=1 for native execution
       @if [ "$$USE_LOCAL_TOOLS" = "1" ]; then \
	       echo "[local mode] Running extractor script..."; \
	       ts-node-esm guac-mesh-graphql/scripts/extractor.ts; \
       else \
	       echo "[container mode] Running extractor in Docker..."; \
	       docker compose -f compose/tools.yml run --rm extractor ts-node-esm guac-mesh-graphql/scripts/extractor.ts; \
       fi

seed: clean setup up
	@echo "--- Starting full data seed process ---"
	$(MAKE) ingest-sboms
	$(MAKE) extract
	@echo "--- Stopping Dgraph Alpha before bulk load (only Zero should be running) ---"
	$(MAKE) stop-alpha
	@echo "--- Running Dgraph Bulk Loader (initial import, not live loader) ---"
	# The following command runs the Dgraph Bulk Loader in a container via docker compose run,
	# mounting the RDF and schema files from the host into the dgraph-bulk-loader service.
	docker compose -f $(COMPOSE_FILE) run --rm \
		-v $(CURDIR)/$(BUILD_DIR):/dgraph/build \
		-v $(CURDIR)/$(SCHEMA_DIR):/dgraph/schema \
		$(DGRAPH_BULK_LOADER_SERVICE) dgraph bulk -f /dgraph/build/guac.rdf.gz -s /dgraph/schema/schema.txt $(DGRAPH_BULK_ARGS)
	@echo "--- Bulk load complete. ---"
	@echo "--- Starting Dgraph Alpha after bulk load ---"
	$(MAKE) start-alpha
	@echo "--- IMPORTANT: Copy the generated out/0/p directory to your Dgraph Alpha's data directory before starting Alpha if not already done. ---"
	@echo "For small datasets, start one Alpha, copy out/0/p, start Alpha, then add replicas. For larger datasets, copy to all Alpha nodes before starting them."
	@echo "See https://docs.hypermode.com/dgraph/admin/bulk-loader for details."
	@echo "--- Seed process finished. ---"

# --- Other Utilities ---
.PHONY: check-dockerfiles
check-dockerfiles:
	@echo "Checking for required Dockerfiles referenced in compose files..."
	@missing=0; \
	for compose in compose/*.yml; do \
	  grep '^\s*build:' $$compose | awk '{print $$2}' | while read dir; do \
	    if [ -n "$$dir" ] && [ ! -f "$$dir/Dockerfile" ]; then \
	      echo "❌ Missing Dockerfile: $$dir/Dockerfile (referenced in $${compose})"; \
	      missing=1; \
	    fi; \
	  done; \
	done; \
	if [ "$$missing" -eq 0 ]; then \
	  echo "✅ All referenced Dockerfiles are present."; \
	fi