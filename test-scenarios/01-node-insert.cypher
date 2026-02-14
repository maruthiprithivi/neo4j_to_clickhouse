// Test Scenario 1: Node Insert
// This test creates new nodes to trigger INSERT events

// Create a single person node
CREATE (p:Person {
    name: 'Alice Johnson',
    age: 30,
    email: 'alice@example.com',
    city: 'New York'
})
RETURN p;

// Create multiple person nodes
UNWIND [
    {name: 'Bob Smith', age: 25, email: 'bob@example.com', city: 'San Francisco'},
    {name: 'Carol White', age: 35, email: 'carol@example.com', city: 'Chicago'},
    {name: 'David Brown', age: 28, email: 'david@example.com', city: 'Seattle'}
] AS person
CREATE (p:Person)
SET p = person
RETURN p;

// Create nodes with multiple labels
CREATE (c:Company:Organization {
    name: 'Tech Corp',
    founded: 2010,
    industry: 'Technology',
    employees: 500
})
RETURN c;

// Create a product node
CREATE (prod:Product {
    name: 'Widget Pro',
    price: 99.99,
    category: 'Electronics',
    inStock: true
})
RETURN prod;

// Wait a moment to see the events
CALL apoc.util.sleep(1000);

// Verify nodes were created
MATCH (n)
WHERE n.name IN ['Alice Johnson', 'Bob Smith', 'Carol White', 'David Brown', 'Tech Corp', 'Widget Pro']
RETURN labels(n) AS labels, n.name AS name, properties(n) AS properties;
