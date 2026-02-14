# Quick Start Guide - Neo4j to ClickHouse CDC

## 5-Minute Setup

### 1. Clone and Navigate
```bash
git clone <repo-url>
cd neo4j-clickhouse-cdc_final
```

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env with your credentials if needed (defaults work for local dev)
```

### 3. Start All Services
```bash
docker-compose up -d
```

Wait 60 seconds for services to start.

### 4. Install Neo4j Triggers
```bash
make install-triggers
```

### 5. Test the System
```bash
cd test-scenarios
pip3 install -r requirements.txt
python3 run_tests.py
```

### 6. Verify Data in ClickHouse
```bash
make verify-clickhouse
```

Done. Your CDC system is running.

---

## Essential Commands

### Service Management
```bash
docker-compose up -d        # Start all services
docker-compose ps           # Check status
docker-compose logs -f      # View logs
docker-compose down         # Stop all services
```

### Health Checks
```bash
make health                 # Check all services
curl http://localhost:7474  # Neo4j
curl http://localhost:8123/ping  # ClickHouse
curl http://localhost:8000/health  # CDC Bridge
```

### Data Operations
```bash
make verify-clickhouse      # Check ClickHouse data
make install-triggers       # Install Neo4j triggers
make remove-triggers        # Remove triggers
make test                   # Run test scenarios
```

---

## What's Next?

### For Testing
1. Open Neo4j Browser: http://localhost:7474 (neo4j/password123)
2. Create some data:
   ```cypher
   CREATE (d:Device {name: 'Router-01', ip: '192.168.1.1'})
   ```
3. Wait 2 seconds
4. Check ClickHouse:
   ```bash
   docker exec clickhouse clickhouse-client --query="SELECT * FROM cdc.nodes_cdc ORDER BY event_timestamp DESC LIMIT 5"
   ```

### For Initial Load (Historical Data)
1. Read: `initial-load/scripts/` directory
2. Follow: Steps in main README.md under "Initial Load"
3. Run: Export -> Import -> Optimize -> Validate

### For Production
1. Read: "Production Deployment" section in README.md
2. Configure: Authentication, TLS, monitoring
3. Scale: Adjust resources based on data volume
4. Monitor: Set up Prometheus + Grafana

---

## Common Issues

### "Connection refused" errors
```bash
# Wait for services to fully start
docker-compose ps
# All should show "Up" status
```

### "Triggers not firing"
```bash
# Reinstall triggers
make remove-triggers
make install-triggers

# Verify
docker exec neo4j cypher-shell -u neo4j -p password123 "CALL apoc.trigger.list()"
```

### "No data in ClickHouse"
```bash
# Check Kafka topics
docker exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Check CDC Bridge logs
docker-compose logs cdc-bridge

# Check ClickHouse logs
docker-compose logs clickhouse
```

---

## Service URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Neo4j Browser | http://localhost:7474 | neo4j/password123 |
| ClickHouse HTTP | http://localhost:8123 | default/(empty) |
| CDC Bridge Health | http://localhost:8000/health | - |
| CDC Bridge Metrics | http://localhost:8000/metrics | - |

---

## Key Files

| File | Purpose |
|------|---------|
| `README.md` | Complete documentation |
| `docker-compose.yml` | Service definitions |
| `.env` | Environment variables |
| `Makefile` | Common commands |
| `neo4j/install-triggers.cypher` | Install CDC triggers |
| `clickhouse/init/01-init-tables.sql` | Table schemas |
| `cdc-bridge/main.py` | CDC bridge service |
| `initial-load/scripts/` | Historical data migration |
| `test-scenarios/` | Test cases |

---

## Architecture Overview

```
Neo4j (Graph DB)
    | APOC Triggers (HTTP POST)
CDC Bridge (Python Flask)
    | Kafka Protocol
Kafka (Message Broker)
    | Kafka Table Engine
ClickHouse (OLAP DB)
```

**Event Types**: INSERT, UPDATE, DELETE

**Latency**: < 2 seconds end-to-end

**Throughput**: 10K+ ops/sec (single instance)

---

## Success Checklist

- [ ] All services running (`docker-compose ps`)
- [ ] Triggers installed (`CALL apoc.trigger.list()`)
- [ ] Test scenarios pass (`python3 run_tests.py`)
- [ ] Data visible in ClickHouse (`make verify-clickhouse`)
- [ ] Kafka lag is low (< 100)

---

Need help? See full README.md for detailed documentation.
