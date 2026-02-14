// Test Scenario 5: Relationship Update
// This test updates relationship properties to trigger UPDATE events

// Update a single relationship property
MATCH (alice:Person {name: 'Alice Johnson'})-[r:KNOWS]->(bob:Person {name: 'Bob Smith'})
SET r.strength = 'very strong', r.lastContact = datetime()
RETURN alice.name, type(r), bob.name, r.strength;

// Update multiple properties on a relationship
MATCH (alice:Person {name: 'Alice Johnson'})-[r:WORKS_AT]->(company:Company)
SET r.salary = 130000,
    r.position = 'Lead Engineer',
    r.promotionDate = date('2023-01-01')
RETURN alice.name, r.position, r.salary;

// Add new properties to existing relationship
MATCH (bob:Person {name: 'Bob Smith'})-[r:WORKS_AT]->(company:Company)
SET r.performanceRating = 4.5,
    r.nextReviewDate = date('2024-06-01'),
    r.benefits = ['health', 'dental', '401k']
RETURN bob.name, r.position, r.performanceRating;

// Update with computed values
MATCH (carol:Person)-[r:WORKS_AT]->(company:Company)
SET r.salary = r.salary * 1.05,
    r.lastSalaryUpdate = date()
RETURN carol.name, r.salary;

// Bulk update relationships
MATCH ()-[r:KNOWS]->()
SET r.verified = true, r.verificationDate = datetime()
RETURN count(r) AS updated_relationships;

// Update relationship by removing property
MATCH (bob:Person)-[r:COLLABORATES_WITH]->(carol:Person)
REMOVE r.project
SET r.status = 'completed', r.endDate = date()
RETURN bob.name, type(r), carol.name, r.status;

// Wait a moment to see the events
CALL apoc.util.sleep(1000);

// Verify updates
MATCH (a:Person)-[r:WORKS_AT]->(c:Company)
RETURN a.name AS employee, r.position AS position, 
       r.salary AS salary, r.performanceRating AS rating;

MATCH (a:Person)-[r:KNOWS]->(b:Person)
RETURN a.name AS from, b.name AS to, 
       r.strength AS strength, r.verified AS verified;
