-- ============================================================================
-- ClickHouse Table Optimization Script
-- ============================================================================
-- Purpose: Optimize tables after initial load to apply deduplication
-- Run this AFTER bulk import is complete
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 1: Check current table sizes
-- ----------------------------------------------------------------------------
SELECT 
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE database = currentDatabase()
  AND active = 1
  AND table IN ('node_events', 'relationship_events')
GROUP BY table
ORDER BY table;

-- ----------------------------------------------------------------------------
-- Step 2: Optimize node_events table
-- ----------------------------------------------------------------------------
-- This will:
-- 1. Merge all parts into fewer parts
-- 2. Apply ReplacingMergeTree deduplication logic
-- 3. Remove old versions of rows (keep only latest based on 'version' column)

OPTIMIZE TABLE node_events FINAL;

-- Check progress
SELECT 
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE database = currentDatabase()
  AND active = 1
  AND table = 'node_events'
GROUP BY table;

-- ----------------------------------------------------------------------------
-- Step 3: Optimize relationship_events table
-- ----------------------------------------------------------------------------
OPTIMIZE TABLE relationship_events FINAL;

-- Check progress
SELECT 
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE database = currentDatabase()
  AND active = 1
  AND table = 'relationship_events'
GROUP BY table;

-- ----------------------------------------------------------------------------
-- Step 4: Validate deduplication
-- ----------------------------------------------------------------------------
-- Check for duplicate entity_ids (should be 0 after OPTIMIZE FINAL)

-- Nodes: Check for duplicates
SELECT 
    entity_id,
    count(*) as duplicate_count
FROM node_events
WHERE event_type = 'SNAPSHOT'
GROUP BY entity_id
HAVING count(*) > 1
ORDER BY duplicate_count DESC
LIMIT 10;

-- Relationships: Check for duplicates
SELECT 
    entity_id,
    count(*) as duplicate_count
FROM relationship_events
WHERE event_type = 'SNAPSHOT'
GROUP BY entity_id
HAVING count(*) > 1
ORDER BY duplicate_count DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Step 5: Verify data consistency
-- ----------------------------------------------------------------------------

-- Count SNAPSHOT events
SELECT 
    'Nodes (SNAPSHOT)' as type,
    count(*) as count
FROM node_events
WHERE event_type = 'SNAPSHOT'
UNION ALL
SELECT 
    'Relationships (SNAPSHOT)' as type,
    count(*) as count
FROM relationship_events
WHERE event_type = 'SNAPSHOT';

-- Count CDC events (should be 0 if CDC hasn't started yet)
SELECT 
    'Nodes (CDC)' as type,
    count(*) as count
FROM node_events
WHERE event_type != 'SNAPSHOT'
UNION ALL
SELECT 
    'Relationships (CDC)' as type,
    count(*) as count
FROM relationship_events
WHERE event_type != 'SNAPSHOT';

-- ----------------------------------------------------------------------------
-- Step 6: Sample data validation
-- ----------------------------------------------------------------------------

-- Sample 10 random nodes
SELECT 
    entity_id,
    labels,
    properties_after,
    event_timestamp
FROM node_events
WHERE event_type = 'SNAPSHOT'
ORDER BY rand()
LIMIT 10;

-- Sample 10 random relationships
SELECT 
    entity_id,
    relationship_type,
    source_id,
    target_id,
    properties_after,
    event_timestamp
FROM relationship_events
WHERE event_type = 'SNAPSHOT'
ORDER BY rand()
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Step 7: Performance statistics
-- ----------------------------------------------------------------------------

-- Nodes by label
SELECT 
    arrayJoin(labels) as label,
    count(*) as count,
    formatReadableSize(sum(length(properties_after))) as total_size
FROM node_events
WHERE event_type = 'SNAPSHOT'
GROUP BY label
ORDER BY count DESC
LIMIT 20;

-- Relationships by type
SELECT 
    relationship_type,
    count(*) as count,
    formatReadableSize(sum(length(properties_after))) as total_size
FROM relationship_events
WHERE event_type = 'SNAPSHOT'
GROUP BY relationship_type
ORDER BY count DESC
LIMIT 20;

-- ----------------------------------------------------------------------------
-- Step 8: Storage analysis
-- ----------------------------------------------------------------------------

-- Compression ratio
SELECT 
    table,
    formatReadableSize(sum(data_compressed_bytes)) as compressed,
    formatReadableSize(sum(data_uncompressed_bytes)) as uncompressed,
    round(sum(data_uncompressed_bytes) / sum(data_compressed_bytes), 2) as compression_ratio
FROM system.parts
WHERE database = currentDatabase()
  AND active = 1
  AND table IN ('node_events', 'relationship_events')
GROUP BY table;

-- ----------------------------------------------------------------------------
-- Step 9: Query performance test
-- ----------------------------------------------------------------------------

-- Test query: Find all devices
SELECT count(*) 
FROM node_events 
WHERE has(labels, 'Device') 
  AND event_type = 'SNAPSHOT';

-- Test query: Find relationships between specific nodes
SELECT count(*) 
FROM relationship_events 
WHERE relationship_type = 'CONNECTED_TO' 
  AND event_type = 'SNAPSHOT';

-- Test query: Complex join (nodes + relationships)
SELECT 
    n1.entity_id as device_id,
    arrayElement(JSONExtractArrayRaw(n1.properties_after, 'name'), 1) as device_name,
    count(r.entity_id) as interface_count
FROM node_events n1
INNER JOIN relationship_events r ON r.source_id = n1.entity_id
WHERE has(n1.labels, 'Device')
  AND r.relationship_type = 'HAS_INTERFACE'
  AND n1.event_type = 'SNAPSHOT'
  AND r.event_type = 'SNAPSHOT'
GROUP BY n1.entity_id, device_name
ORDER BY interface_count DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Step 10: Final summary
-- ----------------------------------------------------------------------------
SELECT 
    'OPTIMIZATION COMPLETE' as status,
    now() as timestamp;

-- Total storage used
SELECT 
    formatReadableSize(sum(bytes)) as total_storage
FROM system.parts
WHERE database = currentDatabase()
  AND active = 1
  AND table IN ('node_events', 'relationship_events');

-- Total rows
SELECT 
    sum(rows) as total_rows
FROM system.parts
WHERE database = currentDatabase()
  AND active = 1
  AND table IN ('node_events', 'relationship_events');
