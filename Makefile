# Graphtastic GUAC Spoke Makefile Control Plane
#
# This Makefile is the single source of truth for all developer and CI workflows in this project.
# All operational tasks—setup, orchestration, diagnostics, data pipeline, and benchmarking—must be run via these targets.
#
# === Main Targets ===
#   help                  - Show this help message and a summary of all targets.
#   setup                 - Create shared Docker resources (networks, etc).
#   up                    - Bring up all services (full stack).
#   down                  - Bring down all services.
#   clean                 - Remove all containers, networks, persistent data, and benchmarking data.
#   status                - Show container, network, and volume status (diagnostics).
#   logs                  - Tail logs for all running services.
#
# === Service Management ===
#   svc-up                - Bring up a specific compose file (and optionally a service).
#   svc-down              - Bring down a specific compose file (and optionally a service).
#   svc-logs              - Tail logs for a specific compose file (and optionally a service).
#
# === Data Pipeline ===
#   ingest-sboms          - Ingest SBOMs from the ./sboms directory into GUAC.
#   extract               - Run the ETL script to extract from Mesh and generate RDF.
#   seed                  - Perform a full, clean data seed from SBOMs to Dgraph (end-to-end pipeline).
#
# === Benchmarking & Utilities ===
#   fetch-benchmark-data  - Download 1million RDF and schemas for benchmarking.
#   wipe-dgraph-data      - Remove all Dgraph persistent data and build output (for benchmarking).
#   benchmark-bulk-indexed    - Benchmark Dgraph bulk loader with indexed schema (wipes data first).
#   benchmark-bulk-noindex    - Benchmark Dgraph bulk loader with no-index schema (wipes data first).
#
# === Notes ===
# - All targets are orchestrated via Docker Compose and follow the Principle of the Makefile Control Plane.
# - Never run docker or docker compose directly—always use these targets.
# - For more details, run: make help

.PHONY: help
help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  setup                - Create shared Docker resources"
	@echo "  up                   - Bring up all services"
	@echo "  down                 - Bring down all services"
	@echo "  clean                - Run 'down' and remove persistent data (including benchmarking data)"
	@echo "  wipe-dgraph-data     - Remove all Dgraph persistent data and build output (for benchmarking)"
	@echo "  fetch-benchmark-data - Download 1million RDF and schemas for benchmarking"
	@echo "  benchmark-bulk-indexed   - Benchmark Dgraph bulk loader with indexed schema (wipes data first)"
	@echo "  benchmark-bulk-noindex   - Benchmark Dgraph bulk loader with no-index schema (wipes data first)"
	@echo "  ingest-sboms         - Ingest SBOMs from the ./sboms directory into GUAC"
	@echo "  extract              - Run the ETL script to extract from Mesh and generate RDF"
	@echo "  seed                 - Perform a full, clean data seed from SBOMs to Dgraph"
	@echo "  status               - Show container, network, and volume status (diagnostics)"
	@echo "  logs                 - Tail logs for all running services"
	@echo "  svc-up SVC=compose/xx.yml [SERVICE=service]   - Bring up a specific compose file (and optionally a service)"
	@echo "  svc-down SVC=compose/xx.yml [SERVICE=service] - Bring down a specific compose file (and optionally a service)"
	@echo "  svc-logs SVC=compose/xx.yml [SERVICE=service] - Tail logs for a specific compose file (and optionally a service)"
# Remove Dgraph persistent data (for benchmarking bulk loader)
.PHONY: wipe-dgraph-data
wipe-dgraph-data:
	rm -rf ./dgraph-stack
	rm -rf ./build


# Benchmark Dgraph bulk loader with indexed schema (full Compose control)
.PHONY: benchmark-bulk-indexed
benchmark-bulk-indexed:
	$(MAKE) clean
	@echo "[Benchmark] Bringing up Dgraph Zero only..."
	docker compose -f compose/dgraph.yml up -d dgraph-zero
	@echo "[Benchmark] Bulk loading with indexed schema..."
	time docker compose -f compose/dgraph.yml run --rm \
	  -v $(shell pwd)/guac-mesh-graphql/benchmark:/dgraph/benchmark \
	  dgraph-zero dgraph bulk -f /dgraph/benchmark/1million.rdf.gz -s /dgraph/benchmark/1million.schema --map_shards=1 --reduce_shards=1
	$(MAKE) down


# Benchmark Dgraph bulk loader with no-index schema (full Compose control)
.PHONY: benchmark-bulk-noindex
benchmark-bulk-noindex:
	$(MAKE) clean
	@echo "[Benchmark] Bringing up Dgraph Zero only..."
	docker compose -f compose/dgraph.yml up -d dgraph-zero
	@echo "[Benchmark] Bulk loading with no-index schema..."
	time docker compose -f compose/dgraph.yml run --rm \
	  -v $(shell pwd)/guac-mesh-graphql/benchmark:/dgraph/benchmark \
	  dgraph-zero dgraph bulk -f /dgraph/benchmark/1million.rdf.gz -s /dgraph/benchmark/1million-noindex.schema --map_shards=1 --reduce_shards=1
	$(MAKE) down

# Fetch benchmarking RDF and schema files for Dgraph
.PHONY: fetch-benchmark-data
fetch-benchmark-data:
	@echo "Creating benchmark directory and fetching 1million RDF and schemas..."
	mkdir -p guac-mesh-graphql/benchmark
	@echo "Downloading 1million.rdf.gz..."
	wget -O guac-mesh-graphql/benchmark/1million.rdf.gz https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.rdf.gz
	@echo "Downloading 1million.schema..."
	wget -O guac-mesh-graphql/benchmark/1million.schema https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million.schema
	@echo "Downloading 1million-noindex.schema..."
	wget -O guac-mesh-graphql/benchmark/1million-noindex.schema https://github.com/hypermodeinc/dgraph-benchmarks/raw/refs/heads/main/data/1million-noindex.schema
	@echo "Benchmark RDF and schema files downloaded to guac-mesh-graphql/benchmark/."

# Stop only Dgraph Alpha containers
.PHONY: stop-alpha
stop-alpha:
	docker compose -f compose/dgraph.yml stop dgraph-alpha || true

# Start only Dgraph Alpha containers
.PHONY: start-alpha
start-alpha:
	docker compose -f compose/dgraph.yml start dgraph-alpha || true

# Makefile Control Plane for the GUAC Spoke
# Check for missing Dockerfiles referenced in compose files
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
	if [ "$$missing" -eq 1 ]; then \
	  echo "One or more Dockerfiles are missing. Please add them before proceeding."; \
	  exit 1; \
	else \
	  echo "✅ All referenced Dockerfiles are present."; \
	fi


# Ensure .env exists by copying from .env.example if needed, then include it
up: check-dockerfiles

ifneq ("$(wildcard .env.example)",""")
    ifeq ("$(wildcard .env)",""")
        $(shell cp .env.example .env)
    endif
    include .env
    export
endif

seed: check-dockerfiles
EXTERNAL_NETWORK_NAME ?= graphtastic_net
COMPOSE_FILE ?= docker-compose.yml

.PHONY: help setup up down clean status logs svc-up svc-down svc-logs ingest-sboms extract seed

help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  setup                - Create shared Docker resources"
	@echo "  up                   - Bring up all services"
	@echo "  down                 - Bring down all services"
	@echo "  clean                - Run 'down' and remove persistent data (including benchmarking data)"
	@echo "  wipe-dgraph-data     - Remove all Dgraph persistent data and build output (for benchmarking)"
	@echo "  fetch-benchmark-data - Download 1million RDF and schemas for benchmarking"
	@echo "  benchmark-bulk-indexed   - Benchmark Dgraph bulk loader with indexed schema (wipes data first)"
	@echo "  benchmark-bulk-noindex   - Benchmark Dgraph bulk loader with no-index schema (wipes data first)"
	@echo "  ingest-sboms         - Ingest SBOMs from the ./sboms directory into GUAC"
	@echo "  extract              - Run the ETL script to extract from Mesh and generate RDF"
	@echo "  seed                 - Perform a full, clean data seed from SBOMs to Dgraph"
	@echo "  status               - Show container, network, and volume status (diagnostics)"
	@echo "  logs                 - Tail logs for all running services"
	@echo "  svc-up SVC=compose/xx.yml [SERVICE=service]   - Bring up a specific compose file (and optionally a service)"
	@echo "  svc-down SVC=compose/xx.yml [SERVICE=service] - Bring down a specific compose file (and optionally a service)"
	@echo "  svc-logs SVC=compose/xx.yml [SERVICE=service] - Tail logs for a specific compose file (and optionally a service)"

# --- Core Service Management ---

setup:
	@echo "--- Creating external network: $(EXTERNAL_NETWORK_NAME) ---"
	@docker network create $(EXTERNAL_NETWORK_NAME) >/dev/null 2>&1 || true
	# GUAC Postgres uses bind mount only for persistent data (see compose/guac.yml)
	# TODO: Add volume creation logic for GUAC Postgres when/if volume mode is supported

up:
	docker compose -f $(COMPOSE_FILE) up -d

down:
	docker compose -f $(COMPOSE_FILE) down

clean:
	@echo "--- Performing a full cleanup ---"
	docker compose -f $(COMPOSE_FILE) down -v --remove-orphans
	rm -rf ./dgraph-stack
	rm -rf ./build
	rm -rf guac-mesh-graphql/benchmark
	# TODO: Add volume removal logic for GUAC Postgres when volume mode is supported

status:
	@echo "--- Container Status ---"
	docker compose -f $(COMPOSE_FILE) ps
	@echo "--- Docker Networks ---"
	docker network ls
	@echo "--- dgraph-net Network Inspect ---"
	docker network inspect dgraph-net | jq '.[0].Containers' || docker network inspect dgraph-net
	@echo "--- graphtastic_net Network Inspect ---"
	docker network inspect $(EXTERNAL_NETWORK_NAME) | jq '.[0].Containers' || docker network inspect $(EXTERNAL_NETWORK_NAME)
	@echo "--- Volumes ---"
	docker volume ls
	@echo "--- Disk Usage (dgraph-stack, build, sboms) ---"
	du -sh ./dgraph-stack 2>/dev/null || true
	du -sh ./build 2>/dev/null || true
	du -sh ./sboms 2>/dev/null || true

logs:
	@echo "--- Tailing logs for all running services ---"
	docker compose -f $(COMPOSE_FILE) logs -f

# --- Generic Service Management ---

svc-up:
	@if [ -z "$(SVC)" ]; then \
		echo "Error: SVC (compose file) is required."; exit 1; \
	fi; \
	docker compose -f $(SVC) up -d $(SERVICE)

svc-down:
	@if [ -z "$(SVC)" ]; then \
		echo "Error: SVC (compose file) is required."; exit 1; \
	fi; \
	docker compose -f $(SVC) down $(SERVICE)

svc-logs:
	@if [ -z "$(SVC)" ]; then \
		echo "Error: SVC (compose file) is required."; exit 1; \
	fi; \
	docker compose -f $(SVC) logs -f $(SERVICE)

# --- Data Pipeline ---

ingest-sboms:
	@echo "--- Ingesting SBOMs into GUAC ---"
	docker compose exec guac-graphql /opt/guac/guacone collect files --csub-addr guac-collectsub:2782 --gql-addr http://localhost:8080/query --add-vuln-on-ingest --add-license-on-ingest --add-eol-on-ingest /sboms

extract:
	@echo "--- Extracting from Mesh to RDF ---"
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
			 make ingest-sboms
			 make extract
			 @echo "--- Stopping Dgraph Alpha before bulk load (only Zero should be running) ---"
			 $(MAKE) stop-alpha
			 @echo "--- Running Dgraph Bulk Loader (initial import, not live loader) ---"
			 # The following command runs the Dgraph Bulk Loader in a container, mounting the RDF and schema files.
			 docker run --rm \
				 -v $(shell pwd)/build:/dgraph/build \
				 -v $(shell pwd)/schema:/dgraph/schema \
				 dgraph/dgraph:latest \
				 dgraph bulk -f /dgraph/build/guac.rdf.gz -s /dgraph/schema/schema.txt --map_shards=1 --reduce_shards=1
			 @echo "--- Bulk load complete. ---"
			 @echo "--- Starting Dgraph Alpha after bulk load ---"
			 $(MAKE) start-alpha
			 @echo "--- IMPORTANT: Copy the generated out/0/p directory to your Dgraph Alpha's data directory before starting Alpha if not already done. ---"
			 @echo "For small datasets, start one Alpha, copy out/0/p, start Alpha, then add replicas. For larger datasets, copy to all Alpha nodes before starting them."
			 @echo "See https://docs.hypermode.com/dgraph/admin/bulk-loader for details."
			 @echo "--- Seed process finished. ---"
