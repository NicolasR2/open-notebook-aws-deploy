#!/bin/bash
# Show status of deployed OpenNotebook infrastructure

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
echo "║      OpenNotebook Deployment Status                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -f "$STATE_FILE" ]; then
    log_error "No deployment state found. Run ./deploy.sh first."
    exit 1
fi

# Load IDs
OLLAMA_INSTANCE_ID=$(load_state "OLLAMA_INSTANCE_ID")
NOTEBOOK_INSTANCE_ID=$(load_state "NOTEBOOK_INSTANCE_ID")

if [ -z "$OLLAMA_INSTANCE_ID" ] || [ -z "$NOTEBOOK_INSTANCE_ID" ]; then
    log_error "Incomplete state. Run ./deploy.sh first."
    exit 1
fi

# Get current status
log_info "Querying AWS for current status..."
echo ""

# Ollama instance
echo "Ollama Instance:"
aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$OLLAMA_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]' \
    --output table

echo ""

# OpenNotebook instance
echo "OpenNotebook Instance:"
aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --instance-ids "$NOTEBOOK_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]' \
    --output table

echo ""
echo "Access URLs:"
NOTEBOOK_PUBLIC_IP=$(load_state "NOTEBOOK_PUBLIC_IP")
if [ -n "$NOTEBOOK_PUBLIC_IP" ]; then
    echo "  OpenNotebook UI: http://${NOTEBOOK_PUBLIC_IP}:8502"
    echo "  OpenNotebook API: http://${NOTEBOOK_PUBLIC_IP}:5055"
else
    echo "  (IP not yet assigned)"
fi

echo ""
echo "SSH Commands:"
OLLAMA_PUBLIC_IP=$(load_state "OLLAMA_PUBLIC_IP")
if [ -n "$OLLAMA_PUBLIC_IP" ]; then
    echo "  Ollama: ssh -i <your-key.pem> ec2-user@${OLLAMA_PUBLIC_IP}"
fi
if [ -n "$NOTEBOOK_PUBLIC_IP" ]; then
    echo "  OpenNotebook: ssh -i <your-key.pem> ec2-user@${NOTEBOOK_PUBLIC_IP}"
fi

echo ""
