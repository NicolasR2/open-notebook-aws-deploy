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

# Create or reuse Ollama Security Group
log_info "Checking for existing Ollama security group..."
OLLAMA_SG=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=group-name,Values=open-notebook-ollama-sg" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ "$OLLAMA_SG" = "None" ] || [ -z "$OLLAMA_SG" ]; then
    log_info "Creating new Ollama security group..."
    OLLAMA_SG=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --group-name "open-notebook-ollama-sg" \
        --description "Security group for OpenNotebook Ollama service" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)
    log_success "Ollama SG created: $OLLAMA_SG"
else
    log_success "Using existing Ollama SG: $OLLAMA_SG"
fi

# Create or reuse OpenNotebook Security Group
log_info "Checking for existing OpenNotebook security group..."
NOTEBOOK_SG=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=group-name,Values=open-notebook-sg" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ "$NOTEBOOK_SG" = "None" ] || [ -z "$NOTEBOOK_SG" ]; then
    log_info "Creating new OpenNotebook security group..."
    NOTEBOOK_SG=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --group-name "open-notebook-sg" \
        --description "Security group for OpenNotebook application" \
        --vpc-id "$VPC_ID" \
        --query 'GroupId' \
        --output text)
    log_success "OpenNotebook SG created: $NOTEBOOK_SG"
else
    log_success "Using existing OpenNotebook SG: $NOTEBOOK_SG"
fi

# Helper function to add ingress rule (ignore if already exists)
add_ingress_rule() {
    local sg_id=$1
    local protocol=$2
    local port=$3
    local cidr=$4
    local source_group=$5

    local cmd="aws ec2 authorize-security-group-ingress --region $AWS_REGION --group-id $sg_id --protocol $protocol --port $port"

    if [ -n "$cidr" ]; then
        cmd="$cmd --cidr $cidr"
    fi

    if [ -n "$source_group" ]; then
        cmd="$cmd --source-group $source_group"
    fi

    # Execute and ignore if rule already exists
    eval "$cmd" 2>/dev/null || true
}

# Add SSH access to both security groups (from anywhere - adjust as needed)
log_info "Adding SSH access to Ollama SG..."
add_ingress_rule "$OLLAMA_SG" "tcp" "22" "0.0.0.0/0"

log_info "Adding SSH access to OpenNotebook SG..."
add_ingress_rule "$NOTEBOOK_SG" "tcp" "22" "0.0.0.0/0"

# Add Ollama port access (from OpenNotebook SG only)
log_info "Adding Ollama port (11434) access from OpenNotebook SG..."
add_ingress_rule "$OLLAMA_SG" "tcp" "11434" "" "$NOTEBOOK_SG"

# Add OpenNotebook web and API port access (from anywhere)
log_info "Adding OpenNotebook UI port (8502) access..."
add_ingress_rule "$NOTEBOOK_SG" "tcp" "8502" "0.0.0.0/0"

log_info "Adding OpenNotebook API port (5055) access..."
add_ingress_rule "$NOTEBOOK_SG" "tcp" "5055" "0.0.0.0/0"

# Save to state file
save_state "VPC_ID" "$VPC_ID"
save_state "OLLAMA_SG" "$OLLAMA_SG"
save_state "NOTEBOOK_SG" "$NOTEBOOK_SG"

log_success "=== Security Groups Created ==="
