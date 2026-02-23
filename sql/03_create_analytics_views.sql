-- ============================================================================
-- Analytical Views for CDC Data
-- ============================================================================

-- ============================================================================
-- View: Latest state of each node (most recent event per node_id)
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.node_latest_state AS
SELECT 
    node_id,
    labels,
    properties,
    operation,
    event_time,
    tx_id
FROM (
    SELECT 
        node_id,
        labels,
        properties,
        operation,
        event_time,
        tx_id,
        ROW_NUMBER() OVER (PARTITION BY node_id ORDER BY event_time DESC, tx_id DESC) AS rn
    FROM neo4j_cdc.node_changes
)
WHERE rn = 1 AND operation != 'DELETE';

-- ============================================================================
-- View: Active relationships (not deleted)
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.relationship_latest_state AS
SELECT 
    rel_id,
    rel_type,
    from_node_id,
    to_node_id,
    properties,
    operation,
    event_time,
    tx_id
FROM (
    SELECT 
        rel_id,
        rel_type,
        from_node_id,
        to_node_id,
        properties,
        operation,
        event_time,
        tx_id,
        ROW_NUMBER() OVER (PARTITION BY rel_id ORDER BY event_time DESC, tx_id DESC) AS rn
    FROM neo4j_cdc.relationship_changes
)
WHERE rn = 1 AND operation != 'DELETE';

-- ============================================================================
-- View: Change frequency by hour
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.change_frequency_hourly AS
SELECT 
    toStartOfHour(event_time) AS hour,
    operation,
    count() AS event_count,
    uniq(tx_id) AS unique_transactions
FROM neo4j_cdc.node_changes
GROUP BY hour, operation
ORDER BY hour DESC, operation;

-- ============================================================================
-- View: Node count by label
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.node_count_by_label AS
SELECT 
    arrayJoin(labels) AS label,
    count() AS node_count,
    max(event_time) AS last_change
FROM neo4j_cdc.node_latest_state
GROUP BY label
ORDER BY node_count DESC;

-- ============================================================================
-- View: Relationship count by type
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.relationship_count_by_type AS
SELECT 
    rel_type,
    count() AS rel_count,
    max(event_time) AS last_change
FROM neo4j_cdc.relationship_latest_state
GROUP BY rel_type
ORDER BY rel_count DESC;

-- ============================================================================
-- View: Recent activity (last 24 hours)
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.recent_activity AS
SELECT 
    'node' AS entity_type,
    operation,
    count() AS count,
    avg(dateDiff('second', event_time, insert_time)) AS avg_lag_seconds
FROM neo4j_cdc.node_changes
WHERE event_time >= now() - INTERVAL 24 HOUR
GROUP BY operation
UNION ALL
SELECT 
    'relationship' AS entity_type,
    operation,
    count() AS count,
    avg(dateDiff('second', event_time, insert_time)) AS avg_lag_seconds
FROM neo4j_cdc.relationship_changes
WHERE event_time >= now() - INTERVAL 24 HOUR
GROUP BY operation
ORDER BY entity_type, operation;

-- ============================================================================
-- View: Change audit log (combines nodes and relationships)
-- ============================================================================
CREATE OR REPLACE VIEW neo4j_cdc.change_audit_log AS
SELECT 
    'node' AS entity_type,
    event_id,
    tx_id,
    operation,
    node_id AS entity_id,
    labels AS entity_labels,
    '' AS entity_type_name,
    event_time,
    insert_time
FROM neo4j_cdc.node_changes
UNION ALL
SELECT 
    'relationship' AS entity_type,
    event_id,
    tx_id,
    operation,
    rel_id AS entity_id,
    [] AS entity_labels,
    rel_type AS entity_type_name,
    event_time,
    insert_time
FROM neo4j_cdc.relationship_changes
ORDER BY event_time DESC
LIMIT 1000;

-- ============================================================================
-- Verify views are created
-- ============================================================================
SELECT 
    database,
    name,
    engine
FROM system.tables
WHERE database = 'neo4j_cdc' 
  AND engine = 'View'
ORDER BY name;
