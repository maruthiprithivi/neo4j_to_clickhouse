#!/usr/bin/env python3
"""
Neo4j to ClickHouse CDC Bridge
Receives CDC events from Neo4j triggers and publishes to Kafka
"""

import os
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional
from flask import Flask, request, jsonify
from confluent_kafka import Producer, KafkaError
import time

# Configure logging
logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO'),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Flask app
app = Flask(__name__)

# Kafka configuration
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
KAFKA_TOPIC_NODES = os.getenv('KAFKA_TOPIC_NODES', 'neo4j.nodes')
KAFKA_TOPIC_RELATIONSHIPS = os.getenv('KAFKA_TOPIC_RELATIONSHIPS', 'neo4j.relationships')

# Initialize Kafka producer
producer = None


def delivery_report(err, msg):
    """Callback for Kafka produce delivery reports"""
    if err is not None:
        logger.error(f"Message delivery failed: {err}")
    else:
        logger.info(f"Message delivered to {msg.topic()} "
                    f"(partition: {msg.partition()}, offset: {msg.offset()})")


def create_kafka_producer(retries=5, delay=5):
    """Create Kafka producer with retry logic"""
    for attempt in range(retries):
        try:
            logger.info(f"Attempting to connect to Kafka at {KAFKA_BOOTSTRAP_SERVERS} (attempt {attempt + 1}/{retries})")
            prod = Producer({
                'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
                'acks': 'all',
                'retries': 3,
                'max.in.flight.requests.per.connection': 1,
                'compression.type': 'gzip',
            })
            # Test connectivity by requesting metadata
            prod.list_topics(timeout=10)
            logger.info("Successfully connected to Kafka")
            return prod
        except Exception as e:
            logger.error(f"Failed to connect to Kafka: {e}")
            if attempt < retries - 1:
                logger.info(f"Retrying in {delay} seconds...")
                time.sleep(delay)
            else:
                logger.error("Max retries reached. Could not connect to Kafka.")
                raise
    return None


def publish_to_kafka(topic: str, event: Dict[str, Any], key: Optional[str] = None):
    """Publish event to Kafka topic"""
    global producer

    if producer is None:
        logger.error("Kafka producer not initialized")
        return False

    try:
        # Add event metadata if not present
        if 'event_id' not in event:
            event['event_id'] = str(uuid.uuid4())
        if 'event_timestamp' not in event:
            event['event_timestamp'] = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

        # Publish to Kafka
        producer.produce(
            topic,
            value=json.dumps(event).encode('utf-8'),
            key=key.encode('utf-8') if key else None,
            callback=delivery_report
        )
        producer.flush(timeout=10)

        logger.info(f"Published event {event['event_id']} to {topic}")
        return True

    except KafkaError as e:
        logger.error(f"Failed to publish to Kafka: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error publishing to Kafka: {e}")
        return False


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'cdc-bridge',
        'kafka_connected': producer is not None
    }), 200


@app.route('/cdc/node', methods=['POST'])
def handle_node_cdc():
    """Handle node CDC events from Neo4j triggers"""
    try:
        event = request.get_json(force=True)

        if not event:
            return jsonify({'error': 'No event data provided'}), 400

        # Validate required fields
        required_fields = ['event_type', 'entity_id']
        for field in required_fields:
            if field not in event:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        # Add metadata
        if 'metadata' not in event:
            event['metadata'] = {}
        event['metadata']['source'] = 'neo4j'
        event['metadata']['entity_type'] = 'NODE'

        # Convert metadata to JSON string for ClickHouse
        event['metadata'] = json.dumps(event['metadata'])

        # Ensure properties are JSON strings
        if 'properties_before' in event and isinstance(event['properties_before'], dict):
            event['properties_before'] = json.dumps(event['properties_before'])
        elif 'properties_before' not in event:
            event['properties_before'] = '{}'

        if 'properties_after' in event and isinstance(event['properties_after'], dict):
            event['properties_after'] = json.dumps(event['properties_after'])
        elif 'properties_after' not in event:
            event['properties_after'] = '{}'

        # Ensure labels is an array
        if 'labels' not in event:
            event['labels'] = []

        # Publish to Kafka
        success = publish_to_kafka(KAFKA_TOPIC_NODES, event, key=event['entity_id'])

        if success:
            return jsonify({
                'status': 'success',
                'event_id': event['event_id']
            }), 200
        else:
            return jsonify({'error': 'Failed to publish to Kafka'}), 500

    except Exception as e:
        logger.error(f"Error handling node CDC event: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500


@app.route('/cdc/relationship', methods=['POST'])
def handle_relationship_cdc():
    """Handle relationship CDC events from Neo4j triggers"""
    try:
        event = request.get_json(force=True)

        if not event:
            return jsonify({'error': 'No event data provided'}), 400

        # Validate required fields
        required_fields = ['event_type', 'entity_id', 'relationship_type']
        for field in required_fields:
            if field not in event:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        # Add metadata
        if 'metadata' not in event:
            event['metadata'] = {}
        event['metadata']['source'] = 'neo4j'
        event['metadata']['entity_type'] = 'RELATIONSHIP'

        # Convert metadata to JSON string for ClickHouse
        event['metadata'] = json.dumps(event['metadata'])

        # Ensure properties are JSON strings
        if 'properties_before' in event and isinstance(event['properties_before'], dict):
            event['properties_before'] = json.dumps(event['properties_before'])
        elif 'properties_before' not in event:
            event['properties_before'] = '{}'

        if 'properties_after' in event and isinstance(event['properties_after'], dict):
            event['properties_after'] = json.dumps(event['properties_after'])
        elif 'properties_after' not in event:
            event['properties_after'] = '{}'

        # Ensure source_id and target_id exist
        if 'source_id' not in event:
            event['source_id'] = ''
        if 'target_id' not in event:
            event['target_id'] = ''

        # Publish to Kafka
        success = publish_to_kafka(KAFKA_TOPIC_RELATIONSHIPS, event, key=event['entity_id'])

        if success:
            return jsonify({
                'status': 'success',
                'event_id': event['event_id']
            }), 200
        else:
            return jsonify({'error': 'Failed to publish to Kafka'}), 500

    except Exception as e:
        logger.error(f"Error handling relationship CDC event: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    # Initialize Kafka producer
    logger.info("Starting CDC Bridge Service")
    producer = create_kafka_producer()

    # Start Flask app
    host = os.getenv('CDC_BRIDGE_HOST', '0.0.0.0')
    port = int(os.getenv('CDC_BRIDGE_PORT', 8000))

    logger.info(f"Starting Flask server on {host}:{port}")
    app.run(host=host, port=port, debug=False)
