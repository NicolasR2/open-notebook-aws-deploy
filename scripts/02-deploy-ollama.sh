#!/bin/bash
# Deploy Ollama EC2 instance

set -e

# Get the repo root directory
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Load configuration
source "$REPO_ROOT/config.env"
source "$REPO_ROOT/scripts/lib.sh"

log_info "=== Deploying Ollama EC2 ==="

# Define REPO_ROOT for state file access
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

# Load previously saved state
OLLAMA_SG=$(load_state "OLLAMA_SG")
if [ -z "$OLLAMA_SG" ]; then
    log_error "OLLAMA_SG not found in state file. Did you run 01-security-groups.sh?"
    exit 1
fi

# Get latest Amazon Linux 2023 AMI
log_info "Finding latest Amazon Linux 2023 AMI..."
AMI_ID=$(get_latest_ami)
if [ -z "$AMI_ID" ]; then
    log_error "Could not find Amazon Linux 2023 AMI"
    exit 1
fi
log_success "Using AMI: $AMI_ID"

# Get VPC and subnet
VPC_ID=$(load_state "VPC_ID")
SUBNET_ID=$(get_default_subnet "$VPC_ID")
log_info "Using subnet: $SUBNET_ID"

# Read userdata script
USERDATA=$(cat "$(dirname "$0")/../userdata/ollama-setup.sh")

# Launch Ollama instance
log_info "Launching Ollama EC2 instance..."
OLLAMA_INSTANCE=$(aws ec2 run-instances \
    --region "$AWS_REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$OLLAMA_INSTANCE_TYPE" \
    --key-name "$KEY_PAIR_NAME" \
    --security-group-ids "$OLLAMA_SG" \
    --subnet-id "$SUBNET_ID" \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=$OLLAMA_VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --user-data "$USERDATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=open-notebook-ollama},{Key=Environment,Value=$ENVIRONMENT_TAG}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

log_success "Ollama instance launched: $OLLAMA_INSTANCE"

# Wait for instance to be running
wait_for_instance_running "$OLLAMA_INSTANCE"

# Get instance IPs
OLLAMA_PRIVATE_IP=$(get_instance_private_ip "$OLLAMA_INSTANCE")
OLLAMA_PUBLIC_IP=$(get_instance_public_ip "$OLLAMA_INSTANCE")

log_success "Ollama Private IP: $OLLAMA_PRIVATE_IP"
log_success "Ollama Public IP: $OLLAMA_PUBLIC_IP"

# Wait for userdata to complete
wait_for_userdata "$OLLAMA_INSTANCE"

# Save to state file
save_state "OLLAMA_INSTANCE_ID" "$OLLAMA_INSTANCE"
save_state "OLLAMA_PRIVATE_IP" "$OLLAMA_PRIVATE_IP"
save_state "OLLAMA_PUBLIC_IP" "$OLLAMA_PUBLIC_IP"

log_success "=== Ollama EC2 Deployed ==="
