-- ============================================================================
-- Neo4j CDC Pipeline - ClickHouse Schema (Kafka Connect Version)
-- ============================================================================

-- Create database
CREATE DATABASE IF NOT EXISTS neo4j_cdc;

-- ============================================================================
-- Node Changes Table (receives data from Kafka Connect)
-- ============================================================================
CREATE TABLE IF NOT EXISTS neo4j_cdc.node_changes (
    event_id String,
    tx_id UInt64,
    operation LowCardinality(String),  -- CREATE, UPDATE, DELETE
    labels Array(String),
    node_id String,
    properties String,  -- JSON string of node properties
    event_time DateTime64(3, 'UTC'),
    insert_time DateTime64(3, 'UTC') DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, node_id)
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Relationship Changes Table (receives data from Kafka Connect)
-- ============================================================================
CREATE TABLE IF NOT EXISTS neo4j_cdc.relationship_changes (
    event_id String,
    tx_id UInt64,
    operation LowCardinality(String),  -- CREATE, UPDATE, DELETE
    rel_type String,
    rel_id String,
    from_node_id String,
    to_node_id String,
    properties String,  -- JSON string of relationship properties
    event_time DateTime64(3, 'UTC'),
    insert_time DateTime64(3, 'UTC') DEFAULT now64(3)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, rel_id)
SETTINGS index_granularity = 8192;

-- ============================================================================
-- Verify tables created
-- ============================================================================
SELECT 
    database,
    name,
    engine,
    formatReadableSize(total_bytes) AS size
FROM system.tables
WHERE database = 'neo4j_cdc'
FORMAT Pretty;
