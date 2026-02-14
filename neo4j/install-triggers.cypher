// Neo4j CDC Triggers Installation Script
// This script installs APOC triggers to capture node and relationship changes
//
// Note: This requires APOC Core to be installed
// The triggers will call the CDC bridge HTTP endpoint
// Must be run against the system database: cypher-shell -d system
//
// IMPORTANT: In Neo4j 5.x APOC triggers:
// - $createdNodes / $deletedNodes contain actual Node objects
// - $assignedNodeProperties[key] contains List<Map{node, key, old, new}>
// - $createdRelationships / $deletedRelationships contain actual Relationship objects
// - $assignedRelationshipProperties[key] contains List<Map{relationship, key, old, new}>
// - Headers for apoc.load.jsonParams must be null or {} (backtick-quoted keys
//   like Content-Type do not survive trigger storage/reparsing)
// - The CDC bridge must use request.get_json(force=True) to accept requests
//   without a Content-Type header

// ============================================================================
// NODE TRIGGERS
// ============================================================================

// Trigger for node creation (INSERT)
CALL apoc.trigger.install(
  'neo4j',
  'nodeInsertTrigger',
  'UNWIND $createdNodes AS node
   CALL apoc.load.jsonParams(
     "http://cdc-bridge:8000/cdc/node",
     null,
     apoc.convert.toJson({
       event_type: "INSERT",
       entity_id: toString(elementId(node)),
       labels: labels(node),
       properties_before: "{}",
       properties_after: apoc.convert.toJson(properties(node))
     }),
     "",
     {method: "POST"}
   )
   YIELD value
   RETURN count(*)',
  {phase: 'afterAsync'}
);

// Trigger for node property updates (UPDATE)
// Note: $assignedNodeProperties[key] returns List<Map{node, key, old, new}>
CALL apoc.trigger.install(
  'neo4j',
  'nodeUpdateTrigger',
  'UNWIND keys($assignedNodeProperties) AS key
   UNWIND $assignedNodeProperties[key] AS change
   WITH change.node AS node
   CALL apoc.load.jsonParams(
     "http://cdc-bridge:8000/cdc/node",
     null,
     apoc.convert.toJson({
       event_type: "UPDATE",
       entity_id: toString(elementId(node)),
       labels: labels(node),
       properties_before: "{}",
       properties_after: apoc.convert.toJson(properties(node))
     }),
     "",
     {method: "POST"}
   )
   YIELD value
   RETURN count(*)',
  {phase: 'afterAsync'}
);

// Trigger for node deletion (DELETE)
CALL apoc.trigger.install(
  'neo4j',
  'nodeDeleteTrigger',
  'UNWIND $deletedNodes AS node
   CALL apoc.load.jsonParams(
     "http://cdc-bridge:8000/cdc/node",
     null,
     apoc.convert.toJson({
       event_type: "DELETE",
       entity_id: toString(elementId(node)),
       labels: labels(node),
       properties_before: apoc.convert.toJson(properties(node)),
       properties_after: "{}"
     }),
     "",
     {method: "POST"}
   )
   YIELD value
   RETURN count(*)',
  {phase: 'afterAsync'}
);

// ============================================================================
// RELATIONSHIP TRIGGERS
// ============================================================================

// Trigger for relationship creation (INSERT)
CALL apoc.trigger.install(
  'neo4j',
  'relationshipInsertTrigger',
  'UNWIND $createdRelationships AS rel
   CALL apoc.load.jsonParams(
     "http://cdc-bridge:8000/cdc/relationship",
     null,
     apoc.convert.toJson({
       event_type: "INSERT",
       entity_id: toString(elementId(rel)),
       relationship_type: type(rel),
       source_id: toString(elementId(startNode(rel))),
       target_id: toString(elementId(endNode(rel))),
       properties_before: "{}",
       properties_after: apoc.convert.toJson(properties(rel))
     }),
     "",
     {method: "POST"}
   )
   YIELD value
   RETURN count(*)',
  {phase: 'afterAsync'}
);

// Trigger for relationship property updates (UPDATE)
// Note: $assignedRelationshipProperties[key] returns List<Map{relationship, key, old, new}>
CALL apoc.trigger.install(
  'neo4j',
  'relationshipUpdateTrigger',
  'UNWIND keys($assignedRelationshipProperties) AS key
   UNWIND $assignedRelationshipProperties[key] AS change
   WITH change.relationship AS rel
   CALL apoc.load.jsonParams(
     "http://cdc-bridge:8000/cdc/relationship",
     null,
     apoc.convert.toJson({
       event_type: "UPDATE",
       entity_id: toString(elementId(rel)),
       relationship_type: type(rel),
       source_id: toString(elementId(startNode(rel))),
       target_id: toString(elementId(endNode(rel))),
       properties_before: "{}",
       properties_after: apoc.convert.toJson(properties(rel))
     }),
     "",
     {method: "POST"}
   )
   YIELD value
   RETURN count(*)',
  {phase: 'afterAsync'}
);

// Trigger for relationship deletion (DELETE)
CALL apoc.trigger.install(
  'neo4j',
  'relationshipDeleteTrigger',
  'UNWIND $deletedRelationships AS rel
   CALL apoc.load.jsonParams(
     "http://cdc-bridge:8000/cdc/relationship",
     null,
     apoc.convert.toJson({
       event_type: "DELETE",
       entity_id: toString(elementId(rel)),
       relationship_type: type(rel),
       source_id: toString(elementId(startNode(rel))),
       target_id: toString(elementId(endNode(rel))),
       properties_before: apoc.convert.toJson(properties(rel)),
       properties_after: "{}"
     }),
     "",
     {method: "POST"}
   )
   YIELD value
   RETURN count(*)',
  {phase: 'afterAsync'}
);
