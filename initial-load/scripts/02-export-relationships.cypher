// ============================================================================
// Neo4j Relationship Export Script
// ============================================================================
// Purpose: Export all relationships from Neo4j to CSV for initial load
// Output: /staging/relationships/*.csv files
// ============================================================================

// ----------------------------------------------------------------------------
// Option 1: Export ALL relationships to a single file (< 5M relationships)
// ----------------------------------------------------------------------------
CALL apoc.export.csv.query(
  "MATCH (a)-[r]->(b)
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/all_relationships.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always',
    useTypes: true
  }
)
YIELD file, source, format, nodes, relationships, properties, time, rows
RETURN file, rows, time;

// ----------------------------------------------------------------------------
// Option 2: Export by RELATIONSHIP TYPE (for large datasets)
// ----------------------------------------------------------------------------

// Export CONNECTED_TO relationships
CALL apoc.export.csv.query(
  "MATCH (a)-[r:CONNECTED_TO]->(b)
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/connected_to.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export HAS_INTERFACE relationships
CALL apoc.export.csv.query(
  "MATCH (a)-[r:HAS_INTERFACE]->(b)
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/has_interface.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export LOCATED_AT relationships
CALL apoc.export.csv.query(
  "MATCH (a)-[r:LOCATED_AT]->(b)
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/located_at.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export CONTAINS relationships (for BOM/Inventory)
CALL apoc.export.csv.query(
  "MATCH (a)-[r:CONTAINS]->(b)
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/contains.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// ----------------------------------------------------------------------------
// Option 3: Export by ID RANGE (for very large datasets > 10M relationships)
// ----------------------------------------------------------------------------

// Export relationships with ID range 0-1M
CALL apoc.export.csv.query(
  "MATCH (a)-[r]->(b)
   WHERE id(r) >= 0 AND id(r) < 1000000
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/rels_0_1m.csv",
  {
    batchSize: 10000,
    bulkImport: true
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export relationships with ID range 1M-2M
CALL apoc.export.csv.query(
  "MATCH (a)-[r]->(b)
   WHERE id(r) >= 1000000 AND id(r) < 2000000
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     elementId(b) as target_id,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/rels_1m_2m.csv",
  {
    batchSize: 10000,
    bulkImport: true
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// ... Continue for other ranges

// ----------------------------------------------------------------------------
// Validation Query: Count relationships by type
// ----------------------------------------------------------------------------
MATCH ()-[r]->()
RETURN type(r) as type, count(*) as count
ORDER BY count DESC;

// ----------------------------------------------------------------------------
// Export Metadata for Validation
// ----------------------------------------------------------------------------
CALL apoc.export.csv.query(
  "MATCH ()-[r]->()
   WITH type(r) as type, count(*) as count
   RETURN type, count
   ORDER BY count DESC",
  "/staging/relationships/metadata_counts.csv",
  {}
)
YIELD file, rows
RETURN file, rows;

// ----------------------------------------------------------------------------
// Advanced: Export with source/target labels (for better filtering)
// ----------------------------------------------------------------------------
CALL apoc.export.csv.query(
  "MATCH (a)-[r]->(b)
   RETURN 
     elementId(r) as entity_id,
     type(r) as relationship_type,
     elementId(a) as source_id,
     labels(a) as source_labels,
     elementId(b) as target_id,
     labels(b) as target_labels,
     properties(r) as properties,
     timestamp() as export_timestamp",
  "/staging/relationships/relationships_with_labels.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;
