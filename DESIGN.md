# Neo4j to ClickHouse CDC Pipeline Design

## Overview

This prototype implements Change Data Capture (CDC) from Neo4j to ClickHouse using Kafka as the message broker. The system captures graph database changes in real-time and streams them to a columnar analytical database.

## Architecture

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Neo4j     │─────>│   Kafka     │─────>│ ClickHouse  │
│   (Graph)   │ CDC  │  (Broker)   │ Sink │ (Analytics) │
└─────────────┘      └─────────────┘      └─────────────┘
```

### Components

1. **Neo4j 5.x** (with Enterprise Edition CDC support)
   - Source database with graph data
   - APOC triggers for custom CDC logic (fallback)
   - Neo4j Kafka Connector (Source) for native CDC

2. **Apache Kafka**
   - Message broker for event streaming
   - Topics for different entity types (nodes, relationships)
   - Persistent event log

3. **ClickHouse 25.10**
   - Analytical database for querying changes
   - Kafka table engine for consuming events
   - Materialized views for transforming data

## Data Flow

### Using Neo4j Native CDC (Preferred)

1. **Capture**: Neo4j CDC detects changes (CREATE, UPDATE, DELETE)
2. **Transform**: Kafka Connector serializes to JSON
3. **Stream**: Events published to Kafka topics
4. **Consume**: ClickHouse Kafka engine reads events
5. **Materialize**: Events transformed and stored in MergeTree tables

### CDC Event Schema

Neo4j CDC produces events in this format:

```json
{
  "id": "unique-event-id",
  "txId": 12345,
  "seq": 1,
  "metadata": {
    "executingUser": "neo4j",
    "serverId": "server-1",
    "captureMode": "FULL"
  },
  "event": {
    "eventType": "n",  // n=node, r=relationship
    "operation": "c",  // c=create, u=update, d=delete
    "labels": ["Person"],
    "keys": {
      "id": "123"
    },
    "before": null,
    "after": {
      "properties": {
        "name": "John Doe",
        "age": 30
      }
    }
  }
}
```

### Alternative: APOC Triggers

For Community Edition or custom logic:

```cypher
CALL apoc.trigger.install(
  'neo4j',
  'cdc_nodes',
  'UNWIND $createdNodes AS node
   CALL apoc.kafka.produce(
     "neo4j-nodes",
     node.id,
     {
       operation: "CREATE",
       labels: labels(node),
       properties: properties(node),
       timestamp: timestamp()
     }
   ) YIELD value
   RETURN value',
  {phase: 'after'}
)
```

## ClickHouse Schema

### Kafka Source Tables

```sql
-- Raw events from Kafka
CREATE TABLE kafka_neo4j_events (
    event_id String,
    tx_id UInt64,
    event_type String,  -- 'node' or 'relationship'
    operation String,   -- 'create', 'update', 'delete'
    labels Array(String),
    entity_id String,
    properties String,  -- JSON string
    timestamp DateTime64(3)
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'neo4j-cdc',
    kafka_group_name = 'clickhouse-consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 2;
```

### Storage Tables

```sql
-- Nodes changes log
CREATE TABLE node_changes (
    event_id String,
    tx_id UInt64,
    operation String,
    labels Array(String),
    node_id String,
    properties String,
    event_time DateTime64(3),
    insert_time DateTime DEFAULT now()
) ENGINE = MergeTree()
ORDER BY (event_time, tx_id, node_id);

-- Materialized view to transform and store
CREATE MATERIALIZED VIEW node_changes_mv TO node_changes AS
SELECT
    event_id,
    tx_id,
    operation,
    labels,
    entity_id AS node_id,
    properties,
    timestamp AS event_time
FROM kafka_neo4j_events
WHERE event_type = 'node';
```

## Deployment Strategy

### Docker Compose Setup

```yaml
services:
  neo4j:
    image: neo4j:5.23-enterprise
    environment:
      - NEO4J_ACCEPT_LICENSE_AGREEMENT=yes
      - db.cdc.enabled=true
  
  kafka:
    image: confluentinc/cp-kafka:7.6.0
    
  clickhouse:
    image: clickhouse/clickhouse-server:25.10
```

## Implementation Options

### Option 1: Native CDC (Requires Enterprise)
- **Pros**: Official support, comprehensive event capture, minimal overhead
- **Cons**: Requires Neo4j Enterprise license, complex setup
- **Best for**: Production deployments, full audit trail

### Option 2: APOC Triggers + Kafka Producer
- **Pros**: Works with Community Edition, flexible custom logic
- **Cons**: Manual trigger management, potential performance impact
- **Best for**: Prototyping, selective CDC, custom transformations

### Option 3: Hybrid Approach
- Use Neo4j Streams (older plugin) for simpler setup
- Falls back to polling for CDC in Community Edition

## Performance Considerations

1. **Kafka Partitioning**: Partition by entity type or ID for parallel consumption
2. **ClickHouse Batch Size**: Tune `kafka_max_block_size` for throughput vs latency
3. **Neo4j CDC Buffer**: Configure CDC buffer size to handle bursts
4. **Materialized Views**: Create indexes based on query patterns

## Monitoring

Key metrics to track:
- Neo4j: Transaction rate, CDC queue depth
- Kafka: Consumer lag, message throughput
- ClickHouse: Ingestion rate, table sizes, query performance

## Prototype Scope

This prototype will implement:
1. ✅ Docker Compose with all services
2. ✅ Neo4j with APOC triggers (Community Edition compatible)
3. ✅ Kafka topic configuration
4. ✅ Python script to produce test events
5. ✅ ClickHouse Kafka engine and materialized views
6. ✅ Sample queries to verify CDC pipeline
7. ✅ Monitoring dashboard (optional)

## Next Steps for Production

1. Implement Neo4j Enterprise CDC (if available)
2. Add schema evolution handling
3. Implement exactly-once semantics
4. Add dead letter queue for failed events
5. Set up monitoring and alerting
6. Add data quality checks
7. Implement CDC replay/reset capabilities
