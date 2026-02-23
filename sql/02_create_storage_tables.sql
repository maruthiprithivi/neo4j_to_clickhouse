-- ============================================================================
-- Storage Table for Node Changes
-- ============================================================================
CREATE TABLE IF NOT EXISTS neo4j_cdc.node_changes (
    event_id String,
    tx_id UInt64,
    operation LowCardinality(String),
    labels Array(String),
    node_id String,
    properties String,
    event_time DateTime64(3, 'UTC'),
    insert_time DateTime DEFAULT now(),
    
    -- Extracted common properties for easier querying
    name String DEFAULT JSONExtractString(properties, 'name'),
    created_at Nullable(DateTime64(3)) DEFAULT JSONExtract(properties, 'created_at', 'Nullable(DateTime64(3))'),
    updated_at Nullable(DateTime64(3)) DEFAULT JSONExtract(properties, 'updated_at', 'Nullable(DateTime64(3))')
    
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, tx_id, node_id)
TTL event_time + INTERVAL 90 DAY  -- Keep data for 90 days
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Materialized View: Kafka -> Node Changes
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS neo4j_cdc.node_changes_mv TO neo4j_cdc.node_changes AS
SELECT
    event_id,
    tx_id,
    operation,
    labels,
    node_id,
    properties,
    timestamp AS event_time
FROM neo4j_cdc.kafka_node_events;

-- ============================================================================
-- Storage Table for Relationship Changes
-- ============================================================================
CREATE TABLE IF NOT EXISTS neo4j_cdc.relationship_changes (
    event_id String,
    tx_id UInt64,
    operation LowCardinality(String),
    rel_type String,
    rel_id String,
    from_node_id String,
    to_node_id String,
    properties String,
    event_time DateTime64(3, 'UTC'),
    insert_time DateTime DEFAULT now()
    
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, tx_id, rel_id)
TTL event_time + INTERVAL 90 DAY
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Materialized View: Kafka -> Relationship Changes
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS neo4j_cdc.relationship_changes_mv TO neo4j_cdc.relationship_changes AS
SELECT
    event_id,
    tx_id,
    operation,
    rel_type,
    rel_id,
    from_node_id,
    to_node_id,
    properties,
    timestamp AS event_time
FROM neo4j_cdc.kafka_relationship_events;

-- ============================================================================
-- Create indexes for common queries
-- ============================================================================

-- Index on node labels for filtering by type
ALTER TABLE neo4j_cdc.node_changes 
ADD INDEX IF NOT EXISTS idx_labels (labels) TYPE bloom_filter GRANULARITY 1;

-- Index on relationship type
ALTER TABLE neo4j_cdc.relationship_changes 
ADD INDEX IF NOT EXISTS idx_rel_type (rel_type) TYPE bloom_filter GRANULARITY 1;

-- ============================================================================
-- Verify storage tables are created
-- ============================================================================
SELECT 
    database,
    name,
    engine,
    total_rows,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = 'neo4j_cdc' 
  AND engine LIKE '%MergeTree%'
ORDER BY name;

-- ============================================================================
-- Verify materialized views are created
-- ============================================================================
SELECT 
    database,
    name,
    as_select
FROM system.tables
WHERE database = 'neo4j_cdc' 
  AND engine = 'MaterializedView'
ORDER BY name;
