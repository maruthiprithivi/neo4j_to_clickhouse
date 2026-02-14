#!/bin/bash
# Register Neo4j CDC source connectors with Kafka Connect

set -e

CONNECT_URL="${CONNECT_URL:-http://kafka-connect:8083}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Waiting for Kafka Connect REST API at ${CONNECT_URL}..."

MAX_RETRIES=60
RETRY_COUNT=0
until curl -sf "${CONNECT_URL}/connectors" > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "${RETRY_COUNT}" -ge "${MAX_RETRIES}" ]; then
        echo "[FAIL] Kafka Connect did not become available after ${MAX_RETRIES} attempts"
        exit 1
    fi
    echo "  Attempt ${RETRY_COUNT}/${MAX_RETRIES} - waiting 5s..."
    sleep 5
done

echo "[OK] Kafka Connect is available"

# Register nodes CDC connector
echo ""
echo "Registering neo4j-cdc-nodes-source connector..."
RESPONSE=$(curl -sf -X POST "${CONNECT_URL}/connectors" \
    -H "Content-Type: application/json" \
    -d @"${SCRIPT_DIR}/neo4j-cdc-nodes-source.json")
echo "[OK] Nodes connector registered"

# Register relationships CDC connector
echo ""
echo "Registering neo4j-cdc-relationships-source connector..."
RESPONSE=$(curl -sf -X POST "${CONNECT_URL}/connectors" \
    -H "Content-Type: application/json" \
    -d @"${SCRIPT_DIR}/neo4j-cdc-relationships-source.json")
echo "[OK] Relationships connector registered"

# Verify connector status
echo ""
echo "Verifying connector status..."
sleep 3

for CONNECTOR in neo4j-cdc-nodes-source neo4j-cdc-relationships-source; do
    STATUS=$(curl -sf "${CONNECT_URL}/connectors/${CONNECTOR}/status" | python3 -c "
import sys, json
data = json.load(sys.stdin)
state = data['connector']['state']
print(state)
" 2>/dev/null || echo "UNKNOWN")
    echo "  ${CONNECTOR}: ${STATUS}"
done

echo ""
echo "Connector registration complete."
