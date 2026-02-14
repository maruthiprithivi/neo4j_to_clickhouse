FROM python:3.12-slim

WORKDIR /app

RUN pip install --no-cache-dir neo4j clickhouse-connect

COPY . /app/

CMD ["python", "run_tests.py"]
