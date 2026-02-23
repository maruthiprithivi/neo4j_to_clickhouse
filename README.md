# Neo4j to ClickHouse CDC Pipeline

A prototype Change Data Capture (CDC) pipeline that streams graph database changes from Neo4j to ClickHouse via Kafka for real-time analytics.

## Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Neo4j     │─────>│   Kafka     │─────>│ ClickHouse  │
│   (Graph)   │ CDC  │  (Broker)   │ Sink │ (Analytics) │
└─────────────┘      └─────────────┘      └─────────────┘
```

## Components

- **Neo4j 5.23**: Source graph database
- **Apache Kafka**: Message broker for event streaming
- **ClickHouse 25.10**: Analytical database for querying changes
- **Python CDC Producer**: Simulates CDC events and populates test data
- **Kafka UI**: Web interface for monitoring Kafka topics

## Quick Start

### 1. Start All Services

```bash
cd neo4j-clickhouse-cdc
docker-compose up -d
```

Wait for all services to be healthy:

```bash
docker-compose ps
```

### 2. Setup ClickHouse Schema

```bash
docker exec neo4j-cdc-clickhouse /sql/setup_clickhouse.sh
```

Or manually run:

```bash
docker exec -it neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/01_create_kafka_tables.sql
docker exec -it neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/02_create_storage_tables.sql
docker exec -it neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/03_create_analytics_views.sql
```

### 3. Generate Sample CDC Events

```bash
docker exec neo4j-cdc-producer python /app/cdc_producer.py
```

This will:
- Create 20 people and 5 companies in Neo4j
- Publish CREATE events to Kafka
- Simulate 10 UPDATE operations
- Simulate 3 DELETE operations

### 4. Verify Data in ClickHouse

Access ClickHouse CLI:

```bash
docker exec -it neo4j-cdc-clickhouse clickhouse-client
```

Run sample queries:

```sql
-- Check total events
SELECT 
    'Nodes' AS type,
    count() AS total_events
FROM neo4j_cdc.node_changes
UNION ALL
SELECT 
    'Relationships' AS type,
    count() AS total_events
FROM neo4j_cdc.relationship_changes;

-- View recent changes
SELECT 
    event_time,
    operation,
    labels,
    node_id,
    JSONExtractString(properties, 'name') AS name
FROM neo4j_cdc.node_changes
ORDER BY event_time DESC
LIMIT 10;

-- Current graph state
SELECT * FROM neo4j_cdc.node_latest_state LIMIT 10;
```

## Access Points

| Service | URL | Credentials |
|---------|-----|-------------|
| Neo4j Browser | http://localhost:7474 | neo4j / password123 |
| Kafka UI | http://localhost:8080 | - |
| ClickHouse HTTP | http://localhost:8123 | default / clickhouse123 |
| ClickHouse Native | localhost:9000 | default / clickhouse123 |

## Kafka Topics

- `neo4j.nodes`: Node CREATE/UPDATE/DELETE events
- `neo4j.relationships`: Relationship CREATE/UPDATE/DELETE events

## ClickHouse Tables

### Source (Kafka Engine)
- `kafka_node_events`: Consumes from `neo4j.nodes`
- `kafka_relationship_events`: Consumes from `neo4j.relationships`

### Storage (MergeTree)
- `node_changes`: Historical log of all node changes
- `relationship_changes`: Historical log of all relationship changes

### Analytics Views
- `node_latest_state`: Current state of each node
- `relationship_latest_state`: Current state of each relationship
- `change_frequency_hourly`: Change patterns over time
- `node_count_by_label`: Node distribution by type
- `relationship_count_by_type`: Relationship distribution

## Project Structure

```
neo4j-clickhouse-cdc/
├── docker-compose.yml          # Docker services configuration
├── DESIGN.md                   # Detailed architecture document
├── README.md                   # This file
├── producer/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── cdc_producer.py         # Python CDC event generator
├── sql/
│   ├── 01_create_kafka_tables.sql
│   ├── 02_create_storage_tables.sql
│   ├── 03_create_analytics_views.sql
│   └── 04_sample_queries.sql
└── scripts/
    └── setup_clickhouse.sh     # Automated setup script
```

## Development Workflow

### Testing CDC Pipeline

1. **Generate events**:
   ```bash
   docker exec neo4j-cdc-producer python /app/cdc_producer.py
   ```

2. **Monitor Kafka topics**:
   - Open http://localhost:8080
   - Navigate to Topics → `neo4j.nodes` or `neo4j.relationships`
   - View messages in real-time

3. **Query ClickHouse**:
   ```bash
   docker exec -it neo4j-cdc-clickhouse clickhouse-client
   ```

4. **Check Neo4j data**:
   - Open http://localhost:7474
   - Run: `MATCH (n) RETURN n LIMIT 25`

### Custom CDC Events

Edit `producer/cdc_producer.py` to customize:
- Event schema
- Data generation patterns
- Update/delete logic

### Scaling Configuration

Edit `docker-compose.yml` to adjust:

**Kafka partitions**:
```bash
docker exec kafka kafka-topics --alter --topic neo4j.nodes --partitions 4 --bootstrap-server localhost:9092
```

**ClickHouse consumers**:
```sql
ALTER TABLE kafka_node_events MODIFY SETTING kafka_num_consumers = 4;
```

## Monitoring

### ClickHouse Ingestion Health

```sql
-- Check consumer lag
SELECT 
    formatReadableTimeDelta(avg(dateDiff('second', event_time, insert_time))) AS avg_lag,
    count() AS events_last_minute
FROM neo4j_cdc.node_changes
WHERE insert_time >= now() - INTERVAL 1 MINUTE;

-- Check ingestion rate
SELECT 
    toStartOfMinute(insert_time) AS minute,
    count() AS events_ingested
FROM neo4j_cdc.node_changes
WHERE insert_time >= now() - INTERVAL 10 MINUTE
GROUP BY minute
ORDER BY minute;
```

### Kafka Metrics

Check http://localhost:8080/ui/clusters/local/consumer-groups

## Production Considerations

### For Production Deployment

1. **Use Neo4j Enterprise CDC**:
   - Replace simulated events with real CDC connector
   - Configure CDC buffer and retention

2. **Kafka Configuration**:
   - Increase replication factor: `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3`
   - Enable compression: `kafka_compression_codec = 'lz4'`
   - Tune partitions based on throughput

3. **ClickHouse Optimization**:
   - Add proper indexes for your query patterns
   - Configure replication for HA
   - Tune `kafka_max_block_size` based on latency requirements
   - Set up proper TTL policies

4. **Security**:
   - Enable SSL/TLS for all connections
   - Configure SASL authentication for Kafka
   - Use secrets management for credentials

5. **Monitoring**:
   - Set up Prometheus + Grafana
   - Monitor consumer lag
   - Alert on ingestion delays

## Troubleshooting

### Kafka Consumer Not Reading

```bash
# Check consumer groups
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --list

# Check consumer lag
docker exec kafka kafka-consumer-groups --bootstrap-server localhost:9092 --group clickhouse_node_consumer --describe
```

### ClickHouse Not Ingesting

```sql
-- Check if materialized views are active
SELECT 
    database,
    name,
    engine,
    dependencies_table
FROM system.tables
WHERE database = 'neo4j_cdc' AND engine = 'MaterializedView';

-- Check for errors
SELECT * FROM system.errors ORDER BY last_error_time DESC LIMIT 10;
```

### Neo4j Connection Issues

```bash
# Check Neo4j logs
docker logs neo4j-cdc-source

# Test connection
docker exec neo4j-cdc-source cypher-shell -u neo4j -p password123 "RETURN 1"
```

## Clean Up

```bash
# Stop all services
docker-compose down

# Remove volumes (deletes all data)
docker-compose down -v
```

## Next Steps

1. Implement Neo4j Kafka Connector for native CDC
2. Add schema evolution handling
3. Implement exactly-once semantics
4. Add data quality checks
5. Create Grafana dashboards
6. Implement CDC replay capabilities

## License

MIT

## Documentation

- [Neo4j Kafka Connector](https://neo4j.com/docs/kafka/current/)
- [ClickHouse Kafka Engine](https://clickhouse.com/docs/engines/table-engines/integrations/kafka)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)

## Support

For issues and questions, refer to:
- Neo4j Community Forum
- ClickHouse Slack
- Kafka Users Mailing List
