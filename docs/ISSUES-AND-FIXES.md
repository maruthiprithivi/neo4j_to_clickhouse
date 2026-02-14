# Issues Found and Fixes Applied

This document captures all issues discovered during the dependency upgrade and benchmarking of the Neo4j-to-ClickHouse CDC pipeline, along with their root causes and resolutions.

---

## Issue 1: kafka-python is Abandoned

**Severity:** Critical
**File:** `cdc-bridge/requirements.txt`, `cdc-bridge/main.py`

**Problem:** The `kafka-python==2.0.2` package has been unmaintained since 2020. It has known bugs with newer Kafka protocol versions and no Python 3.12+ compatibility.

**Fix:** Replaced with `confluent-kafka==2.13.0` which uses librdkafka (C library) and is the officially supported Kafka Python client from Confluent.

**API Changes:**
- `KafkaProducer(...)` -> `Producer({...})` with dot-separated config keys
- `producer.send(topic, value=..., key=...)` -> `producer.produce(topic, value=..., key=..., callback=...)` + `producer.flush()`
- Added `delivery_report()` callback function for async delivery confirmation
- Connection validation: `prod.list_topics(timeout=10)` instead of implicit validation
- Serialization moved to call site: `json.dumps(event).encode('utf-8')` instead of `value_serializer`

**Dockerfile Changes:**
- Added `librdkafka-dev` to system dependencies (required by confluent-kafka C extension)
- Upgraded from `python:3.11-slim` to `python:3.12-slim`

---

## Issue 2: APOC Trigger `apoc.load.jsonParams` Syntax

**Severity:** Critical
**File:** `neo4j/install-triggers.cypher`

**Problem:** The original triggers passed a nested map as the headers parameter:
```cypher
{method: "POST", headers: {"Content-Type": "application/json"}}
```
But `apoc.load.jsonParams` has the signature:
```
(url, headers, payload, path, config)
```
The `method` belongs in the `config` parameter (5th), not in `headers` (2nd). Additionally, Cypher map literal keys with hyphens (like `Content-Type`) cannot use double-quoted strings and require backtick-quoting.

**Root Cause Chain:**
1. `method` was in the wrong parameter position
2. `"Content-Type"` is invalid Cypher syntax (requires backticks)
3. Backtick-quoted keys do not survive APOC trigger storage and reparsing

**Fix:** Use `null` for headers and pass `{method: "POST"}` as the config parameter. Modified the CDC bridge to accept JSON without Content-Type header via `request.get_json(force=True)`.

---

## Issue 3: APOC Trigger `$assignedNodeProperties` Data Structure

**Severity:** Critical
**File:** `neo4j/install-triggers.cypher`

**Problem:** The original UPDATE triggers treated `$assignedNodeProperties[key]` as a list of nodes:
```cypher
UNWIND $assignedNodeProperties[key] AS node
```
But in Neo4j 5.x APOC, `$assignedNodeProperties[key]` returns a `List<Map{node, key, old, new}>` -- each element is a map containing the node reference, the property key, old value, and new value.

**Error Message:**
```
Invalid input for function 'elementId()': Expected Map{node -> (26), new -> String("fresh_trigger"), key -> String("name"), old -> NO_VALUE} to be a node or relationship, but it was `Map`
```

**Fix:** Extract the actual node from the change map:
```cypher
UNWIND $assignedNodeProperties[key] AS change
WITH change.node AS node
```

Same fix applied to `$assignedRelationshipProperties[key]` using `change.relationship AS rel`.

---

## Issue 4: APOC Trigger Cache Not Clearing on `apoc.trigger.install`

**Severity:** High
**Affects:** Neo4j 5.26.0 with APOC Core

**Problem:** When `apoc.trigger.install` is called to update an existing trigger, the old trigger query is cached in APOC's TriggerHandler and continues to execute. Even `apoc.trigger.drop` sets `installed: FALSE` but does not remove the trigger from the in-memory execution list.

**Fix:** After modifying triggers, a Neo4j restart is REQUIRED to clear the trigger cache:
```bash
docker-compose restart neo4j
```
The recommended workflow for trigger changes:
1. Drop all triggers: `CALL apoc.trigger.drop('neo4j', 'triggerName')`
2. Restart Neo4j: `docker-compose restart neo4j`
3. Wait for Neo4j to be healthy
4. Install new triggers

---

## Issue 5: APOC Triggers Must Be Installed Against System Database

**Severity:** High
**File:** `Makefile`

**Problem:** `apoc.trigger.install` in Neo4j 5.x must be run against the `system` database, not the default `neo4j` database. Running against `neo4j` produces:
```
No write operations are allowed directly on this database. Writes must pass through the leader. The role of this server is: FOLLOWER
```

**Fix:** Added `-d system` flag to the cypher-shell command:
```makefile
docker exec -i neo4j-cdc-neo4j cypher-shell -u neo4j -p password123 -d system < neo4j/install-triggers.cypher
```

---

## Issue 6: APOC Triggers Not Enabled

**Severity:** High
**File:** `docker-compose.yml`

**Problem:** APOC triggers require `apoc.trigger.enabled=true` in `apoc.conf`. Without this setting, `apoc.trigger.install` fails with:
```
Triggers have not been enabled. Set 'apoc.trigger.enabled=true' in your apoc.conf
```

**Fix:** Added the environment variable to the Neo4j service in docker-compose.yml:
```yaml
NEO4J_apoc_trigger_enabled: 'true'
```

---

## Issue 7: ClickHouse DateTime64 Parsing Failure

**Severity:** High
**File:** `cdc-bridge/main.py`

**Problem:** Python's `datetime.now(timezone.utc).isoformat()` produces timestamps with timezone offset like `2026-02-14T05:58:36.123456+00:00`. ClickHouse's JSONEachRow format with `DateTime64(3)` cannot parse the `+00:00` suffix.

**Error in ClickHouse:**
```
Cannot parse input: expected '"' before: '+00:00"}'
```

**Fix:** Changed the timestamp format to ClickHouse-compatible format:
```python
datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
```
This produces: `2026-02-14 05:58:36.123`

---

## Issue 8: ClickHouse Port Mismatch in Test Runner

**Severity:** Medium
**File:** `test-scenarios/run_tests.py`

**Problem:** The test runner defaulted to port 9000 (ClickHouse native protocol), but `clickhouse-connect` uses the HTTP interface which runs on port 8123.

**Fix:** Changed the default port:
```python
CLICKHOUSE_PORT = int(os.getenv('CLICKHOUSE_PORT', '8123'))
```

---

## Issue 9: Deprecated `datetime.utcnow()`

**Severity:** Low
**Files:** `cdc-bridge/main.py`, `initial-load/scripts/03-bulk-import.py`

**Problem:** Python 3.12 deprecates `datetime.utcnow()` in favor of timezone-aware datetimes.

**Fix:** Replaced with `datetime.now(timezone.utc)` throughout.

---

## Issue 10: Deprecated Docker Compose `version` Key

**Severity:** Low
**File:** `docker-compose.yml`

**Problem:** The `version: '3.8'` key is deprecated and ignored by modern Docker Compose.

**Fix:** Removed the `version` line entirely.

---

## Issue 11: ClickHouse Kafka Consumer Offset Stuck on Bad Messages

**Severity:** Medium (operational)

**Problem:** When ClickHouse Kafka engine tables encounter unparseable messages (e.g., from the timestamp format issue), the consumer gets stuck retrying the same offset forever. All subsequent valid messages are blocked.

**Fix (operational procedure):**
1. Detach the Kafka engine table: `DETACH TABLE cdc.nodes_kafka_queue`
2. Reset the consumer group offset:
   ```bash
   kafka-consumer-groups --bootstrap-server localhost:9092 \
     --group clickhouse_nodes_consumer \
     --reset-offsets --to-latest \
     --topic neo4j.nodes --execute
   ```
3. Reattach the table: `ATTACH TABLE cdc.nodes_kafka_queue`

Note: This skips over the bad messages. If you need to reprocess, use `--to-earliest` or a specific offset.

---

## Issue 12: Outdated clickhouse-connect Version

**Severity:** Medium
**Files:** `test-scenarios/requirements.txt`, `initial-load/requirements.txt`

**Problem:** The plan specified `clickhouse-connect==0.8.14` but the latest official version from ClickHouse is `0.11.0`.

**Fix:** Updated to `clickhouse-connect==0.11.0` (test-scenarios) and `clickhouse-connect>=0.11.0` (initial-load). The API is backwards-compatible (`get_client()`, `client.query()`, `client.insert()` all work the same).

---

## Dependency Versions Summary (After Upgrade)

### cdc-bridge/requirements.txt
| Package | Old | New |
|---------|-----|-----|
| kafka-python | 2.0.2 (abandoned) | REMOVED |
| confluent-kafka | N/A | 2.13.0 |
| flask | 3.0.0 | 3.1.2 |
| python-dotenv | 1.0.0 | 1.2.1 |
| requests | 2.31.0 | 2.32.5 |
| neo4j | 5.26.0 | 5.26.0 (kept) |

### test-scenarios/requirements.txt
| Package | Old | New |
|---------|-----|-----|
| clickhouse-connect | 0.7.19 | 0.11.0 |
| python-dotenv | 1.0.0 | 1.2.1 |
| neo4j | 5.26.0 | 5.26.0 (kept) |

### initial-load/requirements.txt
| Package | Old | New |
|---------|-----|-----|
| clickhouse-connect | >=0.6.0 | >=0.11.0 |
| pandas | >=2.0.0 | >=2.2.0,<3.0.0 |
| pyarrow | >=12.0.0 | >=18.0.0 |
| fastparquet | >=2023.0.0 | >=2024.11.0 |

### Docker Images
| Service | Old | New |
|---------|-----|-----|
| python (Dockerfile) | 3.11-slim | 3.12-slim |
| cp-kafka | 7.5.0 | 7.8.0 |
| cp-zookeeper | 7.5.0 | 7.8.0 |
| neo4j | 5.26.0 | 5.26.0 (kept) |
| clickhouse-server | 25.10 | 25.10 (kept) |

---

## Verification Results

After all fixes, the full test suite produces:
- **349 node CDC events** (50 INSERT, 270 UPDATE, 29 DELETE)
- **199 relationship CDC events** (36 INSERT, 131 UPDATE, 32 DELETE)
- All events flow end-to-end: Neo4j -> CDC Bridge -> Kafka -> ClickHouse
