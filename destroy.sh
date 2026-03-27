#!/bin/bash
# Destroy all AWS resources created by deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration and lib
if [ ! -f "$SCRIPT_DIR/config.env" ]; then
    echo "[ERROR] config.env not found."
    exit 1
fi

source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/scripts/lib.sh"

STATE_FILE="$SCRIPT_DIR/.deployed-state"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      OpenNotebook AWS Destruction                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -f "$STATE_FILE" ]; then
    log_error "No deployment state found. Nothing to destroy."
    exit 1
fi

# Load resource IDs
OLLAMA_INSTANCE_ID=$(load_state "OLLAMA_INSTANCE_ID")
NOTEBOOK_INSTANCE_ID=$(load_state "NOTEBOOK_INSTANCE_ID")
OLLAMA_SG=$(load_state "OLLAMA_SG")
NOTEBOOK_SG=$(load_state "NOTEBOOK_SG")

log_warn "WARNING: This will destroy the following resources:"
echo "  Ollama Instance: $OLLAMA_INSTANCE_ID"
echo "  OpenNotebook Instance: $NOTEBOOK_INSTANCE_ID"
echo "  Security Groups: $OLLAMA_SG, $NOTEBOOK_SG"
echo ""

read -p "Are you sure you want to continue? (yes/no) " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Destruction cancelled"
    exit 0
fi

cd "$SCRIPT_DIR"

# Terminate instances
if [ -n "$OLLAMA_INSTANCE_ID" ]; then
    log_info "Terminating Ollama instance: $OLLAMA_INSTANCE_ID"
    aws ec2 terminate-instances \
        --region "$AWS_REGION" \
        --instance-ids "$OLLAMA_INSTANCE_ID" \
        > /dev/null
fi

if [ -n "$NOTEBOOK_INSTANCE_ID" ]; then
    log_info "Terminating OpenNotebook instance: $NOTEBOOK_INSTANCE_ID"
    aws ec2 terminate-instances \
        --region "$AWS_REGION" \
        --instance-ids "$NOTEBOOK_INSTANCE_ID" \
        > /dev/null
fi

# Wait for instances to terminate
log_info "Waiting for instances to terminate..."
if [ -n "$OLLAMA_INSTANCE_ID" ]; then
    aws ec2 wait instance-terminated \
        --region "$AWS_REGION" \
        --instance-ids "$OLLAMA_INSTANCE_ID" \
        2>/dev/null || true
fi

if [ -n "$NOTEBOOK_INSTANCE_ID" ]; then
    aws ec2 wait instance-terminated \
        --region "$AWS_REGION" \
        --instance-ids "$NOTEBOOK_INSTANCE_ID" \
        2>/dev/null || true
fi

log_success "Instances terminated"

# Delete security groups (wait a bit for instances to fully terminate)
sleep 5

if [ -n "$OLLAMA_SG" ]; then
    log_info "Deleting Ollama security group: $OLLAMA_SG"
    aws ec2 delete-security-group \
        --region "$AWS_REGION" \
        --group-id "$OLLAMA_SG" \
        2>/dev/null || log_warn "Could not delete Ollama SG (may have dependencies)"
fi

if [ -n "$NOTEBOOK_SG" ]; then
    log_info "Deleting OpenNotebook security group: $NOTEBOOK_SG"
    aws ec2 delete-security-group \
        --region "$AWS_REGION" \
        --group-id "$NOTEBOOK_SG" \
        2>/dev/null || log_warn "Could not delete OpenNotebook SG (may have dependencies)"
fi

log_success "Security groups deleted"

# Clean up state file
rm "$STATE_FILE"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Destruction Complete!                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
