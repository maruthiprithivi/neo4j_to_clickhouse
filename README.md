# Neo4j to ClickHouse CDC System

Production-ready Change Data Capture (CDC) from Neo4j to ClickHouse using Kafka and native Neo4j APOC triggers.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture](#architecture)
3. [Project Structure](#project-structure)
4. [Setup and Installation](#setup-and-installation)
5. [Initial Load (Historical Data)](#initial-load-historical-data)
6. [Real-time CDC](#real-time-cdc)
7. [Testing](#testing)
8. [Monitoring and Validation](#monitoring-and-validation)
9. [Production Deployment](#production-deployment)
10. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- Docker and Docker Compose
- Python 3.8+
- 8GB RAM minimum
- 20GB disk space

### Start the System

```bash
# 1. Clone the repository
git clone <repo-url>
cd neo4j-clickhouse-cdc_final

# 2. Set up environment
cp .env.example .env
# Edit .env if needed (defaults work for local development)

# 3. Start all services
docker-compose up -d

# 4. Wait for services to be ready (~60 seconds)
docker-compose ps

# 5. Install Neo4j triggers
make install-triggers

# 6. Run test scenarios
cd test-scenarios
pip3 install -r requirements.txt
python3 run_tests.py

# 7. Verify data in ClickHouse
make verify-clickhouse
```

Done. You now have a working CDC pipeline.

For the condensed version, see [docs/QUICKSTART.md](docs/QUICKSTART.md).

---

## Architecture

### High-Level Flow

```
+-----------+         +---------------+         +---------+         +--------------+
|   Neo4j   | --HTTP->|  CDC Bridge   | --Kafka->|  Kafka  | --Kafka->|  ClickHouse  |
|  (APOC)   |         |   (Python)    |         |         |         |    (25.10)   |
+-----------+         +---------------+         +---------+         +--------------+
  Triggers              Flask Service            Message             Kafka Table
                                                 Broker              Engine
```

### Components

1. **Neo4j (7474, 7687)**: Graph database with APOC triggers
2. **CDC Bridge (8000)**: Python Flask service that receives events from Neo4j and publishes to Kafka
3. **Kafka + Zookeeper (9092)**: Message broker for reliable event streaming
4. **ClickHouse (8123, 9000)**: OLAP database with Kafka table engine for real-time ingestion

### Event Flow

1. **Change occurs** in Neo4j (INSERT/UPDATE/DELETE)
2. **APOC trigger fires** and sends HTTP POST to CDC Bridge
3. **CDC Bridge** validates and publishes event to Kafka topic
4. **Kafka** stores event reliably with replication
5. **ClickHouse** consumes from Kafka via Kafka table engine
6. **Materialized view** transforms and stores in final table

---

## Project Structure

```
neo4j-clickhouse-cdc_final/
├── docker-compose.yml              # Docker services configuration
├── .env.example                    # Environment variable template
├── Makefile                        # Common commands
├── README.md                       # This file
│
├── docs/                           # Supplementary documentation
│   ├── QUICKSTART.md               # Condensed quick start guide
│   └── ISSUES-AND-FIXES.md        # Issues log from development
│
├── cdc-bridge/                     # Python CDC bridge service
│   ├── Dockerfile
│   ├── main.py                     # Flask app
│   └── requirements.txt
│
├── neo4j/                          # Neo4j configuration
│   ├── install-triggers.cypher     # Install APOC triggers
│   └── remove-triggers.cypher      # Remove triggers
│
├── clickhouse/                     # ClickHouse configuration
│   ├── config/
│   │   └── config.xml              # ClickHouse settings
│   └── init/
│       └── 01-init-tables.sql      # Table schemas
│
├── initial-load/                   # Historical data migration
│   ├── requirements.txt
│   ├── scripts/
│   │   ├── 01-export-nodes.cypher         # Export nodes from Neo4j
│   │   ├── 02-export-relationships.cypher # Export relationships
│   │   ├── 03-bulk-import.py              # Import to ClickHouse
│   │   └── 04-optimize-tables.sql         # Optimize and validate
│   └── staging/                    # CSV export staging area
│       ├── nodes/
│       └── relationships/
│
└── test-scenarios/                 # Test cases
    ├── 01-node-insert.cypher
    ├── 02-node-update.cypher
    ├── 03-node-delete.cypher
    ├── 04-relationship-insert.cypher
    ├── 05-relationship-update.cypher
    ├── 06-relationship-delete.cypher
    ├── 07-bulk-operations.cypher
    ├── run_tests.py                # Automated test runner
    └── requirements.txt
```

---

## Setup and Installation

### Step 1: Configure Environment

Copy the example environment file and adjust if needed:

```bash
cp .env.example .env
```

The defaults work for local development. See `.env.example` for all available options.

### Step 2: Start Services

```bash
# Start all containers
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

**Expected output**:
```
NAME                STATUS              PORTS
neo4j               Up 30 seconds       0.0.0.0:7474->7474/tcp, 0.0.0.0:7687->7687/tcp
kafka               Up 30 seconds       0.0.0.0:9092->9092/tcp
zookeeper           Up 30 seconds       2181/tcp
clickhouse          Up 30 seconds       0.0.0.0:8123->8123/tcp, 0.0.0.0:9000->9000/tcp
cdc-bridge          Up 30 seconds       0.0.0.0:8000->8000/tcp
```

### Step 3: Verify Services

```bash
# Neo4j
curl http://localhost:7474

# ClickHouse
curl http://localhost:8123/ping

# CDC Bridge
curl http://localhost:8000/health

# Kafka
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092
```

### Step 4: Install Neo4j Triggers

```bash
# Using Makefile
make install-triggers

# OR manually
docker exec -i neo4j-cdc-neo4j cypher-shell -u neo4j -p password123 -d system < neo4j/install-triggers.cypher
```

**Verify triggers installed**:

```cypher
// In Neo4j Browser (http://localhost:7474)
CALL apoc.trigger.list();
```

You should see 6 triggers:
- `cdc_node_created`
- `cdc_node_updated`
- `cdc_node_deleted`
- `cdc_relationship_created`
- `cdc_relationship_updated`
- `cdc_relationship_deleted`

---

## Initial Load (Historical Data)

Use this to migrate existing data from Neo4j to ClickHouse BEFORE starting real-time CDC.

### Overview

The "Snapshot + Catchup" strategy:

1. Start CDC consumers (buffer events)
2. Export Neo4j snapshot to CSV
3. Bulk import CSV to ClickHouse
4. Optimize tables (deduplication)
5. Process buffered CDC events
6. Validate

### Step-by-Step

#### 1. Enable CDC Buffering

```bash
# Increase Kafka retention to 7 days (default is 24h)
docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics \
  --entity-name neo4j-node-events \
  --alter --add-config retention.ms=604800000

docker exec kafka kafka-configs.sh \
  --bootstrap-server localhost:9092 \
  --entity-type topics \
  --entity-name neo4j-relationship-events \
  --alter --add-config retention.ms=604800000
```

#### 2. Export from Neo4j

```bash
# Copy export scripts to Neo4j container
docker cp initial-load/scripts/01-export-nodes.cypher neo4j:/tmp/
docker cp initial-load/scripts/02-export-relationships.cypher neo4j:/tmp/

# Create staging directory in Neo4j
docker exec neo4j mkdir -p /staging/nodes /staging/relationships
docker exec neo4j chmod 777 /staging/nodes /staging/relationships

# Run exports
docker exec neo4j cypher-shell -u neo4j -p password123 -f /tmp/01-export-nodes.cypher
docker exec neo4j cypher-shell -u neo4j -p password123 -f /tmp/02-export-relationships.cypher

# Copy exports to host
docker cp neo4j:/staging/nodes/. ./initial-load/staging/nodes/
docker cp neo4j:/staging/relationships/. ./initial-load/staging/relationships/

# Verify exports
ls -lh initial-load/staging/nodes/
ls -lh initial-load/staging/relationships/
```

#### 3. Import to ClickHouse

```bash
cd initial-load

# Install Python dependencies
pip3 install -r requirements.txt

# Run bulk import
python3 scripts/03-bulk-import.py --all --validate
```

#### 4. Optimize Tables

```bash
# Run optimization
docker exec -i clickhouse clickhouse-client --multiquery < initial-load/scripts/04-optimize-tables.sql
```

This will:
- Merge table parts
- Apply deduplication
- Validate data consistency

#### 5. Verify

```bash
# Check row counts
docker exec clickhouse clickhouse-client --query="
  SELECT 'Nodes' as type, count(*) as count FROM cdc.nodes_cdc
  UNION ALL
  SELECT 'Relationships', count(*) FROM cdc.relationships_cdc
"
```

Compare with Neo4j:

```cypher
// In Neo4j Browser
MATCH (n) RETURN count(*);
MATCH ()-[r]->() RETURN count(*);
```

Counts should match.

---

## Real-time CDC

Once initial load is complete, the system automatically captures real-time changes.

### How It Works

1. **Create/Update/Delete** a node or relationship in Neo4j
2. **APOC trigger** fires immediately
3. **CDC Bridge** receives HTTP POST
4. **Kafka** stores event
5. **ClickHouse** consumes and stores in < 2 seconds

### Test Real-time CDC

```bash
# Create a node in Neo4j
docker exec neo4j cypher-shell -u neo4j -p password123 \
  "CREATE (n:Device {name: 'Router-01', ip: '192.168.1.1'})"

# Wait 2 seconds
sleep 2

# Check ClickHouse
docker exec clickhouse clickhouse-client --query="
  SELECT * FROM cdc.nodes_cdc
  WHERE has(labels, 'Device')
    AND JSONExtractString(properties_after, 'name') = 'Router-01'
  ORDER BY event_timestamp DESC
  LIMIT 1
"
```

You should see the event with `event_type = 'INSERT'`.

---

## Testing

### Automated Test Suite

```bash
cd test-scenarios

# Install dependencies
pip3 install -r requirements.txt

# Run all tests
python3 run_tests.py
```

**Tests include**:
1. Node INSERT
2. Node UPDATE
3. Node DELETE
4. Relationship INSERT
5. Relationship UPDATE
6. Relationship DELETE
7. Bulk operations (100+ records)

### Manual Testing

```bash
# Run individual test
docker exec -i neo4j cypher-shell -u neo4j -p password123 < test-scenarios/01-node-insert.cypher

# Verify in ClickHouse
make verify-clickhouse
```

---

## Monitoring and Validation

### Check Service Health

```bash
# All services
make health

# Individual services
curl http://localhost:8000/health    # CDC Bridge
curl http://localhost:8123/ping      # ClickHouse
curl http://localhost:7474           # Neo4j
```

### Check Kafka Lag

```bash
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group clickhouse-consumers \
  --describe
```

**Target**: LAG should be 0 or very low (< 100).

### Check ClickHouse Data

```bash
# Using Makefile
make verify-clickhouse

# OR manually
docker exec clickhouse clickhouse-client --query="
  SELECT
    event_type,
    count(*) as count
  FROM cdc.nodes_cdc
  GROUP BY event_type
  ORDER BY count DESC
"
```

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f cdc-bridge
docker-compose logs -f clickhouse
docker-compose logs -f neo4j
```

---

## Production Deployment

### Scaling Recommendations

| Dataset Size | Neo4j | ClickHouse | Kafka | CDC Bridge |
|--------------|-------|------------|-------|------------|
| < 10M records | 4 vCPU, 16GB | 8 vCPU, 32GB | 2 vCPU, 4GB | 2 vCPU, 4GB |
| 10M - 100M | 8 vCPU, 32GB | 16 vCPU, 64GB | 4 vCPU, 8GB | 4 vCPU, 8GB |
| > 100M | 16 vCPU, 64GB | 32 vCPU, 128GB | 8 vCPU, 16GB | 8 vCPU, 16GB |

### Production Checklist

- [ ] Enable TLS/SSL for all services
- [ ] Configure authentication (Neo4j, ClickHouse, Kafka)
- [ ] Set up monitoring (Prometheus + Grafana)
- [ ] Configure backups (Neo4j, ClickHouse)
- [ ] Enable Kafka replication (3 replicas minimum)
- [ ] Set up alerting (Kafka lag, service health)
- [ ] Configure log aggregation (ELK stack)
- [ ] Enable ClickHouse replication and sharding
- [ ] Set up disaster recovery plan
- [ ] Document runbooks and escalation procedures

### High Availability

For production, deploy:

- **Neo4j Cluster**: 3+ nodes with causal clustering
- **ClickHouse Cluster**: 3+ nodes with sharding and replication
- **Kafka Cluster**: 3+ brokers with replication factor 3
- **CDC Bridge**: 2+ instances behind load balancer

---

## Troubleshooting

For a comprehensive list of issues encountered during development and their fixes, see [docs/ISSUES-AND-FIXES.md](docs/ISSUES-AND-FIXES.md).

### Issue: "Neo4j triggers not firing"

**Solution**:

```bash
# Check APOC is installed
docker exec neo4j cypher-shell -u neo4j -p password123 "CALL apoc.help('trigger')"

# Reinstall triggers
make install-triggers

# Verify
docker exec neo4j cypher-shell -u neo4j -p password123 "CALL apoc.trigger.list()"
```

Note: After modifying triggers, a Neo4j restart is required to clear the trigger cache. See [docs/ISSUES-AND-FIXES.md](docs/ISSUES-AND-FIXES.md) Issue 4 for details.

### Issue: "CDC Bridge connection refused"

**Solution**:

```bash
# Check CDC Bridge is running
docker-compose ps cdc-bridge

# Check logs
docker-compose logs cdc-bridge

# Restart
docker-compose restart cdc-bridge
```

### Issue: "Kafka lag increasing"

**Solution**:

```bash
# Check consumer group lag
docker exec kafka kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group clickhouse_nodes_consumer \
  --describe

# Restart ClickHouse to reset consumers
docker-compose restart clickhouse
```

### Issue: "ClickHouse not consuming from Kafka"

**Solution**:

```bash
# Check Kafka table engine
docker exec clickhouse clickhouse-client --query="
  SELECT * FROM system.kafka_consumers
"

# Check for errors
docker exec clickhouse clickhouse-client --query="
  SELECT * FROM system.errors WHERE name LIKE '%Kafka%'
"

# Restart ClickHouse
docker-compose restart clickhouse
```

### Issue: "Out of disk space"

**Solution**:

```bash
# Check disk usage
docker exec clickhouse clickhouse-client --query="
  SELECT
    formatReadableSize(sum(bytes)) as size
  FROM system.parts
  WHERE active = 1
"

# Clean old data
docker exec clickhouse clickhouse-client --query="
  ALTER TABLE cdc.nodes_cdc DELETE WHERE event_timestamp < now() - INTERVAL 90 DAY
"

# Optimize
docker exec clickhouse clickhouse-client --query="OPTIMIZE TABLE cdc.nodes_cdc FINAL"
```

---

## Useful Commands (Makefile)

```bash
make start              # Start all services
make stop               # Stop all services
make restart            # Restart all services
make logs               # View all logs
make health             # Check service health
make install-triggers   # Install Neo4j triggers
make remove-triggers    # Remove Neo4j triggers
make test               # Run test scenarios
make verify-clickhouse  # Check ClickHouse data
make clean              # Remove all containers and volumes
```

### Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Neo4j Browser | http://localhost:7474 | neo4j/password123 |
| ClickHouse HTTP | http://localhost:8123 | default/(empty) |
| CDC Bridge Health | http://localhost:8000/health | - |
| CDC Bridge Metrics | http://localhost:8000/metrics | - |

---

## Data Schema

### Node Events Table (`cdc.nodes_cdc`)

```sql
CREATE TABLE nodes_cdc (
    event_id String,
    event_type Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3),
    event_timestamp DateTime64(3),
    entity_id String,
    labels Array(String),
    properties_before String,       -- JSON (for UPDATE/DELETE)
    properties_after String,        -- JSON (for INSERT/UPDATE)
    metadata String                 -- JSON (source, timestamp, etc.)
) ENGINE = MergeTree()
ORDER BY (event_timestamp, event_id)
PARTITION BY toYYYYMM(event_timestamp);
```

### Relationship Events Table (`cdc.relationships_cdc`)

```sql
CREATE TABLE relationships_cdc (
    event_id String,
    event_type Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3),
    event_timestamp DateTime64(3),
    entity_id String,
    relationship_type String,
    source_id String,
    target_id String,
    properties_before String,
    properties_after String,
    metadata String
) ENGINE = MergeTree()
ORDER BY (event_timestamp, event_id)
PARTITION BY toYYYYMM(event_timestamp);
```

Events are consumed from Kafka via Kafka engine tables (`nodes_kafka_queue`, `relationships_kafka_queue`) and materialized views that transform and insert into the final tables above.

---

## Key Concepts

### MergeTree Engine

ClickHouse's **MergeTree** engine family provides efficient columnar storage with automatic background merges. Data is partitioned by month (`toYYYYMM`) for efficient time-range queries and ordered by `(event_timestamp, event_id)` for fast lookups.

### APOC Triggers

Neo4j **APOC triggers** fire on database events:

- **afterAsync**: Runs after transaction commits (non-blocking)
- **HTTP POST**: Sends event to CDC Bridge
- Triggers must be installed against the `system` database in Neo4j 5.x

### Kafka as Buffer

Kafka provides:

- **Durability**: Events persisted to disk
- **Replay**: Can reprocess from any offset
- **Scalability**: Partitioning for parallelism
- **Decoupling**: Neo4j and ClickHouse independent

---

## License

This project is provided as-is for educational and commercial use.

---

## Quick Reference

### Start System
```bash
docker-compose up -d
make install-triggers
```

### Run Tests
```bash
cd test-scenarios && python3 run_tests.py
```

### Check Data
```bash
make verify-clickhouse
```

### Stop System
```bash
docker-compose down
```

### Clean Everything
```bash
make clean
```
