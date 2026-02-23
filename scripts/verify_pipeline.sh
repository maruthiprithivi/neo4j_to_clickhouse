#!/bin/bash
set -e

echo "========================================"
echo "Neo4j → ClickHouse CDC Pipeline Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_service() {
    local service=$1
    local container=$2
    local check_cmd=$3
    
    echo -n "Checking $service... "
    if docker exec $container bash -c "$check_cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# 1. Check all services are running
echo "1. Checking service health:"
echo "----------------------------"

check_service "Zookeeper" "neo4j-cdc-zookeeper" "nc -z localhost 2181"
check_service "Kafka" "neo4j-cdc-kafka" "kafka-broker-api-versions --bootstrap-server localhost:9092"
check_service "Neo4j" "neo4j-cdc-source" "cypher-shell -u neo4j -p password123 'RETURN 1'"
check_service "ClickHouse" "neo4j-cdc-clickhouse" "clickhouse-client --query 'SELECT 1'"

echo ""

# 2. Check Kafka topics exist
echo "2. Checking Kafka topics:"
echo "-------------------------"

TOPICS=$(docker exec neo4j-cdc-kafka kafka-topics --list --bootstrap-server localhost:9092)

if echo "$TOPICS" | grep -q "neo4j.nodes"; then
    echo -e "${GREEN}✓${NC} neo4j.nodes topic exists"
else
    echo -e "${YELLOW}⚠${NC} neo4j.nodes topic not found"
fi

if echo "$TOPICS" | grep -q "neo4j.relationships"; then
    echo -e "${GREEN}✓${NC} neo4j.relationships topic exists"
else
    echo -e "${YELLOW}⚠${NC} neo4j.relationships topic not found"
fi

echo ""

# 3. Check ClickHouse tables
echo "3. Checking ClickHouse tables:"
echo "------------------------------"

TABLES=$(docker exec neo4j-cdc-clickhouse clickhouse-client --query "SHOW TABLES FROM neo4j_cdc FORMAT TSV")

for table in "kafka_node_events" "kafka_relationship_events" "node_changes" "relationship_changes"; do
    if echo "$TABLES" | grep -q "^$table$"; then
        echo -e "${GREEN}✓${NC} $table exists"
    else
        echo -e "${RED}✗${NC} $table missing"
    fi
done

echo ""

# 4. Check data counts
echo "4. Checking data ingestion:"
echo "---------------------------"

NODE_COUNT=$(docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT count() FROM neo4j_cdc.node_changes FORMAT TSV")
REL_COUNT=$(docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT count() FROM neo4j_cdc.relationship_changes FORMAT TSV")

echo "Node events in ClickHouse: $NODE_COUNT"
echo "Relationship events in ClickHouse: $REL_COUNT"

if [ "$NODE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Node events are being ingested"
else
    echo -e "${YELLOW}⚠${NC} No node events found yet"
fi

if [ "$REL_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Relationship events are being ingested"
else
    echo -e "${YELLOW}⚠${NC} No relationship events found yet"
fi

echo ""

# 5. Check Neo4j data
echo "5. Checking Neo4j data:"
echo "-----------------------"

NEO4J_NODE_COUNT=$(docker exec neo4j-cdc-source cypher-shell -u neo4j -p password123 "MATCH (n) RETURN count(n) AS count" --format plain | tail -1 | tr -d '"')
NEO4J_REL_COUNT=$(docker exec neo4j-cdc-source cypher-shell -u neo4j -p password123 "MATCH ()-[r]->() RETURN count(r) AS count" --format plain | tail -1 | tr -d '"')

echo "Nodes in Neo4j: $NEO4J_NODE_COUNT"
echo "Relationships in Neo4j: $NEO4J_REL_COUNT"

echo ""

# 6. Check ingestion lag
echo "6. Checking ingestion lag:"
echo "--------------------------"

docker exec neo4j-cdc-clickhouse clickhouse-client --query "
SELECT 
    formatReadableTimeDelta(toUInt64(avg(dateDiff('second', event_time, insert_time)))) AS avg_lag,
    formatReadableTimeDelta(toUInt64(max(dateDiff('second', event_time, insert_time)))) AS max_lag,
    count() AS recent_events
FROM neo4j_cdc.node_changes
WHERE insert_time >= now() - INTERVAL 5 MINUTE
FORMAT Pretty
"

echo ""

# 7. Sample data preview
echo "7. Sample data preview:"
echo "-----------------------"

echo "Recent node changes:"
docker exec neo4j-cdc-clickhouse clickhouse-client --query "
SELECT 
    event_time,
    operation,
    labels,
    node_id,
    substring(properties, 1, 50) AS properties_preview
FROM neo4j_cdc.node_changes
ORDER BY event_time DESC
LIMIT 5
FORMAT Pretty
"

echo ""

# 8. Summary
echo "========================================"
echo "Summary"
echo "========================================"

if [ "$NODE_COUNT" -gt 0 ] && [ "$REL_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ CDC pipeline is working!${NC}"
    echo ""
    echo "Access Points:"
    echo "  • Neo4j Browser:   http://localhost:7474"
    echo "  • Kafka UI:        http://localhost:8080"
    echo "  • ClickHouse:      http://localhost:8123"
    echo ""
    echo "Next steps:"
    echo "  • Run: make query (to see analytics)"
    echo "  • Run: make clickhouse-stats (for detailed stats)"
    echo "  • Run: make generate-data (to generate more events)"
else
    echo -e "${YELLOW}⚠ Pipeline is running but no data yet${NC}"
    echo ""
    echo "To generate test data:"
    echo "  make generate-data"
fi

echo ""
