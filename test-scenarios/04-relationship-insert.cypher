// Test Scenario 4: Relationship Insert
// This test creates relationships to trigger INSERT events

// Create a simple relationship
MATCH (a:Person {name: 'Alice Johnson'}), (b:Person {name: 'Bob Smith'})
CREATE (a)-[r:KNOWS {since: 2020, strength: 'strong'}]->(b)
RETURN a.name, type(r), b.name, r.since;

// Create multiple relationships
MATCH (alice:Person {name: 'Alice Johnson'})
MATCH (carol:Person {name: 'Carol White'})
MATCH (david:Person {name: 'David Brown'})
CREATE (alice)-[:KNOWS {since: 2021, context: 'work'}]->(carol),
       (alice)-[:KNOWS {since: 2019, context: 'college'}]->(david),
       (carol)-[:KNOWS {since: 2022, context: 'conference'}]->(david)
RETURN count(*) AS relationships_created;

// Create relationship with rich properties
MATCH (alice:Person {name: 'Alice Johnson'}), (company:Company {name: 'Tech Corp'})
CREATE (alice)-[r:WORKS_AT {
    startDate: date('2020-01-15'),
    position: 'Senior Engineer',
    department: 'Engineering',
    salary: 120000,
    remote: true
}]->(company)
RETURN alice.name, type(r), company.name;

// Create relationships between people and company
MATCH (bob:Person {name: 'Bob Smith'}), (company:Company {name: 'Tech Corp'})
CREATE (bob)-[:WORKS_AT {
    startDate: date('2021-06-01'),
    position: 'Junior Developer',
    department: 'Engineering',
    salary: 80000
}]->(company);

MATCH (carol:Person {name: 'Carol White'}), (company:Company {name: 'Tech Corp'})
CREATE (carol)-[:WORKS_AT {
    startDate: date('2019-03-10'),
    position: 'Product Manager',
    department: 'Product',
    salary: 110000
}]->(company);

// Create bidirectional relationships
MATCH (bob:Person {name: 'Bob Smith'}), (carol:Person {name: 'Carol White'})
CREATE (bob)-[:COLLABORATES_WITH {project: 'Project X', since: 2022}]->(carol),
       (carol)-[:COLLABORATES_WITH {project: 'Project X', since: 2022}]->(bob);

// Wait a moment to see the events
CALL apoc.util.sleep(1000);

// Verify relationships
MATCH (a)-[r]->(b)
WHERE a:Person OR a:Company
RETURN labels(a)[0] AS from_type, a.name AS from_name,
       type(r) AS relationship_type,
       labels(b)[0] AS to_type, b.name AS to_name,
       properties(r) AS properties;
