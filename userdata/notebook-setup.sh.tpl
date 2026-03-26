#!/bin/bash
# Userdata script for OpenNotebook EC2 instance
# Variables substituted by deploy script:
#   {{OLLAMA_IP}} - Private IP of Ollama instance
#   {{ENCRYPTION_KEY}} - Encryption key for storing API credentials

set -e

# Update system
yum update -y

# Install Docker
yum install docker -y

# Install Docker Compose plugin
yum install docker-compose-plugin -y

# Start Docker
systemctl enable docker
systemctl start docker

# Create app directory
mkdir -p /app

# Create docker-compose.yml
cat > /app/docker-compose.yml <<'DOCKER_EOF'
version: '3.8'

services:
  surrealdb:
    image: surrealdb/surrealdb:v2
    container_name: surrealdb
    ports:
      - "8000:8000"
    volumes:
      - surreal_data:/data
    environment:
      SURREAL_USER: root
      SURREAL_PASSWORD: root
    command: start --log trace file:/data/database.db
    restart: unless-stopped

  open_notebook:
    image: lfnovo/open_notebook:latest
    container_name: open_notebook
    ports:
      - "8502:8501"
      - "5055:5055"
    volumes:
      - notebook_data:/app/data
    environment:
      SURREAL_URL: ws://surrealdb:8000/rpc
      SURREAL_USER: root
      SURREAL_PASSWORD: root
      SURREAL_NAMESPACE: open_notebook
      SURREAL_DATABASE: open_notebook
      OPEN_NOTEBOOK_ENCRYPTION_KEY: {{ENCRYPTION_KEY}}
      OLLAMA_BASE_URL: http://{{OLLAMA_IP}}:11434
    depends_on:
      - surrealdb
    restart: unless-stopped

volumes:
  surreal_data:
  notebook_data:
DOCKER_EOF

# Start Docker Compose
cd /app
docker compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Check if OpenNotebook is accessible
for i in {1..60}; do
    if curl -s http://localhost:8502 > /dev/null; then
        echo "OpenNotebook is ready!"
        break
    fi
    echo "Waiting for OpenNotebook..."
    sleep 5
done

echo "Setup complete!"
