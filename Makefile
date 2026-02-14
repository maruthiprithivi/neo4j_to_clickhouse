.PHONY: help start stop restart logs clean register-connectors connector-status delete-connectors test verify-clickhouse health

help:
	@echo "Neo4j to ClickHouse CDC - Available Commands"
	@echo "=============================================="
	@echo "make start                - Start all services"
	@echo "make stop                 - Stop all services"
	@echo "make restart              - Restart all services"
	@echo "make logs                 - View all logs"
	@echo "make logs-connect         - View Kafka Connect logs"
	@echo "make logs-neo4j           - View Neo4j logs"
	@echo "make logs-clickhouse      - View ClickHouse logs"
	@echo "make logs-kafka           - View Kafka logs"
	@echo "make clean                - Stop and remove all containers and volumes"
	@echo "make register-connectors  - Register Neo4j CDC source connectors"
	@echo "make connector-status     - Check connector status"
	@echo "make delete-connectors    - Delete all connectors"
	@echo "make test                 - Run test scenarios (containerized)"
	@echo "make verify-clickhouse    - Verify data in ClickHouse"
	@echo "make health               - Check service health"

start:
	docker-compose up -d
	@echo "Waiting for services to be healthy..."
	@sleep 10
	@docker-compose ps

stop:
	docker-compose stop

restart:
	docker-compose restart

logs:
	docker-compose logs -f

logs-connect:
	docker-compose logs -f kafka-connect

logs-neo4j:
	docker-compose logs -f neo4j

logs-clickhouse:
	docker-compose logs -f clickhouse

logs-kafka:
	docker-compose logs -f kafka

clean:
	docker-compose down -v
	@echo "All containers and volumes removed"

register-connectors:
	@echo "Registering Neo4j CDC source connectors..."
	docker-compose up register-connectors
	@echo "Connectors registered"

connector-status:
	@echo "Checking connector status..."
	@curl -s http://localhost:8083/connectors/neo4j-cdc-nodes-source/status | python3 -m json.tool || echo "Nodes connector not found"
	@echo ""
	@curl -s http://localhost:8083/connectors/neo4j-cdc-relationships-source/status | python3 -m json.tool || echo "Relationships connector not found"

delete-connectors:
	@echo "Deleting connectors..."
	@curl -s -X DELETE http://localhost:8083/connectors/neo4j-cdc-nodes-source || echo "Nodes connector not found"
	@curl -s -X DELETE http://localhost:8083/connectors/neo4j-cdc-relationships-source || echo "Relationships connector not found"
	@echo ""
	@echo "Connectors deleted"

test:
	@echo "Running test scenarios..."
	docker-compose run --rm test-runner

verify-clickhouse:
	@echo "Querying ClickHouse CDC data..."
	docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT event_type, count() as total FROM cdc.nodes_cdc GROUP BY event_type"
	docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT event_type, count() as total FROM cdc.relationships_cdc GROUP BY event_type"

health:
	@echo "Checking service health..."
	@echo ""
	@echo "Docker services:"
	@docker-compose ps
	@echo ""
	@echo "Kafka Connect:"
	@curl -s http://localhost:8083/connectors | python3 -m json.tool || echo "Kafka Connect not responding"
	@echo ""
	@echo "Neo4j:"
	@docker exec neo4j-cdc-neo4j cypher-shell -u neo4j -p password123 "RETURN 'Neo4j is healthy' as status" || echo "Neo4j not responding"
	@echo ""
	@echo "ClickHouse:"
	@docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT 'ClickHouse is healthy' as status" || echo "ClickHouse not responding"
