// Test Scenario 7: Bulk Operations
// This test performs bulk operations to test CDC performance and batching

// Bulk insert nodes
UNWIND range(1, 50) AS i
CREATE (p:BulkPerson {
    id: 'bulk_' + i,
    name: 'Person ' + i,
    age: 20 + (i % 50),
    email: 'person' + i + '@example.com',
    createdAt: datetime()
})
RETURN count(p) AS created_count;

// Wait for events
CALL apoc.util.sleep(2000);

// Bulk update
MATCH (p:BulkPerson)
WHERE p.age < 30
SET p.category = 'young',
    p.discount = 0.15
RETURN count(p) AS updated_count;

// Wait for events
CALL apoc.util.sleep(2000);

// Bulk create relationships
MATCH (p1:BulkPerson)
WHERE toInteger(split(p1.id, '_')[1]) <= 25
MATCH (p2:BulkPerson)
WHERE toInteger(split(p2.id, '_')[1]) > 25
WITH p1, p2
WHERE toInteger(split(p1.id, '_')[1]) + 25 = toInteger(split(p2.id, '_')[1])
CREATE (p1)-[r:CONNECTED_TO {
    strength: rand(),
    createdAt: datetime()
}]->(p2)
RETURN count(r) AS relationships_created;

// Wait for events
CALL apoc.util.sleep(2000);

// Bulk update relationships
MATCH ()-[r:CONNECTED_TO]->()
WHERE r.strength < 0.5
SET r.status = 'weak', r.priority = 'low'
RETURN count(r) AS updated_relationships;

// Wait for events
CALL apoc.util.sleep(2000);

// Bulk delete relationships
MATCH ()-[r:CONNECTED_TO]->()
WHERE r.strength < 0.3
DELETE r
RETURN count(r) AS deleted_relationships;

// Wait for events
CALL apoc.util.sleep(2000);

// Bulk delete nodes (delete half)
MATCH (p:BulkPerson)
WHERE toInteger(split(p.id, '_')[1]) > 25
DETACH DELETE p
RETURN count(p) AS deleted_nodes;

// Wait for events
CALL apoc.util.sleep(2000);

// Verify final state
MATCH (p:BulkPerson)
RETURN count(p) AS remaining_bulk_persons;

MATCH ()-[r:CONNECTED_TO]->()
RETURN count(r) AS remaining_connections;

// Summary statistics
MATCH (p:BulkPerson)
RETURN 
    count(p) AS total_nodes,
    avg(p.age) AS avg_age,
    collect(DISTINCT p.category) AS categories;
