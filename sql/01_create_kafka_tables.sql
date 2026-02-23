-- Create database for CDC data
CREATE DATABASE IF NOT EXISTS neo4j_cdc;

-- ============================================================================
-- Kafka Source Table for Node Events
-- ============================================================================
CREATE TABLE IF NOT EXISTS neo4j_cdc.kafka_node_events (
    event_id String,
    tx_id UInt64,
    operation LowCardinality(String),  -- CREATE, UPDATE, DELETE
    labels Array(String),
    node_id String,
    properties String,  -- JSON string of node properties
    timestamp DateTime64(3, 'UTC')
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'neo4j.nodes',
    kafka_group_name = 'clickhouse_node_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 2,
    kafka_max_block_size = 1000,
    kafka_skip_broken_messages = 10,
    kafka_thread_per_consumer = 1;

-- ============================================================================
-- Kafka Source Table for Relationship Events
-- ============================================================================
CREATE TABLE IF NOT EXISTS neo4j_cdc.kafka_relationship_events (
    event_id String,
    tx_id UInt64,
    operation LowCardinality(String),  -- CREATE, UPDATE, DELETE
    rel_type String,
    rel_id String,
    from_node_id String,
    to_node_id String,
    properties String,  -- JSON string of relationship properties
    timestamp DateTime64(3, 'UTC')
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:29092',
    kafka_topic_list = 'neo4j.relationships',
    kafka_group_name = 'clickhouse_rel_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 2,
    kafka_max_block_size = 1000,
    kafka_skip_broken_messages = 10,
    kafka_thread_per_consumer = 1;

-- ============================================================================
-- Verify Kafka tables are created
-- ============================================================================
SELECT 
    database,
    name,
    engine,
    total_rows
FROM system.tables
WHERE database = 'neo4j_cdc' AND engine = 'Kafka';
