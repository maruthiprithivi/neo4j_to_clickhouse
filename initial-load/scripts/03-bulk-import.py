#!/usr/bin/env python3
"""
Neo4j to ClickHouse Initial Load - Bulk Import Script
======================================================
Purpose: Import CSV exports from Neo4j into ClickHouse for initial load
Usage: python3 03-bulk-import.py [--nodes] [--relationships] [--all]
"""

import clickhouse_connect
import pandas as pd
import glob
import json
import uuid
import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Any

# ============================================================================
# Configuration
# ============================================================================
CLICKHOUSE_HOST = 'localhost'
CLICKHOUSE_PORT = 8123
CLICKHOUSE_USER = 'default'
CLICKHOUSE_PASSWORD = ''

STAGING_DIR = Path('/home/ubuntu/neo4j-clickhouse-cdc/initial-load/staging')
BATCH_SIZE = 100000  # Rows per insert batch

# ============================================================================
# ClickHouse Client
# ============================================================================
def get_client():
    """Create ClickHouse client connection"""
    return clickhouse_connect.get_client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        username=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD
    )

# ============================================================================
# Node Import Functions
# ============================================================================
def import_nodes(client, file_pattern: str = "*.csv") -> int:
    """
    Import node CSV files to ClickHouse
    
    Args:
        client: ClickHouse client
        file_pattern: Glob pattern for CSV files (e.g., "devices*.csv")
    
    Returns:
        Total number of rows imported
    """
    csv_files = list((STAGING_DIR / 'nodes').glob(file_pattern))
    
    if not csv_files:
        print(f"[WARN] No files found matching: {file_pattern}")
        return 0

    print(f"\nImporting Nodes ({len(csv_files)} files)")
    print("=" * 70)
    
    total_rows = 0
    
    for csv_file in csv_files:
        print(f"\nProcessing: {csv_file.name}")

        try:
            # Read CSV in chunks to handle large files
            chunk_count = 0
            for chunk in pd.read_csv(csv_file, chunksize=BATCH_SIZE):
                # Transform to ClickHouse format
                data = []
                for _, row in chunk.iterrows():
                    # Parse labels (handle both string and list formats)
                    labels = []
                    if pd.notna(row.get('labels')):
                        try:
                            labels_raw = row['labels']
                            if isinstance(labels_raw, str):
                                # Handle JSON array string
                                if labels_raw.startswith('['):
                                    labels = json.loads(labels_raw)
                                else:
                                    # Handle comma-separated string
                                    labels = [l.strip() for l in labels_raw.split(',')]
                            elif isinstance(labels_raw, list):
                                labels = labels_raw
                        except:
                            labels = []

                    # Parse properties (ensure it's a valid JSON string)
                    properties_after = '{}'
                    if pd.notna(row.get('properties')):
                        try:
                            props = row['properties']
                            if isinstance(props, str):
                                # Validate JSON
                                json.loads(props)
                                properties_after = props
                            elif isinstance(props, dict):
                                properties_after = json.dumps(props)
                        except:
                            properties_after = '{}'

                    # Create event record
                    data.append({
                        'event_id': str(uuid.uuid4()),
                        'event_type': 'SNAPSHOT',
                        'event_timestamp': datetime.now(timezone.utc),
                        'entity_id': str(row['entity_id']),
                        'labels': labels,
                        'properties_before': '{}',
                        'properties_after': properties_after,
                        'metadata': json.dumps({
                            'source': 'initial_load',
                            'file': csv_file.name,
                            'timestamp': datetime.now(timezone.utc).isoformat()
                        })
                    })

                # Bulk insert
                if data:
                    client.insert('node_events', data)
                    total_rows += len(data)
                    chunk_count += 1
                    print(f"  [OK] Chunk {chunk_count}: {len(data):,} rows (Total: {total_rows:,})")

        except Exception as e:
            print(f"  [FAIL] Error processing {csv_file.name}: {e}")
            continue

    print(f"\n{'=' * 70}")
    print(f"[DONE] Nodes import complete: {total_rows:,} rows")
    return total_rows

# ============================================================================
# Relationship Import Functions
# ============================================================================
def import_relationships(client, file_pattern: str = "*.csv") -> int:
    """
    Import relationship CSV files to ClickHouse
    
    Args:
        client: ClickHouse client
        file_pattern: Glob pattern for CSV files
    
    Returns:
        Total number of rows imported
    """
    csv_files = list((STAGING_DIR / 'relationships').glob(file_pattern))
    
    if not csv_files:
        print(f"[WARN] No files found matching: {file_pattern}")
        return 0

    print(f"\nImporting Relationships ({len(csv_files)} files)")
    print("=" * 70)
    
    total_rows = 0
    
    for csv_file in csv_files:
        print(f"\nProcessing: {csv_file.name}")

        try:
            chunk_count = 0
            for chunk in pd.read_csv(csv_file, chunksize=BATCH_SIZE):
                data = []
                for _, row in chunk.iterrows():
                    # Parse properties
                    properties_after = '{}'
                    if pd.notna(row.get('properties')):
                        try:
                            props = row['properties']
                            if isinstance(props, str):
                                json.loads(props)  # Validate
                                properties_after = props
                            elif isinstance(props, dict):
                                properties_after = json.dumps(props)
                        except:
                            properties_after = '{}'

                    # Create event record
                    data.append({
                        'event_id': str(uuid.uuid4()),
                        'event_type': 'SNAPSHOT',
                        'event_timestamp': datetime.now(timezone.utc),
                        'entity_id': str(row['entity_id']),
                        'relationship_type': str(row['relationship_type']),
                        'source_id': str(row['source_id']),
                        'target_id': str(row['target_id']),
                        'properties_before': '{}',
                        'properties_after': properties_after,
                        'metadata': json.dumps({
                            'source': 'initial_load',
                            'file': csv_file.name,
                            'timestamp': datetime.now(timezone.utc).isoformat()
                        })
                    })

                # Bulk insert
                if data:
                    client.insert('relationship_events', data)
                    total_rows += len(data)
                    chunk_count += 1
                    print(f"  [OK] Chunk {chunk_count}: {len(data):,} rows (Total: {total_rows:,})")

        except Exception as e:
            print(f"  [FAIL] Error processing {csv_file.name}: {e}")
            continue

    print(f"\n{'=' * 70}")
    print(f"[DONE] Relationships import complete: {total_rows:,} rows")
    return total_rows

# ============================================================================
# Validation Functions
# ============================================================================
def validate_import(client):
    """Validate the imported data"""
    print(f"\nValidating Import")
    print("=" * 70)
    
    # Count nodes
    node_count = client.query("SELECT count(*) FROM node_events WHERE event_type = 'SNAPSHOT'").first_row[0]
    print(f"  Nodes (SNAPSHOT): {node_count:,}")
    
    # Count relationships
    rel_count = client.query("SELECT count(*) FROM relationship_events WHERE event_type = 'SNAPSHOT'").first_row[0]
    print(f"  Relationships (SNAPSHOT): {rel_count:,}")
    
    # Count by label
    print(f"\n  Nodes by Label:")
    label_counts = client.query("""
        SELECT arrayJoin(labels) as label, count(*) as count 
        FROM node_events 
        WHERE event_type = 'SNAPSHOT'
        GROUP BY label 
        ORDER BY count DESC 
        LIMIT 10
    """)
    for row in label_counts.result_rows:
        print(f"    {row[0]}: {row[1]:,}")
    
    # Count by relationship type
    print(f"\n  Relationships by Type:")
    type_counts = client.query("""
        SELECT relationship_type, count(*) as count 
        FROM relationship_events 
        WHERE event_type = 'SNAPSHOT'
        GROUP BY relationship_type 
        ORDER BY count DESC 
        LIMIT 10
    """)
    for row in type_counts.result_rows:
        print(f"    {row[0]}: {row[1]:,}")
    
    print(f"\n{'=' * 70}")

# ============================================================================
# Main Function
# ============================================================================
def main():
    parser = argparse.ArgumentParser(
        description='Import Neo4j CSV exports to ClickHouse'
    )
    parser.add_argument(
        '--nodes', 
        action='store_true',
        help='Import node CSV files'
    )
    parser.add_argument(
        '--relationships', 
        action='store_true',
        help='Import relationship CSV files'
    )
    parser.add_argument(
        '--all', 
        action='store_true',
        help='Import both nodes and relationships'
    )
    parser.add_argument(
        '--file-pattern',
        type=str,
        default='*.csv',
        help='File pattern to match (e.g., "devices*.csv")'
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=BATCH_SIZE,
        help=f'Batch size for inserts (default: {BATCH_SIZE})'
    )
    parser.add_argument(
        '--validate',
        action='store_true',
        help='Validate the import after completion'
    )
    
    args = parser.parse_args()
    
    # Update batch size if specified
    global BATCH_SIZE
    BATCH_SIZE = args.batch_size
    
    # If no specific option, default to --all
    if not (args.nodes or args.relationships or args.all):
        args.all = True
    
    print("\n" + "=" * 70)
    print("  Neo4j to ClickHouse - Initial Load (Bulk Import)")
    print("=" * 70)
    print(f"  ClickHouse: {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}")
    print(f"  Staging Dir: {STAGING_DIR}")
    print(f"  Batch Size: {BATCH_SIZE:,}")
    print(f"  File Pattern: {args.file_pattern}")
    print("=" * 70)
    
    # Create ClickHouse client
    try:
        client = get_client()
        print("[OK] Connected to ClickHouse")
    except Exception as e:
        print(f"✗ Failed to connect to ClickHouse: {e}")
        sys.exit(1)
    
    # Import nodes
    nodes_count = 0
    if args.nodes or args.all:
        nodes_count = import_nodes(client, args.file_pattern)
    
    # Import relationships
    rels_count = 0
    if args.relationships or args.all:
        rels_count = import_relationships(client, args.file_pattern)
    
    # Validation
    if args.validate:
        validate_import(client)
    
    # Summary
    print(f"\n" + "=" * 70)
    print(f"[DONE] Initial Load Complete!")
    print(f"  Nodes: {nodes_count:,}")
    print(f"  Relationships: {rels_count:,}")
    print(f"  Total: {nodes_count + rels_count:,}")
    print("=" * 70)
    print("\nNext Steps:")
    print("  1. Run validation: python3 03-bulk-import.py --validate")
    print("  2. Optimize tables: OPTIMIZE TABLE node_events FINAL;")
    print("  3. Start CDC consumers to process buffered events")
    print()

if __name__ == '__main__':
    main()
