#!/bin/bash
# Userdata script for Ollama EC2 instance
# This runs automatically when the instance starts

set -e

# Simple logging (no colors in userdata)
log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] $1"; }
log_error() { echo "[ERROR] $1"; exit 1; }

# Update system
yum update -y

# Install Ollama
log_info "Installing Ollama..."
curl -fsSL https://ollama.ai/install.sh | sh

# Create systemd drop-in directory
mkdir -p /etc/systemd/system/ollama.service.d

# Configure Ollama to listen on all interfaces
cat > /etc/systemd/system/ollama.service.d/override.conf <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

# Reload systemd and start Ollama
systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

# Wait for Ollama to be ready
log_info "Waiting for Ollama to be ready..."
for i in {1..60}; do
    if curl -s http://localhost:11434/api/version > /dev/null; then
        log_success "Ollama is ready"
        break
    fi
    sleep 5
done

# Pull the embedding model
log_info "Pulling nomic-embed-text model..."
ollama pull nomic-embed-text

log_success "Ollama setup complete"
