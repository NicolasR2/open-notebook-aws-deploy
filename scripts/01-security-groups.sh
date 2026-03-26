#!/bin/bash
# Create security groups for Ollama and OpenNotebook

set -e

# Get the repo root directory (set by parent or determine here)
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Load configuration (use exported vars if available, otherwise source)
if [ -z "$AWS_REGION" ]; then
    source "$REPO_ROOT/config.env"
fi

source "$REPO_ROOT/scripts/lib.sh"

log_info "=== Creating Security Groups ==="
log_info "DEBUG: AWS_REGION=$AWS_REGION"

# Get VPC
log_info "Getting default VPC..."
VPC_ID=$(get_default_vpc)
if [ -z "$VPC_ID" ]; then
    log_error "Could not find default VPC"
    exit 1
fi
log_success "Using VPC: $VPC_ID"

# Create Ollama Security Group
log_info "Creating Ollama security group..."
OLLAMA_SG=$(aws ec2 create-security-group \
    --region "$AWS_REGION" \
    --group-name "open-notebook-ollama-sg" \
    --description "Security group for OpenNotebook Ollama service" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

log_success "Ollama SG created: $OLLAMA_SG"

# Create OpenNotebook Security Group
log_info "Creating OpenNotebook security group..."
NOTEBOOK_SG=$(aws ec2 create-security-group \
    --region "$AWS_REGION" \
    --group-name "open-notebook-sg" \
    --description "Security group for OpenNotebook application" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

log_success "OpenNotebook SG created: $NOTEBOOK_SG"

# Add SSH access to both security groups (from anywhere - adjust as needed)
log_info "Adding SSH access to Ollama SG..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$OLLAMA_SG" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

log_info "Adding SSH access to OpenNotebook SG..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$NOTEBOOK_SG" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Add Ollama port access (from OpenNotebook SG only)
log_info "Adding Ollama port (11434) access from OpenNotebook SG..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$OLLAMA_SG" \
    --protocol tcp \
    --port 11434 \
    --source-group "$NOTEBOOK_SG"

# Add OpenNotebook web and API port access (from anywhere)
log_info "Adding OpenNotebook UI port (8502) access..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$NOTEBOOK_SG" \
    --protocol tcp \
    --port 8502 \
    --cidr 0.0.0.0/0

log_info "Adding OpenNotebook API port (5055) access..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$NOTEBOOK_SG" \
    --protocol tcp \
    --port 5055 \
    --cidr 0.0.0.0/0

# Save to state file
save_state "VPC_ID" "$VPC_ID"
save_state "OLLAMA_SG" "$OLLAMA_SG"
save_state "NOTEBOOK_SG" "$NOTEBOOK_SG"

log_success "=== Security Groups Created ==="
