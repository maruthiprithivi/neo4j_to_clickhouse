FROM python:3.12-slim

WORKDIR /app

# Install system dependencies (librdkafka-dev required by confluent-kafka)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    librdkafka-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port for HTTP endpoint
EXPOSE 8000

# Run the CDC bridge service
CMD ["python", "main.py"]
