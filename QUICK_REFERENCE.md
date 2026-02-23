# Quick Reference Card

## One-Line Commands

```bash
# Start everything
make test

# Just start services
make start

# Generate test data
make generate-data

# View statistics
make clickhouse-stats

# Run queries
make query

# Clean everything
make clean
```

## Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Neo4j Browser | http://localhost:7474 | neo4j / password123 |
| Kafka UI | http://localhost:8080 | - |
| ClickHouse HTTP | http://localhost:8123 | default / clickhouse123 |

## Common Queries

### ClickHouse CLI
```bash
docker exec -it neo4j-cdc-clickhouse clickhouse-client
```

### Check Data Counts
```sql
SELECT count() FROM neo4j_cdc.node_changes;
SELECT count() FROM neo4j_cdc.relationship_changes;
```

### View Recent Changes
```sql
SELECT * FROM neo4j_cdc.node_changes 
ORDER BY event_time DESC 
LIMIT 10;
```

### Current Graph State
```sql
SELECT * FROM neo4j_cdc.node_latest_state LIMIT 10;
SELECT * FROM neo4j_cdc.relationship_latest_state LIMIT 10;
```

### Ingestion Lag
```sql
SELECT 
    formatReadableTimeDelta(toUInt64(avg(dateDiff('second', event_time, insert_time)))) AS lag
FROM neo4j_cdc.node_changes
WHERE insert_time >= now() - INTERVAL 1 MINUTE;
```

## Kafka Topics

```bash
# List topics
docker exec neo4j-cdc-kafka kafka-topics --list --bootstrap-server localhost:9092

# Consume messages
docker exec neo4j-cdc-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic neo4j.nodes \
  --from-beginning \
  --max-messages 5
```

## Neo4j Cypher

```bash
# Open Cypher shell
docker exec -it neo4j-cdc-source cypher-shell -u neo4j -p password123
```

```cypher
// Count nodes
MATCH (n) RETURN labels(n), count(*);

// View graph
MATCH (n)-[r]->(m) RETURN n, r, m LIMIT 25;

// Clear all data
MATCH (n) DETACH DELETE n;
```

## Troubleshooting

### Services not starting
```bash
docker-compose logs <service-name>
docker-compose restart <service-name>
```

### Clear and restart
```bash
make clean
make start
make setup-clickhouse
make generate-data
```

### Check service health
```bash
./scripts/verify_pipeline.sh
```

## File Locations

- SQL scripts: `./sql/`
- Producer code: `./producer/cdc_producer.py`
- Setup scripts: `./scripts/`
- Documentation: `./README.md`, `./DESIGN.md`, `./TESTING.md`

## Event Schema

### Node Event
```json
{
  "event_id": "uuid",
  "tx_id": 123,
  "operation": "CREATE|UPDATE|DELETE",
  "labels": ["Person"],
  "node_id": "person_1",
  "properties": "{\"name\":\"John\"}",
  "timestamp": "2024-02-13T05:30:00Z"
}
```

### Relationship Event
```json
{
  "event_id": "uuid",
  "tx_id": 124,
  "operation": "CREATE|UPDATE|DELETE",
  "rel_type": "KNOWS",
  "rel_id": "rel_1",
  "from_node_id": "person_1",
  "to_node_id": "person_2",
  "properties": "{\"since\":\"2020-01-01\"}",
  "timestamp": "2024-02-13T05:30:01Z"
}
```

## Performance Tuning

### Kafka
```yaml
# docker-compose.yml
KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3  # Production
KAFKA_COMPRESSION_TYPE: lz4                 # Better compression
```

### ClickHouse
```sql
-- Increase consumers
ALTER TABLE kafka_node_events 
MODIFY SETTING kafka_num_consumers = 4;

-- Adjust batch size
ALTER TABLE kafka_node_events 
MODIFY SETTING kafka_max_block_size = 10000;
```

## Next Steps Checklist

- [ ] Run `make test` successfully
- [ ] Explore Kafka UI
- [ ] Run sample queries in ClickHouse
- [ ] View graph in Neo4j Browser
- [ ] Read DESIGN.md for architecture
- [ ] Read TESTING.md for advanced testing
- [ ] Customize for your use case
- [ ] Plan production deployment

## Support

- **Documentation**: README.md, DESIGN.md, TESTING.md
- **Health Check**: `./scripts/verify_pipeline.sh`
- **Logs**: `make logs`
- **Status**: `make status`
