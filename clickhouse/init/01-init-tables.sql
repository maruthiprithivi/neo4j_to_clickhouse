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

-- Create Kafka engine table for nodes
CREATE TABLE IF NOT EXISTS nodes_kafka_queue (
    event_id String,
    event_type String,
    event_timestamp DateTime64(3),
    entity_id String,
    labels Array(String),
    properties_before String,
    properties_after String,
    metadata String
) ENGINE = Kafka
SETTINGS 
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'neo4j.nodes',
    kafka_group_name = 'clickhouse_nodes_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 2,
    kafka_max_block_size = 1048576;

-- Create Kafka engine table for relationships
CREATE TABLE IF NOT EXISTS relationships_kafka_queue (
    event_id String,
    event_type String,
    event_timestamp DateTime64(3),
    entity_id String,
    relationship_type String,
    source_id String,
    target_id String,
    properties_before String,
    properties_after String,
    metadata String
) ENGINE = Kafka
SETTINGS 
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'neo4j.relationships',
    kafka_group_name = 'clickhouse_relationships_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 2,
    kafka_max_block_size = 1048576;

-- Create materialized view for nodes
CREATE MATERIALIZED VIEW IF NOT EXISTS nodes_kafka_mv TO nodes_cdc AS
SELECT 
    event_id,
    CAST(event_type AS Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3)) AS event_type,
    event_timestamp,
    entity_id,
    labels,
    properties_before,
    properties_after,
    metadata
FROM nodes_kafka_queue;

-- Create materialized view for relationships
CREATE MATERIALIZED VIEW IF NOT EXISTS relationships_kafka_mv TO relationships_cdc AS
SELECT 
    event_id,
    CAST(event_type AS Enum8('INSERT' = 1, 'UPDATE' = 2, 'DELETE' = 3)) AS event_type,
    event_timestamp,
    entity_id,
    relationship_type,
    source_id,
    target_id,
    properties_before,
    properties_after,
    metadata
FROM relationships_kafka_queue;
