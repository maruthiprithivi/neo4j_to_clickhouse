// Neo4j CDC Triggers Removal Script
// This script removes all CDC triggers

// Remove node triggers
CALL apoc.trigger.remove('neo4j', 'nodeInsertTrigger');
CALL apoc.trigger.remove('neo4j', 'nodeUpdateTrigger');
CALL apoc.trigger.remove('neo4j', 'nodeDeleteTrigger');

// Remove relationship triggers
CALL apoc.trigger.remove('neo4j', 'relationshipInsertTrigger');
CALL apoc.trigger.remove('neo4j', 'relationshipUpdateTrigger');
CALL apoc.trigger.remove('neo4j', 'relationshipDeleteTrigger');

// Verify all triggers are removed
CALL apoc.trigger.list();
