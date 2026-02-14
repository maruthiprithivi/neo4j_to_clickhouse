// Test Scenario 6: Relationship Delete
// This test deletes relationships to trigger DELETE events

// First, create some test relationships to delete
MATCH (alice:Person {name: 'Alice Johnson'}), (bob:Person {name: 'Bob Smith'})
CREATE (alice)-[r:TEST_REL {id: 'test1', value: 100}]->(bob)
RETURN r;

MATCH (carol:Person {name: 'Carol White'}), (david:Person {name: 'David Brown'})
CREATE (carol)-[r:TEST_REL {id: 'test2', value: 200}]->(david)
RETURN r;

// Wait for insert events
CALL apoc.util.sleep(1000);

// Delete a single relationship
MATCH (alice:Person {name: 'Alice Johnson'})-[r:TEST_REL]->(bob:Person {name: 'Bob Smith'})
DELETE r;

// Delete multiple relationships with WHERE clause
MATCH ()-[r:TEST_REL]->()
WHERE r.value >= 200
DELETE r;

// Wait a moment to see the delete events
CALL apoc.util.sleep(1000);

// Verify deletions
MATCH ()-[r:TEST_REL]->()
RETURN count(r) AS remaining_test_relationships;

// Delete COLLABORATES_WITH relationships
MATCH (bob:Person {name: 'Bob Smith'})-[r:COLLABORATES_WITH]-(carol:Person {name: 'Carol White'})
DELETE r;

// Delete all KNOWS relationships from Alice
MATCH (alice:Person {name: 'Alice Johnson'})-[r:KNOWS]->()
DELETE r;

// Wait for events
CALL apoc.util.sleep(1000);

// Verify final state
MATCH (alice:Person {name: 'Alice Johnson'})-[r:KNOWS]->()
RETURN count(r) AS alice_knows_count;

MATCH ()-[r:COLLABORATES_WITH]-()
RETURN count(r) AS collaborates_count;
