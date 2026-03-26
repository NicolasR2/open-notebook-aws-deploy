#!/bin/bash
# Deploy OpenNotebook EC2 instance

set -e

source "$(dirname "$0")/lib.sh"

log_info "=== Deploying OpenNotebook EC2 ==="

# Load previously saved state
NOTEBOOK_SG=$(load_state "NOTEBOOK_SG")
OLLAMA_PRIVATE_IP=$(load_state "OLLAMA_PRIVATE_IP")
VPC_ID=$(load_state "VPC_ID")

if [ -z "$NOTEBOOK_SG" ] || [ -z "$OLLAMA_PRIVATE_IP" ]; then
    log_error "Required state not found. Did you run 01-security-groups.sh and 02-deploy-ollama.sh?"
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

# Get subnet
SUBNET_ID=$(get_default_subnet "$VPC_ID")
log_info "Using subnet: $SUBNET_ID"

# Generate userdata from template
log_info "Generating userdata script..."
USERDATA_TEMPLATE=$(cat "$(dirname "$0")/../userdata/notebook-setup.sh.tpl")
USERDATA="${USERDATA_TEMPLATE//{{OLLAMA_IP}}/$OLLAMA_PRIVATE_IP}"
USERDATA="${USERDATA//{{ENCRYPTION_KEY}}/$ENCRYPTION_KEY}"

# Launch OpenNotebook instance
log_info "Launching OpenNotebook EC2 instance..."
NOTEBOOK_INSTANCE=$(aws ec2 run-instances \
    --region "$AWS_REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$NOTEBOOK_INSTANCE_TYPE" \
    --key-name "$KEY_PAIR_NAME" \
    --security-group-ids "$NOTEBOOK_SG" \
    --subnet-id "$SUBNET_ID" \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=$NOTEBOOK_VOLUME_SIZE,VolumeType=gp3,DeleteOnTermination=true}" \
    --user-data "$USERDATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=open-notebook-app},{Key=Environment,Value=$ENVIRONMENT_TAG}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

log_success "OpenNotebook instance launched: $NOTEBOOK_INSTANCE"

# Wait for instance to be running
wait_for_instance_running "$NOTEBOOK_INSTANCE"

# Get instance IPs
NOTEBOOK_PRIVATE_IP=$(get_instance_private_ip "$NOTEBOOK_INSTANCE")
NOTEBOOK_PUBLIC_IP=$(get_instance_public_ip "$NOTEBOOK_INSTANCE")

log_success "OpenNotebook Private IP: $NOTEBOOK_PRIVATE_IP"
log_success "OpenNotebook Public IP: $NOTEBOOK_PUBLIC_IP"

# Wait for userdata to complete
wait_for_userdata "$NOTEBOOK_INSTANCE"

# Save to state file
save_state "NOTEBOOK_INSTANCE_ID" "$NOTEBOOK_INSTANCE"
save_state "NOTEBOOK_PRIVATE_IP" "$NOTEBOOK_PRIVATE_IP"
save_state "NOTEBOOK_PUBLIC_IP" "$NOTEBOOK_PUBLIC_IP"

log_success "=== OpenNotebook EC2 Deployed ==="
