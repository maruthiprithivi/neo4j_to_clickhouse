-- ============================================================================
-- Sample Queries for Neo4j CDC in ClickHouse
-- ============================================================================

-- ============================================================================
-- 1. Check total events captured
-- ============================================================================
SELECT 
    'Nodes' AS type,
    count() AS total_events,
    min(event_time) AS first_event,
    max(event_time) AS last_event
FROM neo4j_cdc.node_changes
UNION ALL
SELECT 
    'Relationships' AS type,
    count() AS total_events,
    min(event_time) AS first_event,
    max(event_time) AS last_event
FROM neo4j_cdc.relationship_changes;

-- ============================================================================
-- 2. Event distribution by operation type
-- ============================================================================
SELECT 
    operation,
    count() AS event_count,
    count() * 100.0 / sum(count()) OVER () AS percentage
FROM neo4j_cdc.node_changes
GROUP BY operation
ORDER BY event_count DESC;

-- ============================================================================
-- 3. Most active transactions (top 10)
-- ============================================================================
SELECT 
    tx_id,
    count() AS changes_count,
    groupArray(operation) AS operations,
    min(event_time) AS tx_start,
    max(event_time) AS tx_end
FROM neo4j_cdc.node_changes
GROUP BY tx_id
ORDER BY changes_count DESC
LIMIT 10;

-- ============================================================================
-- 4. Node change history for a specific node
-- ============================================================================
-- Replace 'node_xxx' with actual node_id
SELECT 
    event_time,
    operation,
    labels,
    properties,
    tx_id
FROM neo4j_cdc.node_changes
WHERE node_id = 'node_xxx'
ORDER BY event_time;

-- ============================================================================
-- 5. Find nodes that were created and then deleted
-- ============================================================================
SELECT 
    node_id,
    groupArray(operation) AS operations,
    min(event_time) AS created_at,
    max(event_time) AS deleted_at,
    dateDiff('second', min(event_time), max(event_time)) AS lifetime_seconds
FROM neo4j_cdc.node_changes
GROUP BY node_id
HAVING hasAll(operations, ['CREATE', 'DELETE'])
ORDER BY lifetime_seconds;

-- ============================================================================
-- 6. Changes per minute (time series analysis)
-- ============================================================================
SELECT 
    toStartOfMinute(event_time) AS minute,
    count() AS events,
    uniq(node_id) AS unique_nodes,
    uniq(tx_id) AS unique_transactions
FROM neo4j_cdc.node_changes
WHERE event_time >= now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute;

-- ============================================================================
-- 7. Most frequently updated nodes (top 20)
-- ============================================================================
SELECT 
    node_id,
    labels,
    count() AS update_count,
    min(event_time) AS first_update,
    max(event_time) AS last_update
FROM neo4j_cdc.node_changes
WHERE operation = 'UPDATE'
GROUP BY node_id, labels
ORDER BY update_count DESC
LIMIT 20;

-- ============================================================================
-- 8. Relationship creation patterns
-- ============================================================================
SELECT 
    rel_type,
    count() AS created_count,
    count(DISTINCT from_node_id) AS unique_from_nodes,
    count(DISTINCT to_node_id) AS unique_to_nodes,
    toStartOfHour(min(event_time)) AS first_seen,
    toStartOfHour(max(event_time)) AS last_seen
FROM neo4j_cdc.relationship_changes
WHERE operation = 'CREATE'
GROUP BY rel_type
ORDER BY created_count DESC;

-- ============================================================================
-- 9. Extract specific properties from nodes
-- ============================================================================
-- Example: Extract 'name' and 'email' properties from Person nodes
SELECT 
    node_id,
    JSONExtractString(properties, 'name') AS name,
    JSONExtractString(properties, 'email') AS email,
    event_time
FROM neo4j_cdc.node_latest_state
WHERE has(labels, 'Person')
LIMIT 100;

-- ============================================================================
-- 10. Data quality checks
-- ============================================================================
-- Check for missing properties
SELECT 
    'Nodes with empty properties' AS check_name,
    count() AS count
FROM neo4j_cdc.node_changes
WHERE properties = '{}' OR properties = ''
UNION ALL
SELECT 
    'Nodes with null node_id' AS check_name,
    count() AS count
FROM neo4j_cdc.node_changes
WHERE node_id = '' OR node_id IS NULL;

-- ============================================================================
-- 11. CDC pipeline lag monitoring
-- ============================================================================
SELECT 
    formatReadableTimeDelta(avg(dateDiff('second', event_time, insert_time))) AS avg_lag,
    formatReadableTimeDelta(max(dateDiff('second', event_time, insert_time))) AS max_lag,
    count() AS events_last_minute
FROM neo4j_cdc.node_changes
WHERE insert_time >= now() - INTERVAL 1 MINUTE;

-- ============================================================================
-- 12. Graph structure snapshot (current state)
-- ============================================================================
WITH 
    active_nodes AS (
        SELECT node_id, labels
        FROM neo4j_cdc.node_latest_state
    ),
    active_rels AS (
        SELECT rel_type, from_node_id, to_node_id
        FROM neo4j_cdc.relationship_latest_state
    )
SELECT 
    (SELECT count() FROM active_nodes) AS total_nodes,
    (SELECT count() FROM active_rels) AS total_relationships,
    (SELECT count(DISTINCT arrayJoin(labels)) FROM active_nodes) AS unique_labels,
    (SELECT count(DISTINCT rel_type) FROM active_rels) AS unique_rel_types;

-- ============================================================================
-- 13. Find orphaned relationships (pointing to deleted nodes)
-- ============================================================================
SELECT 
    r.rel_id,
    r.rel_type,
    r.from_node_id,
    r.to_node_id,
    CASE 
        WHEN n1.node_id IS NULL THEN 'from_node_missing'
        WHEN n2.node_id IS NULL THEN 'to_node_missing'
    END AS issue
FROM neo4j_cdc.relationship_latest_state r
LEFT JOIN neo4j_cdc.node_latest_state n1 ON r.from_node_id = n1.node_id
LEFT JOIN neo4j_cdc.node_latest_state n2 ON r.to_node_id = n2.node_id
WHERE n1.node_id IS NULL OR n2.node_id IS NULL;

-- ============================================================================
-- 14. Change velocity (changes per second)
-- ============================================================================
SELECT 
    toStartOfInterval(event_time, INTERVAL 10 SECOND) AS interval_start,
    count() / 10 AS changes_per_second,
    uniq(tx_id) / 10 AS transactions_per_second
FROM neo4j_cdc.node_changes
WHERE event_time >= now() - INTERVAL 5 MINUTE
GROUP BY interval_start
ORDER BY interval_start DESC;

-- ============================================================================
-- 15. Property change tracking (requires JSON comparison)
-- ============================================================================
-- Track what properties changed in UPDATE operations
SELECT 
    node_id,
    event_time,
    properties,
    lagInFrame(properties) OVER (PARTITION BY node_id ORDER BY event_time) AS previous_properties,
    properties != lagInFrame(properties) OVER (PARTITION BY node_id ORDER BY event_time) AS has_changes
FROM neo4j_cdc.node_changes
WHERE operation = 'UPDATE'
ORDER BY node_id, event_time
LIMIT 100;
