# Public Access Setup for Neo4j CDC Demo

## Server Information

- **Public IP**: 37.27.131.209
- **Services Running**:
  - Neo4j Browser: Port 7474
  - ClickHouse HTTP: Port 8124  
  - Kafka UI: Port 8081

---

## Option 1: Direct Public Access ⚡ (Recommended for Demo)

### Current Status

Services are bound to `0.0.0.0` (all interfaces), which means they're already accessible if firewall allows.

### Access URLs (After Firewall Configuration)

```
🌐 Neo4j Browser:    http://37.27.131.209:7474
   Username: neo4j
   Password: password123

🌐 ClickHouse UI:    http://37.27.131.209:8124
   Run queries via:  http://37.27.131.209:8124/?query=SELECT+1

🌐 Kafka UI:         http://37.27.131.209:8081
   Monitor topics, consumers, and messages
```

### Firewall Setup (UFW)

Run these commands to open the required ports:

```bash
# Allow Neo4j Browser (HTTP)
sudo ufw allow 7474/tcp comment 'Neo4j Browser'

# Allow ClickHouse HTTP
sudo ufw allow 8124/tcp comment 'ClickHouse HTTP'

# Allow Kafka UI
sudo ufw allow 8081/tcp comment 'Kafka UI'

# Check status
sudo ufw status numbered
```

### Security Considerations

⚠️ **Warning**: These ports will be publicly accessible. For production:

1. **Add authentication** to ClickHouse queries
2. **Use HTTPS** with proper SSL certificates
3. **Restrict IP access** via firewall rules
4. **Change default passwords**

For quick demo, this is fine. Close ports after demo:

```bash
# Close ports after demo
sudo ufw delete allow 7474/tcp
sudo ufw delete allow 8124/tcp
sudo ufw delete allow 8081/tcp
```

---

## Option 2: ngrok Tunnels 🔒 (HTTPS + Nice URLs)

### Setup Steps

1. **Sign up for free ngrok account**: https://ngrok.com/signup
2. **Get your auth token**: https://dashboard.ngrok.com/get-started/your-authtoken
3. **Configure ngrok**:

```bash
cd /home/maruthi/.openclaw/workspace/neo4j-clickhouse-cdc

# Add your auth token
ngrok config add-authtoken YOUR_TOKEN_HERE

# Start all tunnels
ngrok start --all --config ngrok.yml
```

### ngrok Benefits

✅ **HTTPS automatically** - Secure SSL connections  
✅ **Nice URLs** - e.g., `https://abc123.ngrok-free.app`  
✅ **No firewall config** - Works through NAT  
✅ **Traffic inspection** - See all requests at http://localhost:4040  

### Example ngrok Output

```
Session Status  online
Account         you@email.com
Region          US (us)

Tunnels
neo4j       http://abc123.ngrok-free.app -> http://localhost:7474
clickhouse  http://xyz456.ngrok-free.app -> http://localhost:8124
kafka-ui    http://def789.ngrok-free.app -> http://localhost:8081
```

**Note**: Free ngrok tier limits to 1 agent with 3 endpoints. Use `ngrok start neo4j clickhouse kafka-ui`.

---

## Option 3: localtunnel 🌐 (No Signup Required)

Quick alternative if you don't want to sign up:

```bash
# Install localtunnel
npm install -g localtunnel

# Create tunnels (run in separate terminals)
lt --port 7474 --subdomain neo4j-demo
lt --port 8124 --subdomain clickhouse-demo  
lt --port 8081 --subdomain kafka-demo
```

---

## Quick Test Commands

### Test Neo4j Access

```bash
# From your local machine or anywhere
curl http://37.27.131.209:7474/browser/

# Should return Neo4j Browser HTML
```

### Test ClickHouse Access

```bash
curl "http://37.27.131.209:8124/?query=SELECT+1"

# Should return: 1
```

### Test Kafka UI

```bash
curl -I http://37.27.131.209:8081

# Should return: HTTP/1.1 200 OK
```

---

## Recommended Setup for Demo

### **Quick Start (5 minutes)**

1. **Open firewall ports**:
   ```bash
   sudo ufw allow 7474/tcp
   sudo ufw allow 8124/tcp
   sudo ufw allow 8081/tcp
   ```

2. **Verify services are running**:
   ```bash
   cd /home/maruthi/.openclaw/workspace/neo4j-clickhouse-cdc
   docker compose ps
   ```

3. **Share these URLs**:
   - Neo4j: `http://37.27.131.209:7474` (neo4j/password123)
   - ClickHouse: `http://37.27.131.209:8124`
   - Kafka UI: `http://37.27.131.209:8081`

4. **Run demo queries**:

   **Neo4j**:
   ```cypher
   // In Neo4j Browser
   MATCH (p:Person)-[r:WORKS_AT]->(c:Company)
   RETURN p, r, c
   LIMIT 10
   ```

   **ClickHouse**:
   ```sql
   -- Recent CDC events
   SELECT * FROM neo4j_cdc.node_changes 
   ORDER BY event_time DESC 
   LIMIT 10;
   
   -- Current graph state
   SELECT 
       arrayJoin(labels) AS label,
       count() AS count
   FROM neo4j_cdc.node_latest_state
   GROUP BY label;
   ```

5. **After demo, close ports**:
   ```bash
   sudo ufw delete allow 7474/tcp
   sudo ufw delete allow 8124/tcp
   sudo ufw delete allow 8081/tcp
   ```

---

## Troubleshooting

### Ports Not Accessible?

```bash
# Check if services are listening on correct interfaces
sudo netstat -tlnp | grep -E '7474|8124|8081'

# Should show 0.0.0.0:PORT (not 127.0.0.1:PORT)
```

### Docker Networking Issues?

```bash
# Verify docker containers are running
docker compose ps

# Check container ports
docker port neo4j-cdc-source
docker port neo4j-cdc-clickhouse
docker port neo4j-cdc-kafka-ui
```

### UFW Not Installed?

```bash
sudo apt install ufw -y
sudo ufw enable
```

---

## Security Checklist for Public Demo

- [ ] Change Neo4j password from default
- [ ] Set ClickHouse password for HTTP queries
- [ ] Enable UFW firewall
- [ ] Only open ports during demo
- [ ] Close ports after demo
- [ ] Monitor access logs
- [ ] Use HTTPS if handling sensitive data (use ngrok)

---

## Demo Script

### 1. Show Architecture
Open `CDC-FLOW-DIAGRAM.md` or share the Mermaid diagram

### 2. Show Live Services

**Neo4j Browser** → `http://37.27.131.209:7474`
- Show graph visualization
- Run Cypher queries

**Kafka UI** → `http://37.27.131.209:8081`  
- Show topics: `neo4j.nodes`, `neo4j.relationships`
- View messages
- Check consumer lag

**ClickHouse** → `http://37.27.131.209:8124/?query=SELECT+*+FROM+neo4j_cdc.node_changes+LIMIT+5`
- Show ingested CDC events
- Run analytics queries

### 3. Generate New Data

```bash
# SSH into server
docker exec neo4j-cdc-producer python /app/cdc_producer.py

# Watch in real-time:
# - Kafka UI: New messages appear
# - ClickHouse: Row count increases
# - Consumer logs: Processing events
```

### 4. Show End-to-End Flow

1. Create a node in Neo4j
2. Watch event in Kafka topic
3. See consumer process it
4. Query result in ClickHouse

---

**Status**: Ready for public demo! 🎉
**Choose**: Option 1 (Direct) for speed, Option 2 (ngrok) for HTTPS
