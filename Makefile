.PHONY: help start stop restart logs clean install-triggers remove-triggers test verify-clickhouse

help:
	@echo "Neo4j to ClickHouse CDC - Available Commands"
	@echo "=============================================="
	@echo "make start              - Start all services"
	@echo "make stop               - Stop all services"
	@echo "make restart            - Restart all services"
	@echo "make logs               - View all logs"
	@echo "make logs-cdc           - View CDC bridge logs"
	@echo "make logs-neo4j         - View Neo4j logs"
	@echo "make logs-clickhouse    - View ClickHouse logs"
	@echo "make clean              - Stop and remove all containers and volumes"
	@echo "make install-triggers   - Install Neo4j CDC triggers"
	@echo "make remove-triggers    - Remove Neo4j CDC triggers"
	@echo "make test               - Run test scenarios"
	@echo "make verify-clickhouse  - Verify data in ClickHouse"
	@echo "make health             - Check service health"

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

logs-cdc:
	docker-compose logs -f cdc-bridge

logs-neo4j:
	docker-compose logs -f neo4j

logs-clickhouse:
	docker-compose logs -f clickhouse

logs-kafka:
	docker-compose logs -f kafka

clean:
	docker-compose down -v
	@echo "All containers and volumes removed"

install-triggers:
	@echo "Installing Neo4j CDC triggers..."
	docker exec -i neo4j-cdc-neo4j cypher-shell -u neo4j -p password123 -d system < neo4j/install-triggers.cypher
	@echo "Triggers installed successfully"

remove-triggers:
	@echo "Removing Neo4j CDC triggers..."
	docker exec -i neo4j-cdc-neo4j cypher-shell -u neo4j -p password123 < neo4j/remove-triggers.cypher
	@echo "Triggers removed successfully"

test:
	@echo "Running test scenarios..."
	cd test-scenarios && python run_tests.py

verify-clickhouse:
	@echo "Querying ClickHouse CDC data..."
	docker exec -it neo4j-cdc-clickhouse clickhouse-client --query "SELECT event_type, count() as total FROM cdc.nodes_cdc GROUP BY event_type"
	docker exec -it neo4j-cdc-clickhouse clickhouse-client --query "SELECT event_type, count() as total FROM cdc.relationships_cdc GROUP BY event_type"

health:
	@echo "Checking service health..."
	@echo "\nDocker services:"
	@docker-compose ps
	@echo "\nCDC Bridge:"
	@curl -s http://localhost:8000/health | python -m json.tool || echo "CDC Bridge not responding"
	@echo "\nNeo4j:"
	@docker exec neo4j-cdc-neo4j cypher-shell -u neo4j -p password123 "RETURN 'Neo4j is healthy' as status" || echo "Neo4j not responding"
	@echo "\nClickHouse:"
	@docker exec neo4j-cdc-clickhouse clickhouse-client --query "SELECT 'ClickHouse is healthy' as status" || echo "ClickHouse not responding"
