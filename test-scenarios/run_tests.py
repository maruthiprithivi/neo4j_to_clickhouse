#!/usr/bin/env python3
"""
Test Runner for Neo4j CDC to ClickHouse
Executes test scenarios and verifies data in ClickHouse
"""

import os
import sys
import time
from neo4j import GraphDatabase
import clickhouse_connect

# Configuration
NEO4J_URI = os.getenv('NEO4J_URI', 'bolt://localhost:7687')
NEO4J_USER = os.getenv('NEO4J_USER', 'neo4j')
NEO4J_PASSWORD = os.getenv('NEO4J_PASSWORD', 'password123')

CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'localhost')
CLICKHOUSE_PORT = int(os.getenv('CLICKHOUSE_PORT', '8123'))
CLICKHOUSE_DATABASE = os.getenv('CLICKHOUSE_DATABASE', 'cdc')


def run_cypher_file(driver, filepath):
    """Execute a Cypher file in Neo4j"""
    print(f"\n{'='*60}")
    print(f"Running: {os.path.basename(filepath)}")
    print('='*60)
    
    with open(filepath, 'r') as f:
        cypher_content = f.read()
    
    # Split by semicolons and filter out comments
    statements = []
    for stmt in cypher_content.split(';'):
        stmt = stmt.strip()
        # Remove single-line comments
        lines = [line for line in stmt.split('\n') 
                if not line.strip().startswith('//')]
        stmt = '\n'.join(lines).strip()
        if stmt:
            statements.append(stmt)
    
    with driver.session() as session:
        for i, statement in enumerate(statements, 1):
            if not statement:
                continue
            try:
                result = session.run(statement)
                # Try to consume results
                try:
                    records = list(result)
                    if records:
                        print(f"  Statement {i}: {len(records)} records returned")
                        # Print first few records
                        for record in records[:3]:
                            print(f"    {dict(record)}")
                except Exception:
                    print(f"  Statement {i}: Executed successfully")
            except Exception as e:
                print(f"  Statement {i}: Error - {e}")
                # Continue with next statement
    
    print(f"Completed: {os.path.basename(filepath)}")


def query_clickhouse(client, query, description):
    """Execute a query in ClickHouse and display results"""
    print(f"\n{description}")
    print('-'*60)
    try:
        result = client.query(query)
        if result.result_rows:
            for row in result.result_rows:
                print(f"  {row}")
            print(f"Total rows: {len(result.result_rows)}")
        else:
            print("  No results")
    except Exception as e:
        print(f"  Error: {e}")


def verify_clickhouse_data(client):
    """Verify CDC data in ClickHouse"""
    print(f"\n{'='*60}")
    print("VERIFYING DATA IN CLICKHOUSE")
    print('='*60)
    
    # Check nodes CDC
    query_clickhouse(
        client,
        "SELECT count() as total, event_type, countDistinct(entity_id) as unique_entities FROM cdc.nodes_cdc GROUP BY event_type ORDER BY event_type",
        "Node CDC Events Summary:"
    )
    
    query_clickhouse(
        client,
        "SELECT event_type, entity_id, labels, properties_after FROM cdc.nodes_cdc ORDER BY event_timestamp DESC LIMIT 10",
        "Latest Node CDC Events:"
    )
    
    # Check relationships CDC
    query_clickhouse(
        client,
        "SELECT count() as total, event_type, countDistinct(entity_id) as unique_entities FROM cdc.relationships_cdc GROUP BY event_type ORDER BY event_type",
        "Relationship CDC Events Summary:"
    )
    
    query_clickhouse(
        client,
        "SELECT event_type, relationship_type, source_id, target_id, properties_after FROM cdc.relationships_cdc ORDER BY event_timestamp DESC LIMIT 10",
        "Latest Relationship CDC Events:"
    )
    
    # Overall statistics
    query_clickhouse(
        client,
        "SELECT 'nodes' as type, count() as total FROM cdc.nodes_cdc UNION ALL SELECT 'relationships' as type, count() as total FROM cdc.relationships_cdc",
        "Overall CDC Statistics:"
    )


def main():
    """Main test execution"""
    print("Neo4j to ClickHouse CDC Test Suite")
    print("="*60)
    
    # Connect to Neo4j
    print(f"\nConnecting to Neo4j at {NEO4J_URI}...")
    neo4j_driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, NEO4J_PASSWORD))
    
    try:
        neo4j_driver.verify_connectivity()
        print("[OK] Connected to Neo4j")
    except Exception as e:
        print(f"[FAIL] Failed to connect to Neo4j: {e}")
        sys.exit(1)
    
    # Connect to ClickHouse
    print(f"\nConnecting to ClickHouse at {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}...")
    try:
        ch_client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DATABASE
        )
        ch_client.command("SELECT 1")
        print("[OK] Connected to ClickHouse")
    except Exception as e:
        print(f"[FAIL] Failed to connect to ClickHouse: {e}")
        sys.exit(1)
    
    # Get test scenario files
    test_dir = os.path.dirname(os.path.abspath(__file__))
    test_files = sorted([
        os.path.join(test_dir, f) 
        for f in os.listdir(test_dir) 
        if f.endswith('.cypher') and f[0].isdigit()
    ])
    
    if not test_files:
        print("\n✗ No test scenario files found!")
        sys.exit(1)
    
    print(f"\nFound {len(test_files)} test scenarios")
    
    # Run each test scenario
    for test_file in test_files:
        run_cypher_file(neo4j_driver, test_file)
        # Wait for CDC events to propagate
        print("  Waiting for CDC events to propagate...")
        time.sleep(3)
    
    # Wait a bit more for all events to be processed
    print("\nWaiting for final CDC events to propagate...")
    time.sleep(5)
    
    # Verify data in ClickHouse
    verify_clickhouse_data(ch_client)
    
    # Cleanup
    neo4j_driver.close()
    print("\n" + "="*60)
    print("Test suite completed!")
    print("="*60)


if __name__ == '__main__':
    main()
