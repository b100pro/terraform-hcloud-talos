#!/bin/bash
# Talos OS Upgrade Script
# Performs rolling upgrades with custom extensions via Image Factory
#
# Usage: ./upgrade-talos.sh <version>
# Example: ./upgrade-talos.sh v1.12.1

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TALOSCONFIG="${TALOSCONFIG:-./talosconfig}"
SCHEMATIC_FILE="./_packer/schematic.yaml"
HEALTH_TIMEOUT=300  # 5 minutes
HEALTH_INTERVAL=10

# Parse arguments
VERSION="${1}"

if [ -z "$VERSION" ]; then
  echo -e "${RED}Error: Version argument required${NC}"
  echo "Usage: $0 <version>"
  echo "Example: $0 v1.12.1"
  exit 1
fi

# Ensure version starts with 'v'
if [[ ! "$VERSION" =~ ^v ]]; then
  VERSION="v${VERSION}"
fi

echo -e "${BLUE}=== Talos Upgrade Script ===${NC}"
echo -e "Target version: ${GREEN}${VERSION}${NC}"
echo ""

# Check prerequisites
if ! command -v talosctl &> /dev/null; then
  echo -e "${RED}Error: talosctl not found${NC}"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo -e "${RED}Error: jq not found${NC}"
  exit 1
fi

if [ ! -f "$TALOSCONFIG" ]; then
  echo -e "${RED}Error: talosconfig not found at $TALOSCONFIG${NC}"
  exit 1
fi

if [ ! -f "$SCHEMATIC_FILE" ]; then
  echo -e "${RED}Error: schematic.yaml not found at $SCHEMATIC_FILE${NC}"
  exit 1
fi

# Get schematic ID from Image Factory
echo -e "${YELLOW}Getting schematic ID from Image Factory...${NC}"
SCHEMATIC_RESPONSE=$(curl -sX POST --data-binary @"$SCHEMATIC_FILE" https://factory.talos.dev/schematics)
SCHEMATIC_ID=$(echo "$SCHEMATIC_RESPONSE" | jq -r '.id')

if [ -z "$SCHEMATIC_ID" ] || [ "$SCHEMATIC_ID" == "null" ]; then
  echo -e "${RED}Error: Failed to get schematic ID${NC}"
  echo "Response: $SCHEMATIC_RESPONSE"
  exit 1
fi

echo -e "Schematic ID: ${GREEN}${SCHEMATIC_ID}${NC}"

# Build installer image URL
IMAGE="factory.talos.dev/installer/${SCHEMATIC_ID}:${VERSION}"
echo -e "Installer image: ${GREEN}${IMAGE}${NC}"
echo ""

# Get nodes - prefer environment variables, fallback to talosconfig
echo -e "${YELLOW}Detecting nodes...${NC}"

if [ -n "$CONTROL_PLANES" ]; then
  echo -e "Using CONTROL_PLANES from environment"
else
  # Try to get nodes from talosconfig
  ENDPOINTS=$(talosctl --talosconfig "$TALOSCONFIG" config info 2>/dev/null | grep -E "^\s+Endpoints:" | sed 's/.*Endpoints:\s*//' | tr ',' ' ')
  CONTROL_PLANES="$ENDPOINTS"
fi

if [ -z "$CONTROL_PLANES" ]; then
  echo -e "${RED}Could not detect nodes${NC}"
  echo "Please set CONTROL_PLANES environment variable:"
  echo "  export CONTROL_PLANES='tmainc1 tmainc2 tmainc3'"
  echo "  export WORKERS='tmainw1 tmainw2'"
  exit 1
fi

# WORKERS can be empty (optional)
WORKERS="${WORKERS:-}"

echo -e "Control planes: ${GREEN}${CONTROL_PLANES}${NC}"
echo -e "Workers: ${GREEN}${WORKERS:-none}${NC}"
echo ""

# Function to wait for node health
wait_for_health() {
  local node=$1
  local elapsed=0

  echo -e "  Waiting for ${node} to be healthy..."

  while [ $elapsed -lt $HEALTH_TIMEOUT ]; do
    if talosctl --talosconfig "$TALOSCONFIG" --nodes "$node" health --server=false 2>/dev/null; then
      echo -e "  ${GREEN}${node} is healthy${NC}"
      return 0
    fi
    sleep $HEALTH_INTERVAL
    elapsed=$((elapsed + HEALTH_INTERVAL))
    echo -e "  Waiting... (${elapsed}s/${HEALTH_TIMEOUT}s)"
  done

  echo -e "  ${RED}Timeout waiting for ${node} health${NC}"
  return 1
}

# Function to upgrade a node
upgrade_node() {
  local node=$1
  local node_type=$2

  echo -e "${BLUE}Upgrading ${node_type}: ${node}${NC}"

  # Get current SERVER version (skip client version, get server's Tag)
  CURRENT=$(talosctl --talosconfig "$TALOSCONFIG" --nodes "$node" version 2>/dev/null | grep -A20 "Server:" | grep "Tag:" | head -1 | awk '{print $2}')
  echo -e "  Current version: ${YELLOW}${CURRENT}${NC}"
  echo -e "  Target version: ${GREEN}${VERSION}${NC}"

  if [ "$CURRENT" == "$VERSION" ]; then
    echo -e "  ${GREEN}Already at target version, skipping${NC}"
    return 0
  fi

  # Perform upgrade (don't use --preserve to ensure machine config is applied correctly)
  echo -e "  Starting upgrade..."
  if ! talosctl --talosconfig "$TALOSCONFIG" --nodes "$node" upgrade --image "$IMAGE"; then
    echo -e "  ${RED}Upgrade command failed for ${node}${NC}"
    return 1
  fi

  # Wait for node to come back
  echo -e "  Waiting for reboot..."
  sleep 30

  # Wait for health
  if ! wait_for_health "$node"; then
    echo -e "  ${RED}Node ${node} did not become healthy${NC}"
    return 1
  fi

  # Verify server version
  NEW_VERSION=$(talosctl --talosconfig "$TALOSCONFIG" --nodes "$node" version 2>/dev/null | grep -A20 "Server:" | grep "Tag:" | head -1 | awk '{print $2}')
  echo -e "  ${GREEN}Upgraded ${node}: ${CURRENT} -> ${NEW_VERSION}${NC}"
  echo ""

  return 0
}

# Track results
FAILED_NODES=""
SUCCESS_COUNT=0
FAIL_COUNT=0

# Upgrade control planes first
echo -e "${BLUE}=== Upgrading Control Planes ===${NC}"
for node in $CONTROL_PLANES; do
  if upgrade_node "$node" "control-plane"; then
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_NODES="$FAILED_NODES $node"
    echo -e "${YELLOW}Warning: Continuing with remaining nodes...${NC}"
  fi
done

# Upgrade workers
if [ -n "$WORKERS" ]; then
  echo -e "${BLUE}=== Upgrading Workers ===${NC}"
  for node in $WORKERS; do
    if upgrade_node "$node" "worker"; then
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAILED_NODES="$FAILED_NODES $node"
      echo -e "${YELLOW}Warning: Continuing with remaining nodes...${NC}"
    fi
  done
fi

# Summary
echo -e "${BLUE}=== Upgrade Summary ===${NC}"
echo -e "Target version: ${GREEN}${VERSION}${NC}"
echo -e "Successful: ${GREEN}${SUCCESS_COUNT}${NC}"
echo -e "Failed: ${RED}${FAIL_COUNT}${NC}"

if [ $FAIL_COUNT -gt 0 ]; then
  echo -e "${RED}Failed nodes:${FAILED_NODES}${NC}"
  exit 1
fi

echo -e "${GREEN}All nodes upgraded successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Update talos_version in terraform.tfvars to '${VERSION#v}'"
echo "2. Rebuild Packer images: cd _packer && ./create.sh"
