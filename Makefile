.PHONY: help start stop restart logs status clean setup-clickhouse generate-data query shell-clickhouse shell-neo4j shell-kafka test

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

start: ## Start all services
	docker-compose up -d
	@echo "Waiting for services to be healthy..."
	@sleep 10
	@echo "Services started! Access points:"
	@echo "  Neo4j Browser:    http://localhost:7474 (neo4j/password123)"
	@echo "  Kafka UI:         http://localhost:8080"
	@echo "  ClickHouse HTTP:  http://localhost:8123"

stop: ## Stop all services
	docker-compose stop

restart: ## Restart all services
	docker-compose restart

logs: ## Show logs from all services
	docker-compose logs -f

status: ## Show status of all services
	docker-compose ps

clean: ## Stop and remove all containers, volumes, and data
	docker-compose down -v
	@echo "All data removed!"

setup-clickhouse: ## Setup ClickHouse schema (run after start)
	@echo "Setting up ClickHouse tables and views..."
	docker exec neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/01_create_kafka_tables.sql
	docker exec neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/02_create_storage_tables.sql
	docker exec neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/03_create_analytics_views.sql
	@echo "ClickHouse setup complete!"

generate-data: ## Generate sample CDC events
	docker exec neo4j-cdc-producer python /app/cdc_producer.py

query: ## Run sample queries in ClickHouse
	docker exec -it neo4j-cdc-clickhouse clickhouse-client --multiquery < sql/04_sample_queries.sql

shell-clickhouse: ## Open ClickHouse interactive shell
	docker exec -it neo4j-cdc-clickhouse clickhouse-client

shell-neo4j: ## Open Neo4j Cypher shell
	docker exec -it neo4j-cdc-source cypher-shell -u neo4j -p password123

shell-kafka: ## Open Kafka container bash shell
	docker exec -it neo4j-cdc-kafka bash

shell-producer: ## Open producer container bash shell
	docker exec -it neo4j-cdc-producer bash

test: ## Full integration test (start, setup, generate, verify)
	@echo "=== Starting services ==="
	$(MAKE) start
	@echo ""
	@echo "=== Waiting for services to be ready ==="
	@sleep 30
	@echo ""
	@echo "=== Setting up ClickHouse ==="
	$(MAKE) setup-clickhouse
	@echo ""
	@echo "=== Generating sample data ==="
	$(MAKE) generate-data
	@echo ""
	@echo "=== Waiting for ingestion ==="
	@sleep 10
	@echo ""
	@echo "=== Verifying data ==="
	docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT count() FROM neo4j_cdc.node_changes"
	docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT count() FROM neo4j_cdc.relationship_changes"
	@echo ""
	@echo "=== Test complete! ==="

kafka-topics: ## List all Kafka topics
	docker exec neo4j-cdc-kafka kafka-topics --list --bootstrap-server localhost:9092

kafka-consume-nodes: ## Consume messages from neo4j.nodes topic
	docker exec neo4j-cdc-kafka kafka-console-consumer \
		--bootstrap-server localhost:9092 \
		--topic neo4j.nodes \
		--from-beginning \
		--max-messages 10

kafka-consume-rels: ## Consume messages from neo4j.relationships topic
	docker exec neo4j-cdc-kafka kafka-console-consumer \
		--bootstrap-server localhost:9092 \
		--topic neo4j.relationships \
		--from-beginning \
		--max-messages 10

clickhouse-stats: ## Show ClickHouse ingestion statistics
	docker exec neo4j-cdc-clickhouse clickhouse-client --query "\
		SELECT \
			'Nodes' AS type, \
			count() AS total_events, \
			min(event_time) AS first_event, \
			max(event_time) AS last_event, \
			formatReadableSize(sum(length(properties))) AS total_size \
		FROM neo4j_cdc.node_changes \
		UNION ALL \
		SELECT \
			'Relationships' AS type, \
			count() AS total_events, \
			min(event_time) AS first_event, \
			max(event_time) AS last_event, \
			formatReadableSize(sum(length(properties))) AS total_size \
		FROM neo4j_cdc.relationship_changes \
		FORMAT Pretty"

neo4j-stats: ## Show Neo4j node and relationship counts
	docker exec neo4j-cdc-source cypher-shell -u neo4j -p password123 \
		"MATCH (n) RETURN labels(n)[0] AS type, count(*) AS count ORDER BY count DESC"
