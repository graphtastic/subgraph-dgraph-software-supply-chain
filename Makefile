# Makefile Control Plane for the GUAC Spoke

# Ensure .env exists by copying from .env.example if needed, then include it
ifneq ("$(wildcard .env.example)","")
    ifeq ("$(wildcard .env)","")
        $(shell cp .env.example .env)
    endif
    include .env
    export
endif

EXTERNAL_NETWORK_NAME ?= graphtastic_net
COMPOSE_FILE ?= docker-compose.yml

.PHONY: help setup up down clean status logs svc-up svc-down svc-logs ingest-sboms extract seed

help:
	@echo "Usage: make [target]"
	@echo "Targets:"
	@echo "  setup                - Create shared Docker resources"
	@echo "  up                   - Bring up all services"
	@echo "  down                 - Bring down all services"
	@echo "  clean                - Run 'down' and remove persistent data"
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
	# TODO: Add volume removal logic for GUAC Postgres when volume mode is supported

status:
	@echo "--- Container Status ---"
	docker compose $(COMPOSE_FILE) ps
	@echo "--- Docker Networks ---"
	docker network $(COMPOSE_FILE) ls
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
	docker compose $(COMPOSE_FILE) logs -f

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
	# TODO: Add actual command to ingest SBOMs

extract:
	@echo "--- Extracting from Mesh to RDF ---"
	# TODO: Add actual command to extract data

seed: clean setup up
	@echo "--- Starting full data seed process ---"
	make ingest-sboms
	make extract
	@echo "--- Seeding Dgraph from RDF ---"
	# TODO: Add dgraph bulk/live loader command here
	@echo "--- Seed complete! ---"