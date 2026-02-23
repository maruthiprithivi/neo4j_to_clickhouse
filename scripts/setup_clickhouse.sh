#!/bin/bash
set -e

echo "===================================="
echo "Setting up ClickHouse for Neo4j CDC"
echo "===================================="

# Wait for ClickHouse to be ready
echo "Waiting for ClickHouse to start..."
for i in {1..30}; do
    if clickhouse-client --query "SELECT 1" >/dev/null 2>&1; then
        echo "ClickHouse is ready!"
        break
    fi
    echo "Waiting... ($i/30)"
    sleep 2
done

# Run SQL scripts in order
echo ""
echo "Creating Kafka source tables..."
clickhouse-client --multiquery < /sql/01_create_kafka_tables.sql

echo ""
echo "Creating storage tables and materialized views..."
clickhouse-client --multiquery < /sql/02_create_storage_tables.sql

echo ""
echo "Creating analytics views..."
clickhouse-client --multiquery < /sql/03_create_analytics_views.sql

echo ""
echo "===================================="
echo "ClickHouse setup complete!"
echo "===================================="
