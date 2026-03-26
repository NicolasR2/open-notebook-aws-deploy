#!/bin/bash
# Shared functions for deployment scripts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# State file management
STATE_FILE=".deployed-state"

save_state() {
    local key=$1
    local value=$2

    if [ ! -f "$STATE_FILE" ]; then
        echo "" > "$STATE_FILE"
    fi

    if grep -q "^${key}=" "$STATE_FILE"; then
        # Update existing key
        sed -i.bak "s/^${key}=.*/${key}=${value}/" "$STATE_FILE"
        rm -f "$STATE_FILE.bak"
    else
        # Add new key
        echo "${key}=${value}" >> "$STATE_FILE"
    fi

    log_info "Saved: $key=$value"
}

load_state() {
    local key=$1

    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi

    local value=$(grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2- || echo "")
    if [ -z "$value" ]; then
        return 1
    fi

    echo "$value"
}

# AWS helper functions
get_default_vpc() {
    aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text
}

get_default_subnet() {
    local vpc_id=$1
    aws ec2 describe-subnets \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[0].SubnetId' \
        --output text
}

get_latest_ami() {
    # Get latest Amazon Linux 2023 AMI
    aws ec2 describe-images \
        --region "$AWS_REGION" \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-*" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text
}

# EC2 instance management
wait_for_instance_running() {
    local instance_id=$1
    local max_attempts=60
    local attempt=0

    log_info "Waiting for instance $instance_id to reach 'running' state..."

    while [ $attempt -lt $max_attempts ]; do
        local state=$(aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text)

        if [ "$state" = "running" ]; then
            log_success "Instance $instance_id is running"
            return 0
        fi

        if [ "$state" = "terminated" ] || [ "$state" = "terminating" ]; then
            log_error "Instance $instance_id was terminated"
            return 1
        fi

        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done

    log_error "Timeout waiting for instance $instance_id"
    return 1
}

get_instance_private_ip() {
    local instance_id=$1
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text
}

get_instance_public_ip() {
    local instance_id=$1
    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text
}

wait_for_userdata() {
    local instance_id=$1
    local max_attempts=120  # 10 minutes
    local attempt=0

    log_info "Waiting for userdata script to complete on $instance_id..."

    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws ec2 describe-instance-status \
            --region "$AWS_REGION" \
            --instance-ids "$instance_id" \
            --query 'InstanceStatuses[0].InstanceStatus.Status' \
            --output text 2>/dev/null || echo "initializing")

        if [ "$status" = "ok" ]; then
            log_success "Instance $instance_id is ready"
            return 0
        fi

        echo -n "."
        sleep 5
        attempt=$((attempt + 1))
    done

    log_warn "Timeout waiting for instance status (may still be initializing)"
    return 0
}

# Validation
validate_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    log_success "AWS CLI found"
}

validate_aws_credentials() {
    if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    log_success "AWS credentials valid"
}

validate_key_pair() {
    local key_pair=$1
    if ! aws ec2 describe-key-pairs \
        --region "$AWS_REGION" \
        --key-names "$key_pair" &> /dev/null; then
        log_error "Key pair '$key_pair' not found in AWS region $AWS_REGION"
        exit 1
    fi
    log_success "Key pair '$key_pair' found"
}

validate_required_vars() {
    local missing_vars=()

    for var in AWS_REGION KEY_PAIR_NAME ENCRYPTION_KEY \
               NOTEBOOK_INSTANCE_TYPE OLLAMA_INSTANCE_TYPE \
               NOTEBOOK_VOLUME_SIZE OLLAMA_VOLUME_SIZE; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required variables: ${missing_vars[*]}"
        exit 1
    fi

    log_success "All required variables set"
}

# Cleanup
cleanup_on_error() {
    log_error "Deployment failed. Partial resources may exist in AWS."
    log_info "Run './destroy.sh' to clean up or './status.sh' to see what was created."
}

trap cleanup_on_error EXIT
