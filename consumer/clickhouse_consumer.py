#!/usr/bin/env python3
"""
ClickHouse CDC Consumer
Consumes CDC events from Kafka and writes to ClickHouse
Production-ready with error handling, batching, and metrics
"""

import os
import json
import time
import signal
import sys
from datetime import datetime
from typing import List, Dict, Any
from kafka import KafkaConsumer
from clickhouse_driver import Client
from dotenv import load_dotenv

load_dotenv()

# Configuration
KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'kafka:29092')
CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
CLICKHOUSE_PORT = int(os.getenv('CLICKHOUSE_PORT', '9000'))
CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'default')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', 'clickhouse123')
CLICKHOUSE_DATABASE = os.getenv('CLICKHOUSE_DATABASE', 'neo4j_cdc')

BATCH_SIZE = int(os.getenv('BATCH_SIZE', '100'))
BATCH_TIMEOUT = int(os.getenv('BATCH_TIMEOUT', '5'))  # seconds

# Global flag for graceful shutdown
running = True

def signal_handler(signum, frame):
    """Handle shutdown signals gracefully"""
    global running
    print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
    running = False

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


class ClickHouseConsumer:
    """Consumer that reads from Kafka and writes to ClickHouse"""
    
    def __init__(self):
        print("="*60)
        print("ClickHouse CDC Consumer")
        print("="*60)
        
        # Initialize ClickHouse client
        print(f"Connecting to ClickHouse at {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}...")
        self.clickhouse = Client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            user=CLICKHOUSE_USER,
            password=CLICKHOUSE_PASSWORD,
            database=CLICKHOUSE_DATABASE,
            settings={'use_numpy': False}
        )
        
        # Test connection
        result = self.clickhouse.execute('SELECT 1')
        print(f"✓ ClickHouse connected: {result}")
        
        # Initialize Kafka consumers
        print(f"Connecting to Kafka at {KAFKA_BROKER}...")
        
        self.node_consumer = KafkaConsumer(
            'neo4j.nodes',
            bootstrap_servers=[KAFKA_BROKER],
            group_id='clickhouse-node-consumer',
            auto_offset_reset='earliest',
            enable_auto_commit=False,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            max_poll_records=BATCH_SIZE
        )
        
        self.rel_consumer = KafkaConsumer(
            'neo4j.relationships',
            bootstrap_servers=[KAFKA_BROKER],
            group_id='clickhouse-rel-consumer',
            auto_offset_reset='earliest',
            enable_auto_commit=False,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            max_poll_records=BATCH_SIZE
        )
        
        print("✓ Kafka consumers created")
        
        # Metrics
        self.nodes_processed = 0
        self.rels_processed = 0
        self.errors = 0
        self.start_time = time.time()
    
    def parse_timestamp(self, timestamp_str: str) -> datetime:
        """Parse ISO timestamp to datetime"""
        try:
            # Handle both formats: with and without microseconds
            if '.' in timestamp_str:
                return datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            else:
                return datetime.strptime(timestamp_str, '%Y-%m-%dT%H:%M:%SZ')
        except Exception as e:
            print(f"⚠️  Error parsing timestamp {timestamp_str}: {e}")
            return datetime.utcnow()
    
    def insert_nodes(self, events: List[Dict[str, Any]]):
        """Insert node events into ClickHouse"""
        if not events:
            return
        
        # Prepare data for bulk insert
        data = []
        for event in events:
            try:
                data.append((
                    event['event_id'],
                    event['tx_id'],
                    event['operation'],
                    event['labels'],
                    event['node_id'],
                    event['properties'],
                    self.parse_timestamp(event['timestamp'])
                ))
            except Exception as e:
                print(f"⚠️  Error preparing node event: {e}")
                print(f"   Event: {event}")
                self.errors += 1
        
        if not data:
            return
        
        # Bulk insert
        try:
            self.clickhouse.execute(
                '''
                INSERT INTO node_changes 
                (event_id, tx_id, operation, labels, node_id, properties, event_time)
                VALUES
                ''',
                data
            )
            self.nodes_processed += len(data)
            print(f"✓ Inserted {len(data)} node events (total: {self.nodes_processed})")
        except Exception as e:
            print(f"❌ Error inserting nodes: {e}")
            self.errors += 1
    
    def insert_relationships(self, events: List[Dict[str, Any]]):
        """Insert relationship events into ClickHouse"""
        if not events:
            return
        
        # Prepare data for bulk insert
        data = []
        for event in events:
            try:
                data.append((
                    event['event_id'],
                    event['tx_id'],
                    event['operation'],
                    event['rel_type'],
                    event['rel_id'],
                    event['from_node_id'],
                    event['to_node_id'],
                    event['properties'],
                    self.parse_timestamp(event['timestamp'])
                ))
            except Exception as e:
                print(f"⚠️  Error preparing relationship event: {e}")
                print(f"   Event: {event}")
                self.errors += 1
        
        if not data:
            return
        
        # Bulk insert
        try:
            self.clickhouse.execute(
                '''
                INSERT INTO relationship_changes 
                (event_id, tx_id, operation, rel_type, rel_id, from_node_id, to_node_id, properties, event_time)
                VALUES
                ''',
                data
            )
            self.rels_processed += len(data)
            print(f"✓ Inserted {len(data)} relationship events (total: {self.rels_processed})")
        except Exception as e:
            print(f"❌ Error inserting relationships: {e}")
            self.errors += 1
    
    def consume_nodes(self):
        """Consume and process node events"""
        batch = []
        batch_start = time.time()
        
        for message in self.node_consumer:
            if not running:
                break
                
            batch.append(message.value)
            
            # Insert when batch is full or timeout reached
            if len(batch) >= BATCH_SIZE or (time.time() - batch_start) >= BATCH_TIMEOUT:
                self.insert_nodes(batch)
                self.node_consumer.commit()
                batch = []
                batch_start = time.time()
        
        # Insert remaining events
        if batch:
            self.insert_nodes(batch)
            self.node_consumer.commit()
    
    def consume_relationships(self):
        """Consume and process relationship events"""
        batch = []
        batch_start = time.time()
        
        for message in self.rel_consumer:
            if not running:
                break
                
            batch.append(message.value)
            
            # Insert when batch is full or timeout reached
            if len(batch) >= BATCH_SIZE or (time.time() - batch_start) >= BATCH_TIMEOUT:
                self.insert_relationships(batch)
                self.rel_consumer.commit()
                batch = []
                batch_start = time.time()
        
        # Insert remaining events
        if batch:
            self.insert_relationships(batch)
            self.rel_consumer.commit()
    
    def run(self):
        """Main consumer loop - poll both topics"""
        print("\n🚀 Starting consumption...")
        print(f"   Batch size: {BATCH_SIZE}")
        print(f"   Batch timeout: {BATCH_TIMEOUT}s\n")
        
        node_batch = []
        rel_batch = []
        batch_start = time.time()
        last_stats = time.time()
        
        while running:
            try:
                # Poll node events
                node_messages = self.node_consumer.poll(timeout_ms=1000, max_records=BATCH_SIZE)
                for topic_partition, messages in node_messages.items():
                    node_batch.extend([msg.value for msg in messages])
                
                # Poll relationship events
                rel_messages = self.rel_consumer.poll(timeout_ms=1000, max_records=BATCH_SIZE)
                for topic_partition, messages in rel_messages.items():
                    rel_batch.extend([msg.value for msg in messages])
                
                # Insert batches if full or timeout reached
                now = time.time()
                should_flush = (now - batch_start) >= BATCH_TIMEOUT
                
                if len(node_batch) >= BATCH_SIZE or (node_batch and should_flush):
                    self.insert_nodes(node_batch)
                    self.node_consumer.commit()
                    node_batch = []
                
                if len(rel_batch) >= BATCH_SIZE or (rel_batch and should_flush):
                    self.insert_relationships(rel_batch)
                    self.rel_consumer.commit()
                    rel_batch = []
                
                if should_flush:
                    batch_start = time.time()
                
                # Print stats every 30 seconds
                if (now - last_stats) >= 30:
                    self.print_stats()
                    last_stats = now
                
            except Exception as e:
                print(f"❌ Error in main loop: {e}")
                self.errors += 1
                time.sleep(1)
        
        # Final flush
        if node_batch:
            self.insert_nodes(node_batch)
            self.node_consumer.commit()
        if rel_batch:
            self.insert_relationships(rel_batch)
            self.rel_consumer.commit()
        
        print("\n✓ Consumer stopped gracefully")
        self.print_stats()
    
    def print_stats(self):
        """Print consumption statistics"""
        elapsed = time.time() - self.start_time
        print(f"\n📊 Statistics:")
        print(f"   Nodes processed: {self.nodes_processed}")
        print(f"   Relationships processed: {self.rels_processed}")
        print(f"   Errors: {self.errors}")
        print(f"   Uptime: {elapsed:.1f}s")
        if elapsed > 0:
            print(f"   Throughput: {(self.nodes_processed + self.rels_processed) / elapsed:.1f} events/sec")
        print()
    
    def close(self):
        """Close connections"""
        print("Closing consumers...")
        self.node_consumer.close()
        self.rel_consumer.close()
        self.clickhouse.disconnect()
        print("✓ Connections closed")


def wait_for_services():
    """Wait for Kafka and ClickHouse to be ready"""
    import socket
    
    def wait_for_port(host, port, service_name, timeout=60):
        print(f"Waiting for {service_name} at {host}:{port}...")
        start = time.time()
        while time.time() - start < timeout:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                result = sock.connect_ex((host, port))
                sock.close()
                if result == 0:
                    print(f"✓ {service_name} is ready")
                    return True
            except:
                pass
            time.sleep(2)
        print(f"❌ Timeout waiting for {service_name}")
        return False
    
    kafka_host, kafka_port = KAFKA_BROKER.split(':')
    if not wait_for_port(kafka_host, int(kafka_port), "Kafka"):
        sys.exit(1)
    
    if not wait_for_port(CLICKHOUSE_HOST, CLICKHOUSE_PORT, "ClickHouse"):
        sys.exit(1)
    
    # Additional wait for Kafka to be fully ready
    time.sleep(10)
    print("✓ All services ready\n")


def main():
    """Main entry point"""
    wait_for_services()
    
    consumer = None
    try:
        consumer = ClickHouseConsumer()
        consumer.run()
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if consumer:
            consumer.close()


if __name__ == '__main__':
    main()
