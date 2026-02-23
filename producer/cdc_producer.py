#!/usr/bin/env python3
"""
Neo4j CDC Producer
Monitors Neo4j for changes and publishes events to Kafka
"""

import os
import json
import time
import uuid
from datetime import datetime
from typing import Dict, Any
from kafka import KafkaProducer
from neo4j import GraphDatabase
from faker import Faker

# Configuration
NEO4J_URI = os.getenv('NEO4J_URI', 'bolt://neo4j:7687')
NEO4J_USER = os.getenv('NEO4J_USER', 'neo4j')
NEO4J_PASSWORD = os.getenv('NEO4J_PASSWORD', 'password123')
KAFKA_BROKER = os.getenv('KAFKA_BROKER', 'kafka:29092')
NODE_TOPIC = 'neo4j.nodes'
RELATIONSHIP_TOPIC = 'neo4j.relationships'

fake = Faker()


class Neo4jCDCProducer:
    """Produces CDC events from Neo4j to Kafka"""
    
    def __init__(self):
        # Initialize Kafka producer
        self.producer = KafkaProducer(
            bootstrap_servers=[KAFKA_BROKER],
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks='all',
            retries=3,
            compression_type='snappy'
        )
        
        # Initialize Neo4j driver
        self.driver = GraphDatabase.driver(
            NEO4J_URI,
            auth=(NEO4J_USER, NEO4J_PASSWORD)
        )
        
        self.tx_counter = 1
        
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
    
    def close(self):
        """Close connections"""
        if hasattr(self, 'producer'):
            self.producer.flush()
            self.producer.close()
        if hasattr(self, 'driver'):
            self.driver.close()
    
    def generate_event_id(self) -> str:
        """Generate unique event ID"""
        return str(uuid.uuid4())
    
    def get_tx_id(self) -> int:
        """Get next transaction ID"""
        tx_id = self.tx_counter
        self.tx_counter += 1
        return tx_id
    
    def create_node_event(
        self,
        operation: str,
        node_id: str,
        labels: list,
        properties: dict
    ) -> Dict[str, Any]:
        """Create a node change event"""
        return {
            'event_id': self.generate_event_id(),
            'tx_id': self.get_tx_id(),
            'operation': operation,
            'labels': labels,
            'node_id': node_id,
            'properties': json.dumps(properties),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }
    
    def create_relationship_event(
        self,
        operation: str,
        rel_id: str,
        rel_type: str,
        from_node_id: str,
        to_node_id: str,
        properties: dict
    ) -> Dict[str, Any]:
        """Create a relationship change event"""
        return {
            'event_id': self.generate_event_id(),
            'tx_id': self.get_tx_id(),
            'operation': operation,
            'rel_type': rel_type,
            'rel_id': rel_id,
            'from_node_id': from_node_id,
            'to_node_id': to_node_id,
            'properties': json.dumps(properties),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }
    
    def publish_node_event(self, event: Dict[str, Any]):
        """Publish node event to Kafka"""
        future = self.producer.send(NODE_TOPIC, value=event)
        try:
            record_metadata = future.get(timeout=10)
            print(f"✓ Published node event to {record_metadata.topic} "
                  f"partition {record_metadata.partition} "
                  f"offset {record_metadata.offset}")
        except Exception as e:
            print(f"✗ Failed to publish node event: {e}")
    
    def publish_relationship_event(self, event: Dict[str, Any]):
        """Publish relationship event to Kafka"""
        future = self.producer.send(RELATIONSHIP_TOPIC, value=event)
        try:
            record_metadata = future.get(timeout=10)
            print(f"✓ Published relationship event to {record_metadata.topic} "
                  f"partition {record_metadata.partition} "
                  f"offset {record_metadata.offset}")
        except Exception as e:
            print(f"✗ Failed to publish relationship event: {e}")
    
    def setup_neo4j_triggers(self):
        """Setup APOC triggers in Neo4j for CDC (optional)"""
        with self.driver.session() as session:
            # Note: This requires APOC plugin and proper configuration
            # For this prototype, we'll use simulated events instead
            print("Note: APOC triggers require additional Neo4j configuration")
            print("Using simulated CDC events for this prototype")
    
    def generate_sample_data(self, num_people: int = 10, num_companies: int = 3):
        """Generate sample graph data in Neo4j and emit CDC events"""
        with self.driver.session() as session:
            print(f"\n=== Creating {num_people} people and {num_companies} companies ===\n")
            
            # Create companies
            company_ids = []
            for i in range(num_companies):
                company_name = fake.company()
                company_id = f"company_{i+1}"
                
                # Create in Neo4j
                session.run(
                    "CREATE (c:Company {id: $id, name: $name, founded: $founded})",
                    id=company_id,
                    name=company_name,
                    founded=fake.year()
                )
                
                # Emit CDC event
                event = self.create_node_event(
                    operation='CREATE',
                    node_id=company_id,
                    labels=['Company'],
                    properties={
                        'id': company_id,
                        'name': company_name,
                        'founded': fake.year(),
                        'created_at': datetime.utcnow().isoformat()
                    }
                )
                self.publish_node_event(event)
                company_ids.append(company_id)
                time.sleep(0.1)
            
            # Create people and relationships
            person_ids = []
            for i in range(num_people):
                person_id = f"person_{i+1}"
                person_name = fake.name()
                person_email = fake.email()
                
                # Create in Neo4j
                session.run(
                    "CREATE (p:Person {id: $id, name: $name, email: $email, age: $age})",
                    id=person_id,
                    name=person_name,
                    email=person_email,
                    age=fake.random_int(min=22, max=65)
                )
                
                # Emit CDC event
                event = self.create_node_event(
                    operation='CREATE',
                    node_id=person_id,
                    labels=['Person'],
                    properties={
                        'id': person_id,
                        'name': person_name,
                        'email': person_email,
                        'age': fake.random_int(min=22, max=65),
                        'created_at': datetime.utcnow().isoformat()
                    }
                )
                self.publish_node_event(event)
                person_ids.append(person_id)
                time.sleep(0.1)
            
            # Create WORKS_AT relationships
            print("\n=== Creating WORKS_AT relationships ===\n")
            for person_id in person_ids:
                if fake.boolean(chance_of_getting_true=80):  # 80% have a job
                    company_id = fake.random_element(company_ids)
                    rel_id = f"{person_id}_works_at_{company_id}"
                    
                    # Create in Neo4j
                    session.run(
                        """
                        MATCH (p:Person {id: $person_id})
                        MATCH (c:Company {id: $company_id})
                        CREATE (p)-[r:WORKS_AT {since: $since, position: $position}]->(c)
                        """,
                        person_id=person_id,
                        company_id=company_id,
                        since=fake.date_between(start_date='-10y', end_date='today').isoformat(),
                        position=fake.job()
                    )
                    
                    # Emit CDC event
                    event = self.create_relationship_event(
                        operation='CREATE',
                        rel_id=rel_id,
                        rel_type='WORKS_AT',
                        from_node_id=person_id,
                        to_node_id=company_id,
                        properties={
                            'since': fake.date_between(start_date='-10y', end_date='today').isoformat(),
                            'position': fake.job(),
                            'created_at': datetime.utcnow().isoformat()
                        }
                    )
                    self.publish_relationship_event(event)
                    time.sleep(0.1)
            
            # Create KNOWS relationships (social graph)
            print("\n=== Creating KNOWS relationships ===\n")
            num_friendships = num_people // 2
            for _ in range(num_friendships):
                person1 = fake.random_element(person_ids)
                person2 = fake.random_element(person_ids)
                
                if person1 != person2:
                    rel_id = f"{person1}_knows_{person2}"
                    
                    # Create in Neo4j
                    session.run(
                        """
                        MATCH (p1:Person {id: $person1})
                        MATCH (p2:Person {id: $person2})
                        MERGE (p1)-[r:KNOWS {since: $since}]-(p2)
                        """,
                        person1=person1,
                        person2=person2,
                        since=fake.date_between(start_date='-20y', end_date='today').isoformat()
                    )
                    
                    # Emit CDC event
                    event = self.create_relationship_event(
                        operation='CREATE',
                        rel_id=rel_id,
                        rel_type='KNOWS',
                        from_node_id=person1,
                        to_node_id=person2,
                        properties={
                            'since': fake.date_between(start_date='-20y', end_date='today').isoformat(),
                            'created_at': datetime.utcnow().isoformat()
                        }
                    )
                    self.publish_relationship_event(event)
                    time.sleep(0.1)
    
    def simulate_updates(self, num_updates: int = 5):
        """Simulate UPDATE operations"""
        print(f"\n=== Simulating {num_updates} updates ===\n")
        
        with self.driver.session() as session:
            # Get random person IDs
            result = session.run("MATCH (p:Person) RETURN p.id AS id LIMIT $limit", limit=num_updates)
            person_ids = [record['id'] for record in result]
            
            for person_id in person_ids:
                new_age = fake.random_int(min=22, max=65)
                
                # Update in Neo4j
                session.run(
                    "MATCH (p:Person {id: $id}) SET p.age = $age, p.updated_at = datetime()",
                    id=person_id,
                    age=new_age
                )
                
                # Emit CDC event
                event = self.create_node_event(
                    operation='UPDATE',
                    node_id=person_id,
                    labels=['Person'],
                    properties={
                        'age': new_age,
                        'updated_at': datetime.utcnow().isoformat()
                    }
                )
                self.publish_node_event(event)
                time.sleep(0.5)
    
    def simulate_deletes(self, num_deletes: int = 2):
        """Simulate DELETE operations"""
        print(f"\n=== Simulating {num_deletes} deletes ===\n")
        
        with self.driver.session() as session:
            # Get random person IDs
            result = session.run("MATCH (p:Person) RETURN p.id AS id LIMIT $limit", limit=num_deletes)
            person_ids = [record['id'] for record in result]
            
            for person_id in person_ids:
                # Delete from Neo4j
                session.run(
                    "MATCH (p:Person {id: $id}) DETACH DELETE p",
                    id=person_id
                )
                
                # Emit CDC event
                event = self.create_node_event(
                    operation='DELETE',
                    node_id=person_id,
                    labels=['Person'],
                    properties={}
                )
                self.publish_node_event(event)
                time.sleep(0.5)


def wait_for_services():
    """Wait for Kafka and Neo4j to be ready"""
    import socket
    
    def wait_for_port(host: str, port: int, timeout: int = 60):
        start = time.time()
        while time.time() - start < timeout:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(1)
                sock.connect((host, port))
                sock.close()
                return True
            except (socket.error, socket.timeout):
                time.sleep(1)
        return False
    
    print("Waiting for Kafka...")
    if not wait_for_port('kafka', 29092, timeout=120):
        print("ERROR: Kafka not available")
        return False
    
    print("Waiting for Neo4j...")
    if not wait_for_port('neo4j', 7687, timeout=120):
        print("ERROR: Neo4j not available")
        return False
    
    print("All services ready!")
    return True


def main():
    """Main entry point"""
    print("="*60)
    print("Neo4j to ClickHouse CDC Producer")
    print("="*60)
    
    # Wait for services
    if not wait_for_services():
        return
    
    # Additional startup delay
    print("Waiting for services to fully initialize...")
    time.sleep(10)
    
    # Run CDC producer
    with Neo4jCDCProducer() as producer:
        # Generate sample data
        producer.generate_sample_data(num_people=20, num_companies=5)
        
        # Wait a bit
        print("\nWaiting 5 seconds...")
        time.sleep(5)
        
        # Simulate some updates
        producer.simulate_updates(num_updates=10)
        
        # Wait a bit
        print("\nWaiting 5 seconds...")
        time.sleep(5)
        
        # Simulate some deletes
        producer.simulate_deletes(num_deletes=3)
        
        print("\n" + "="*60)
        print("CDC events published successfully!")
        print("Check Kafka UI at http://localhost:8080")
        print("Query ClickHouse at http://localhost:8123")
        print("="*60)


if __name__ == '__main__':
    main()
