// Test Scenario 2: Node Update
// This test updates existing node properties to trigger UPDATE events

// Update a single property
MATCH (p:Person {name: 'Alice Johnson'})
SET p.age = 31
RETURN p;

// Update multiple properties
MATCH (p:Person {name: 'Bob Smith'})
SET p.age = 26, p.city = 'Los Angeles', p.department = 'Engineering'
RETURN p;

// Add new property to existing node
MATCH (p:Person {name: 'Carol White'})
SET p.phone = '+1-555-0123', p.status = 'active'
RETURN p;

// Update with computed values
MATCH (c:Company {name: 'Tech Corp'})
SET c.employees = c.employees + 50,
    c.lastUpdated = datetime()
RETURN c;

// Bulk update
MATCH (p:Person)
WHERE p.age < 30
SET p.category = 'young_professional'
RETURN count(p) AS updated_count;

// Update with REMOVE (set to null)
MATCH (p:Person {name: 'David Brown'})
REMOVE p.email
SET p.contactPreference = 'phone'
RETURN p;

// Wait a moment to see the events
CALL apoc.util.sleep(1000);

// Verify updates
MATCH (p:Person)
RETURN p.name AS name, p.age AS age, p.city AS city, 
       p.department AS department, p.category AS category;
