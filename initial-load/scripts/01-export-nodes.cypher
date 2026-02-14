// ============================================================================
// Neo4j Node Export Script
// ============================================================================
// Purpose: Export all nodes from Neo4j to CSV for initial load
// Output: /staging/nodes/*.csv files
// ============================================================================

// ----------------------------------------------------------------------------
// Option 1: Export ALL nodes to a single file (for small datasets < 1M nodes)
// ----------------------------------------------------------------------------
CALL apoc.export.csv.query(
  "MATCH (n) 
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/all_nodes.csv",
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
// Option 2: Export by LABEL (for large datasets > 1M nodes)
// ----------------------------------------------------------------------------
// This allows parallel processing and better memory management

// Export Device nodes
CALL apoc.export.csv.query(
  "MATCH (n:Device) 
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/devices.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export Interface nodes
CALL apoc.export.csv.query(
  "MATCH (n:Interface) 
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/interfaces.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export Location nodes
CALL apoc.export.csv.query(
  "MATCH (n:Location) 
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/locations.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export Product nodes
CALL apoc.export.csv.query(
  "MATCH (n:Product) 
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/products.csv",
  {
    batchSize: 10000,
    bulkImport: true,
    quotes: 'always'
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// ----------------------------------------------------------------------------
// Option 3: Export by ID RANGE (for very large datasets > 10M nodes)
// ----------------------------------------------------------------------------
// This allows even more parallelization

// Export nodes with ID range 0-1M
CALL apoc.export.csv.query(
  "MATCH (n) 
   WHERE id(n) >= 0 AND id(n) < 1000000
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/nodes_0_1m.csv",
  {
    batchSize: 10000,
    bulkImport: true
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// Export nodes with ID range 1M-2M
CALL apoc.export.csv.query(
  "MATCH (n) 
   WHERE id(n) >= 1000000 AND id(n) < 2000000
   RETURN 
     elementId(n) as entity_id,
     labels(n) as labels,
     properties(n) as properties,
     timestamp() as export_timestamp",
  "/staging/nodes/nodes_1m_2m.csv",
  {
    batchSize: 10000,
    bulkImport: true
  }
)
YIELD file, rows, time
RETURN file, rows, time;

// ... Continue for other ranges

// ----------------------------------------------------------------------------
// Validation Query: Count nodes by label
// ----------------------------------------------------------------------------
MATCH (n)
RETURN labels(n) as label, count(*) as count
ORDER BY count DESC;

// ----------------------------------------------------------------------------
// Export Metadata for Validation
// ----------------------------------------------------------------------------
CALL apoc.export.csv.query(
  "MATCH (n)
   WITH labels(n) as label, count(*) as count
   RETURN label, count
   ORDER BY count DESC",
  "/staging/nodes/metadata_counts.csv",
  {}
)
YIELD file, rows
RETURN file, rows;
