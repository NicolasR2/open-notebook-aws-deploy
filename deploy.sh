#!/bin/bash
# Main deployment orchestrator for OpenNotebook on AWS

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [ ! -f "$SCRIPT_DIR/config.env" ]; then
    echo "[ERROR] config.env not found. Please create it from the template."
    exit 1
fi

source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/scripts/lib.sh"

# Trap to handle errors
trap 'cleanup_on_error' EXIT

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║      OpenNotebook AWS Deployment                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Validate configuration
log_info "Validating configuration..."
validate_required_vars
validate_aws_cli

# Note: AWS credentials are available via Cloud9 IAM role
# validate_aws_credentials is skipped as it's handled automatically
log_success "AWS credentials available (via Cloud9 IAM role)"

validate_key_pair "$KEY_PAIR_NAME"

echo ""
log_info "Configuration Summary:"
echo "  Region: $AWS_REGION"
echo "  Key Pair: $KEY_PAIR_NAME"
echo "  Ollama Instance: $OLLAMA_INSTANCE_TYPE ($OLLAMA_VOLUME_SIZE GB)"
echo "  OpenNotebook Instance: $NOTEBOOK_INSTANCE_TYPE ($NOTEBOOK_VOLUME_SIZE GB)"
echo ""

# Clean up old state file if requested
if [ -f "$SCRIPT_DIR/.deployed-state" ]; then
    log_warn "Previous deployment state found."
    read -p "Do you want to start fresh? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$SCRIPT_DIR/.deployed-state"
        log_info "State file cleared"
    fi
fi

# Change to script directory
cd "$SCRIPT_DIR"

# Run deployment scripts in sequence
log_info "Starting deployment..."
echo ""

log_info "Step 1/3: Creating Security Groups..."
bash "$SCRIPT_DIR/scripts/01-security-groups.sh"
echo ""

log_info "Step 2/3: Deploying Ollama..."
bash "$SCRIPT_DIR/scripts/02-deploy-ollama.sh"
echo ""

log_info "Step 3/3: Deploying OpenNotebook..."
bash "$SCRIPT_DIR/scripts/03-deploy-notebook.sh"
echo ""

# Get final state
NOTEBOOK_PUBLIC_IP=$(load_state "NOTEBOOK_PUBLIC_IP")
OLLAMA_PUBLIC_IP=$(load_state "OLLAMA_PUBLIC_IP")

# Trap reset - deployment succeeded
trap - EXIT

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              Deployment Complete!                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_success "OpenNotebook deployed successfully!"
echo ""
echo "Access Information:"
echo "  OpenNotebook UI: http://${NOTEBOOK_PUBLIC_IP}:8502"
echo "  OpenNotebook API: http://${NOTEBOOK_PUBLIC_IP}:5055"
echo ""
echo "Next Steps:"
echo "  1. Wait 5-10 minutes for all services to fully initialize"
echo "  2. Open http://${NOTEBOOK_PUBLIC_IP}:8502 in your browser"
echo "  3. Go to Settings → API Keys and add your LLM provider (OpenAI, Anthropic, etc)"
echo "  4. Verify Ollama embedding model is detected"
echo "  5. Create a notebook and upload a document to test"
echo ""
echo "SSH Access (if needed):"
echo "  Ollama: ssh -i <your-key.pem> ec2-user@$(load_state 'OLLAMA_PUBLIC_IP')"
echo "  OpenNotebook: ssh -i <your-key.pem> ec2-user@${NOTEBOOK_PUBLIC_IP}"
echo ""
echo "Clean up Resources:"
echo "  Run: ./destroy.sh"
echo ""
echo "Check Status:"
echo "  Run: ./status.sh"
echo ""
