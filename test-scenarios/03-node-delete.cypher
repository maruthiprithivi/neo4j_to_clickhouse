// Test Scenario 3: Node Delete
// This test deletes nodes to trigger DELETE events

// First, create some test nodes to delete
CREATE (t1:TestNode {name: 'ToDelete1', value: 100}),
       (t2:TestNode {name: 'ToDelete2', value: 200}),
       (t3:TestNode {name: 'ToDelete3', value: 300})
RETURN t1, t2, t3;

// Wait for insert events
CALL apoc.util.sleep(1000);

// Delete a single node
MATCH (t:TestNode {name: 'ToDelete1'})
DELETE t;

// Delete multiple nodes with WHERE clause
MATCH (t:TestNode)
WHERE t.value >= 200
DELETE t;

// Wait a moment to see the delete events
CALL apoc.util.sleep(1000);

// Verify deletions
MATCH (t:TestNode)
RETURN count(t) AS remaining_test_nodes;

// Create and immediately delete (for testing)
CREATE (temp:TempNode {id: 'temp123'})
WITH temp
CALL apoc.util.sleep(500)
WITH temp
DELETE temp;

// Delete a product node
MATCH (p:Product {name: 'Widget Pro'})
DELETE p;

// Verify final state
MATCH (n)
WHERE n:TestNode OR n:TempNode OR (n:Product AND n.name = 'Widget Pro')
RETURN count(n) AS should_be_zero;
