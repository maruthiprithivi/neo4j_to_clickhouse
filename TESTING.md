# Testing Guide for Neo4j → ClickHouse CDC Pipeline

This guide walks through testing the entire CDC pipeline from end to end.

## Prerequisites

- Docker and Docker Compose installed
- At least 4GB RAM available
- Ports 7474, 7687, 8080, 8123, 9000, 9092 available

## Quick Test (Automated)

Run the full integration test:

```bash
make test
```

This will:
1. Start all services
2. Setup ClickHouse schema
3. Generate sample data
4. Verify ingestion
5. Display statistics

## Manual Testing Steps

### 1. Start the Pipeline

```bash
# Start all services
make start

# Check service status
make status

# Expected output: all services "Up (healthy)"
```

### 2. Setup ClickHouse

```bash
# Create tables and views
make setup-clickhouse

# Verify tables were created
make shell-clickhouse
```

In ClickHouse shell:
```sql
SHOW TABLES FROM neo4j_cdc;
-- Expected: 6 tables (2 Kafka, 2 MergeTree, 2 MaterializedView)

DESCRIBE neo4j_cdc.node_changes;
-- Should show table schema

EXIT;
```

### 3. Generate Test Data

```bash
# Generate sample CDC events
make generate-data
```

Expected output:
```
=== Creating 20 people and 5 companies ===
✓ Published node event to neo4j.nodes partition 0 offset 0
✓ Published node event to neo4j.nodes partition 0 offset 1
...

=== Creating WORKS_AT relationships ===
...

=== Simulating 10 updates ===
...

=== Simulating 3 deletes ===
...

CDC events published successfully!
```

### 4. Verify Data Flow

#### Check Kafka Topics

```bash
# List topics
make kafka-topics

# Should see:
# neo4j.nodes
# neo4j.relationships

# Consume some messages
make kafka-consume-nodes
```

#### Check ClickHouse Ingestion

```bash
make clickhouse-stats
```

Expected output:
```
┌─type──────────┬─total_events─┬─first_event─────────┬─last_event──────────┬─total_size─┐
│ Nodes         │           33 │ 2024-02-13 05:30:00 │ 2024-02-13 05:31:15 │ 5.23 KiB   │
│ Relationships │           25 │ 2024-02-13 05:30:30 │ 2024-02-13 05:30:55 │ 3.45 KiB   │
└───────────────┴──────────────┴─────────────────────┴─────────────────────┴────────────┘
```

#### Check Neo4j Data

```bash
make neo4j-stats
```

Expected output showing Person and Company node counts.

### 5. Run Verification Script

```bash
./scripts/verify_pipeline.sh
```

This comprehensive script checks:
- Service health
- Kafka topics
- ClickHouse tables
- Data counts
- Ingestion lag
- Sample data

### 6. Test Analytics Queries

```bash
make query
```

Or manually:

```bash
make shell-clickhouse
```

```sql
-- 1. Total events by operation type
SELECT 
    operation,
    count() AS event_count
FROM neo4j_cdc.node_changes
GROUP BY operation;

-- 2. Current graph state
SELECT 
    arrayJoin(labels) AS label,
    count() AS count
FROM neo4j_cdc.node_latest_state
GROUP BY label;

-- 3. Change frequency timeline
SELECT 
    toStartOfMinute(event_time) AS minute,
    count() AS events
FROM neo4j_cdc.node_changes
GROUP BY minute
ORDER BY minute;

-- 4. Most updated nodes
SELECT 
    node_id,
    labels,
    count() AS update_count
FROM neo4j_cdc.node_changes
WHERE operation = 'UPDATE'
GROUP BY node_id, labels
ORDER BY update_count DESC
LIMIT 10;

-- 5. Ingestion lag
SELECT 
    formatReadableTimeDelta(toUInt64(avg(dateDiff('second', event_time, insert_time)))) AS avg_lag,
    formatReadableTimeDelta(toUInt64(max(dateDiff('second', event_time, insert_time)))) AS max_lag
FROM neo4j_cdc.node_changes
WHERE insert_time >= now() - INTERVAL 1 HOUR;
```

### 7. Monitor in Real-Time

#### Kafka UI
Open http://localhost:8080 and:
- Navigate to Topics
- Select `neo4j.nodes` or `neo4j.relationships`
- View messages and consumer groups

#### Neo4j Browser
Open http://localhost:7474 and run:
```cypher
// Show all nodes and relationships
MATCH (n)-[r]->(m)
RETURN n, r, m
LIMIT 50;

// Count by label
MATCH (n)
RETURN labels(n), count(*);
```

## Performance Testing

### Load Test: High Volume Events

Create a load test script:

```python
# In producer container
docker exec -it neo4j-cdc-producer bash

# Edit /app/load_test.py
python << 'EOF'
from cdc_producer import Neo4jCDCProducer
import time

with Neo4jCDCProducer() as producer:
    start = time.time()
    
    # Generate 1000 events
    for i in range(1000):
        event = producer.create_node_event(
            operation='CREATE',
            node_id=f'test_node_{i}',
            labels=['TestNode'],
            properties={'index': i, 'batch': 'load_test'}
        )
        producer.publish_node_event(event)
        
        if i % 100 == 0:
            print(f"Published {i} events...")
    
    elapsed = time.time() - start
    print(f"Throughput: {1000/elapsed:.2f} events/sec")
EOF
```

Then monitor ingestion:

```sql
-- In ClickHouse
SELECT 
    count() AS total,
    max(insert_time) AS last_insert,
    dateDiff('second', min(event_time), max(insert_time)) AS total_lag_seconds
FROM neo4j_cdc.node_changes
WHERE JSONExtractString(properties, 'batch') = 'load_test';
```

### Latency Test

```sql
-- Measure end-to-end latency (event generation to ClickHouse insertion)
SELECT 
    toStartOfMinute(event_time) AS minute,
    avg(dateDiff('millisecond', event_time, insert_time)) AS avg_latency_ms,
    quantile(0.95)(dateDiff('millisecond', event_time, insert_time)) AS p95_latency_ms,
    quantile(0.99)(dateDiff('millisecond', event_time, insert_time)) AS p99_latency_ms
FROM neo4j_cdc.node_changes
WHERE event_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute;
```

## Failure Testing

### Test 1: Kafka Downtime

```bash
# Stop Kafka
docker-compose stop kafka

# Generate events (should fail or queue)
make generate-data

# Start Kafka
docker-compose start kafka

# Events should resume processing
```

### Test 2: ClickHouse Downtime

```bash
# Stop ClickHouse
docker-compose stop clickhouse

# Generate events (Kafka should buffer)
make generate-data

# Start ClickHouse
docker-compose start clickhouse

# Check if events were consumed
make clickhouse-stats
```

### Test 3: Data Loss Simulation

```sql
-- Delete some events
DELETE FROM neo4j_cdc.node_changes
WHERE node_id LIKE 'test_node_%';

-- Verify deletion
SELECT count() FROM neo4j_cdc.node_changes
WHERE node_id LIKE 'test_node_%';
-- Should be 0

-- Events are still in Kafka and can be replayed if needed
```

## Data Quality Checks

Run these queries to verify data quality:

```sql
-- 1. Check for duplicate events
SELECT 
    event_id,
    count() AS duplicates
FROM neo4j_cdc.node_changes
GROUP BY event_id
HAVING duplicates > 1;

-- 2. Check for missing node_ids
SELECT count()
FROM neo4j_cdc.node_changes
WHERE node_id = '' OR node_id IS NULL;

-- 3. Check for invalid JSON in properties
SELECT 
    node_id,
    properties
FROM neo4j_cdc.node_changes
WHERE NOT isValidJSON(properties)
LIMIT 10;

-- 4. Check operation distribution
SELECT 
    operation,
    count() AS count,
    count() * 100.0 / sum(count()) OVER () AS percentage
FROM neo4j_cdc.node_changes
GROUP BY operation;

-- 5. Check for orphaned relationships
SELECT count()
FROM neo4j_cdc.relationship_latest_state r
LEFT JOIN neo4j_cdc.node_latest_state n1 ON r.from_node_id = n1.node_id
LEFT JOIN neo4j_cdc.node_latest_state n2 ON r.to_node_id = n2.node_id
WHERE n1.node_id IS NULL OR n2.node_id IS NULL;
```

## Benchmarking

### Kafka Throughput

```bash
# Producer performance test
docker exec neo4j-cdc-kafka kafka-producer-perf-test \
  --topic neo4j.nodes \
  --num-records 10000 \
  --record-size 500 \
  --throughput -1 \
  --producer-props bootstrap.servers=localhost:9092
```

### ClickHouse Query Performance

```sql
-- Enable query profiling
SET send_logs_level = 'trace';

-- Test query performance
SELECT 
    arrayJoin(labels) AS label,
    count() AS count
FROM neo4j_cdc.node_latest_state
GROUP BY label;

-- Check query stats
SELECT 
    query_duration_ms,
    read_rows,
    read_bytes,
    memory_usage
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 1;
```

## Troubleshooting Tests

### Test Kafka Consumer Lag

```bash
# Check consumer group lag
docker exec neo4j-cdc-kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --group clickhouse_node_consumer \
  --describe
```

### Test ClickHouse Materialized View

```sql
-- Check if materialized view is working
SELECT 
    database,
    name,
    dependencies_database,
    dependencies_table,
    create_table_query
FROM system.tables
WHERE database = 'neo4j_cdc' 
  AND engine = 'MaterializedView';

-- Force refresh (not typically needed)
OPTIMIZE TABLE neo4j_cdc.node_changes FINAL;
```

### Test Neo4j Connection

```bash
# Test Cypher query
docker exec neo4j-cdc-source cypher-shell -u neo4j -p password123 \
  "MATCH (n) RETURN count(n) AS total_nodes"
```

## Expected Results Summary

| Test | Expected Result |
|------|----------------|
| Service Health | All services "Up (healthy)" |
| Kafka Topics | 2 topics created (nodes, relationships) |
| ClickHouse Tables | 6 tables (2 Kafka, 2 MergeTree, 2 views) |
| Data Generation | 20+ nodes, 15+ relationships created |
| Ingestion Lag | < 5 seconds average |
| Query Performance | < 100ms for simple aggregations |
| Data Quality | 0 duplicates, 0 nulls, valid JSON |

## Clean Up After Testing

```bash
# Stop services
make stop

# Remove all data and volumes
make clean

# Verify cleanup
docker-compose ps
# Should show no containers
```

## Continuous Testing

For ongoing development, run:

```bash
# Watch logs in real-time
make logs

# In another terminal, generate events periodically
watch -n 30 'make generate-data'

# In another terminal, monitor stats
watch -n 10 'make clickhouse-stats'
```

## Next Steps

After successful testing:
1. Review DESIGN.md for architecture details
2. Customize event schema for your use case
3. Tune performance parameters
4. Set up monitoring dashboards
5. Plan production deployment
