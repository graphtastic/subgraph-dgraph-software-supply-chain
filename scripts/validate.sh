#!/bin/bash

# Graphtastic Environment Validation Script
# This script performs a series of health checks to validate the running environment.

# --- Helper Functions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
SUCCESS=0

# Usage: check_port <host> <port> <service_name>
check_port() {
  local host=$1
  local port=$2
  local name=$3
  printf "  - Checking port %-5s for %-20s ... " "$port" "$name"
  if nc -z "$host" "$port"; then
    echo -e "${GREEN}✅ UP${NC}"
  else
    echo -e "${RED}❌ DOWN${NC}"
    SUCCESS=1
  fi
}

# Usage: check_graphql_health <url> <service_name>
check_graphql_health() {
  local url=$1
  local name=$2
  printf "  - Checking GraphQL health for %-12s ... " "$name"
  # Use --fail to exit with non-zero on server error, -s for silent, -o to discard output
  if curl --fail -s -o /dev/null -X POST -H "Content-Type: application/json" --data '{"query":"{__typename}"}' "$url"; then
    echo -e "${GREEN}✅ OK${NC}"
  else
    echo -e "${RED}❌ FAILED${NC}"
    SUCCESS=1
  fi
}

# --- Main Validation Logic ---
echo -e "${YELLOW}--- Running Graphtastic Environment Validation ---${NC}"

echo "1. Validating Public Endpoints (Host Access)"
check_port localhost 8080 "GUAC GraphQL"
check_port localhost 4000 "GraphQL Mesh"
check_port localhost 8081 "Dgraph Alpha (GraphQL)"
check_port localhost 9081 "Dgraph Alpha (gRPC)"
check_port localhost 8001 "Dgraph Ratel UI"

echo ""
echo "2. Validating GraphQL API Health"
check_graphql_health http://localhost:8080/query "GUAC GraphQL"
check_graphql_health http://localhost:4000/graphql "GraphQL Mesh"
check_graphql_health http://localhost:8081/graphql "Dgraph Alpha"

echo ""
if [ $SUCCESS -eq 0 ]; then
  echo -e "${GREEN}🎉 All checks passed. The environment appears to be healthy!${NC}"
else
  echo -e "${RED}🔥 Some validation checks failed. Please review the output above.${NC}"
  echo -e "${YELLOW}Running 'make status' for diagnostics...${NC}"
  make status
  exit 1
fi