-- Create database
CREATE DATABASE IF NOT EXISTS cdc;

-- Switch to cdc database
USE cdc;

-- Create target table for node CDC events
CREATE TABLE IF NOT EXISTS nodes_cdc (
    event_id String,
    event_type Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3),
    event_timestamp DateTime64(3),
    entity_id String,
    labels Array(String),
    properties_before String,
    properties_after String,
    metadata String
) ENGINE = MergeTree()
ORDER BY (event_timestamp, event_id)
PARTITION BY toYYYYMM(event_timestamp)
SETTINGS index_granularity = 8192;

-- Create target table for relationship CDC events
CREATE TABLE IF NOT EXISTS relationships_cdc (
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
PARTITION BY toYYYYMM(event_timestamp)
SETTINGS index_granularity = 8192;

-- Create Kafka engine table for nodes (JSONAsString for nested connector output)
CREATE TABLE IF NOT EXISTS nodes_kafka_queue (
    raw String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'neo4j-cdc-nodes',
    kafka_group_name = 'clickhouse_nodes_consumer',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 2,
    kafka_max_block_size = 1048576;

-- Create Kafka engine table for relationships (JSONAsString for nested connector output)
CREATE TABLE IF NOT EXISTS relationships_kafka_queue (
    raw String
) ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'neo4j-cdc-relationships',
    kafka_group_name = 'clickhouse_relationships_consumer',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 2,
    kafka_max_block_size = 1048576;

-- Create materialized view for nodes
-- Neo4j CDC connector output structure:
--   id: unique event id
--   metadata.txStartTime.TZDT: ISO 8601 timestamp string
--   event.operation: CREATE / UPDATE / DELETE
--   event.elementId: neo4j element id
--   event.labels: array of label strings
--   event.state.before/after.properties: property map with typed values
CREATE MATERIALIZED VIEW IF NOT EXISTS nodes_kafka_mv TO nodes_cdc AS
SELECT
    JSONExtractString(raw, 'id') AS event_id,
    CAST(
        multiIf(
            JSONExtractString(raw, 'event', 'operation') = 'CREATE', 'INSERT',
            JSONExtractString(raw, 'event', 'operation') = 'UPDATE', 'UPDATE',
            JSONExtractString(raw, 'event', 'operation') = 'DELETE', 'DELETE',
            'INSERT'
        ) AS Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3)
    ) AS event_type,
    parseDateTimeBestEffort(
        JSONExtractString(raw, 'metadata', 'txStartTime', 'TZDT')
    ) AS event_timestamp,
    JSONExtractString(raw, 'event', 'elementId') AS entity_id,
    JSONExtract(raw, 'event', 'labels', 'Array(String)') AS labels,
    JSONExtractRaw(raw, 'event', 'state', 'before', 'properties') AS properties_before,
    JSONExtractRaw(raw, 'event', 'state', 'after', 'properties') AS properties_after,
    raw AS metadata
FROM nodes_kafka_queue;

-- Create materialized view for relationships
-- Neo4j CDC connector relationship output structure:
--   event.eventType: RELATIONSHIP_EVENT
--   event.type: relationship type string
--   event.start.elementId / event.end.elementId: source/target node ids
CREATE MATERIALIZED VIEW IF NOT EXISTS relationships_kafka_mv TO relationships_cdc AS
SELECT
    JSONExtractString(raw, 'id') AS event_id,
    CAST(
        multiIf(
            JSONExtractString(raw, 'event', 'operation') = 'CREATE', 'INSERT',
            JSONExtractString(raw, 'event', 'operation') = 'UPDATE', 'UPDATE',
            JSONExtractString(raw, 'event', 'operation') = 'DELETE', 'DELETE',
            'INSERT'
        ) AS Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3)
    ) AS event_type,
    parseDateTimeBestEffort(
        JSONExtractString(raw, 'metadata', 'txStartTime', 'TZDT')
    ) AS event_timestamp,
    JSONExtractString(raw, 'event', 'elementId') AS entity_id,
    JSONExtractString(raw, 'event', 'type') AS relationship_type,
    JSONExtractString(raw, 'event', 'start', 'elementId') AS source_id,
    JSONExtractString(raw, 'event', 'end', 'elementId') AS target_id,
    JSONExtractRaw(raw, 'event', 'state', 'before', 'properties') AS properties_before,
    JSONExtractRaw(raw, 'event', 'state', 'after', 'properties') AS properties_after,
    raw AS metadata
FROM relationships_kafka_queue;
