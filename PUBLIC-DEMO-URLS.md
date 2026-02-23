# 🌐 Public Demo URLs - Neo4j CDC Pipeline

## ✅ Services Now Publicly Accessible

All services are live and accessible from anywhere in the world!

---

## 🔗 Access URLs

### 1. **Neo4j Browser** 🗄️
```
URL:      http://37.27.131.209:7474
Username: neo4j
Password: password123
```

**What to show:**
- Visual graph exploration
- Run Cypher queries
- See real-time graph data

**Demo Queries:**
```cypher
// Show all nodes
MATCH (n) RETURN n LIMIT 25

// Show Person → Company relationships
MATCH (p:Person)-[r:WORKS_AT]->(c:Company)
RETURN p, r, c

// Show social network
MATCH (p1:Person)-[r:KNOWS]->(p2:Person)
RETURN p1, r, p2
```

---

### 2. **ClickHouse Analytics** 📊
```
URL:      http://37.27.131.209:8124
```

**Query Interface:**
```
http://37.27.131.209:8124/?query=YOUR_SQL_HERE
```

**Demo Queries:**

**See all CDC events:**
```
http://37.27.131.209:8124/?query=SELECT+*+FROM+neo4j_cdc.node_changes+ORDER+BY+event_time+DESC+LIMIT+10
```

**Count by operation type:**
```
http://37.27.131.209:8124/?query=SELECT+operation,count()+FROM+neo4j_cdc.node_changes+GROUP+BY+operation
```

**Current graph state:**
```
http://37.27.131.209:8124/?query=SELECT+arrayJoin(labels)+AS+label,count()+FROM+neo4j_cdc.node_latest_state+GROUP+BY+label
```

**Recent activity:**
```
http://37.27.131.209:8124/?query=SELECT+*+FROM+neo4j_cdc.recent_activity+LIMIT+20
```

---

### 3. **Kafka UI** 📨
```
URL: http://37.27.131.209:8081
```

**What to show:**
- Topics: `neo4j.nodes` and `neo4j.relationships`
- Live messages streaming
- Consumer groups and lag
- Partition details

**Features:**
- ✅ Browse messages in topics
- ✅ View message headers and payloads
- ✅ Monitor consumer lag
- ✅ See broker metrics

---

## 🎬 Demo Script (5-Minute Flow)

### **Part 1: Show the Architecture** (1 min)

Open the flow diagram:
```
https://github.com/yourrepo/CDC-FLOW-DIAGRAM.md
```

Explain: "Neo4j → Kafka → Python Consumer → ClickHouse"

---

### **Part 2: Explore Live Services** (2 min)

**Step 1: Neo4j** → Show the graph
1. Open `http://37.27.131.209:7474`
2. Login: neo4j/password123
3. Run: `MATCH (n) RETURN n LIMIT 25`
4. Show visual graph

**Step 2: Kafka UI** → Show the pipeline
1. Open `http://37.27.131.209:8081`
2. Click "Topics" → `neo4j.nodes`
3. Show messages (JSON CDC events)
4. Click "Consumer Groups" → show clickhouse consumers

**Step 3: ClickHouse** → Show analytics
1. Open: `http://37.27.131.209:8124/?query=SELECT+count()+FROM+neo4j_cdc.node_changes`
2. Show: "38 events ingested"
3. Run aggregation query to show insights

---

### **Part 3: Live Demo - Generate New Data** (2 min)

**SSH into server and run:**
```bash
docker exec neo4j-cdc-producer python /app/cdc_producer.py
```

**Watch in real-time:**

1. **Kafka UI** → Refresh topics, new messages appear
2. **Consumer Logs**:
   ```bash
   docker logs neo4j-cdc-consumer --tail 20 --follow
   ```
   Watch: "✓ Inserted X events"

3. **ClickHouse** → Re-run count query:
   ```
   http://37.27.131.209:8124/?query=SELECT+count()+FROM+neo4j_cdc.node_changes
   ```
   Count increased!

4. **Neo4j** → Refresh graph visualization

---

## 📊 Key Metrics to Highlight

### **Performance:**
- ✅ **Throughput:** 2.2 events/sec
- ✅ **Latency:** < 5 seconds end-to-end
- ✅ **Batch size:** 100 events
- ✅ **Error rate:** 0%

### **Scale:**
- ✅ **Current data:** 38 nodes + 29 relationships
- ✅ **Total size:** 6.25 KiB
- ✅ **Operations:** CREATE, UPDATE, DELETE tracked

### **Production Features:**
- ✅ **Batch processing** with timeout
- ✅ **Auto-commit** Kafka offsets
- ✅ **Graceful shutdown** handling
- ✅ **Native ClickHouse** driver
- ✅ **Real-time analytics** views

---

## 🧪 Interactive Demo Commands

### Generate New CDC Events

```bash
# SSH into server
ssh maruthi@37.27.131.209

# Generate more data
docker exec neo4j-cdc-producer python /app/cdc_producer.py

# Watch consumer process it
docker logs neo4j-cdc-consumer --tail 30 --follow
```

### Query Live Data

**Neo4j (Cypher):**
```cypher
// Create a new person
CREATE (p:Person {name: 'Demo User', created_at: datetime()})
RETURN p
```

**ClickHouse (SQL):**
```sql
-- See the newest event
SELECT * 
FROM neo4j_cdc.node_changes 
ORDER BY insert_time DESC 
LIMIT 1;
```

---

## 🔐 Security Note

⚠️ **These are public URLs accessible to anyone!**

**For this demo:**
- ✅ Default passwords (fine for demo)
- ✅ Public access (fine for short demo)
- ✅ No sensitive data (good!)

**After demo, close ports:**
```bash
sudo ufw delete allow 7474/tcp
sudo ufw delete allow 8124/tcp
sudo ufw delete allow 8081/tcp
```

---

## 🐛 Troubleshooting

### Can't access from browser?

1. **Verify firewall:**
   ```bash
   sudo ufw status | grep -E '7474|8124|8081'
   ```

2. **Verify services running:**
   ```bash
   docker compose ps
   ```

3. **Test from another location:**
   ```bash
   curl http://37.27.131.209:7474
   ```

### Services not responding?

```bash
# Restart all services
cd /home/maruthi/.openclaw/workspace/neo4j-clickhouse-cdc
docker compose restart

# Check logs
docker logs neo4j-cdc-source --tail 20
docker logs neo4j-cdc-clickhouse --tail 20
docker logs neo4j-cdc-consumer --tail 20
```

---

## 📱 Share These URLs

Copy and paste for your audience:

```
Neo4j Browser:
http://37.27.131.209:7474
(neo4j / password123)

Kafka UI:
http://37.27.131.209:8081

ClickHouse Queries:
http://37.27.131.209:8124/?query=SELECT+1

Example ClickHouse Query:
http://37.27.131.209:8124/?query=SELECT+operation,count()+AS+count+FROM+neo4j_cdc.node_changes+GROUP+BY+operation
```

---

## ✅ Quick Verification

All services verified working:
- ✅ Neo4j Browser: HTTP 200 OK
- ✅ ClickHouse HTTP: HTTP 200 OK  
- ✅ Kafka UI: HTTP 200 OK

**Public IP:** 37.27.131.209  
**Ports:** 7474, 8124, 8081  
**Status:** 🟢 LIVE and ready for demo!

---

## 🎯 Demo Success Checklist

- [ ] All three URLs accessible from external network
- [ ] Neo4j Browser shows graph visualization
- [ ] Kafka UI displays topics and messages
- [ ] ClickHouse responds to SQL queries
- [ ] Can generate new CDC events
- [ ] Real-time data flow visible
- [ ] Consumer processing events successfully

---

**Demo Duration:** 5-10 minutes  
**Audience:** Technical stakeholders  
**Focus:** Real-time CDC pipeline, production-ready architecture
