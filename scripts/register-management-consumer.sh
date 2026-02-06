#!/bin/bash
set -euo pipefail

# =============================================================================
# Register Management Cluster Consumer (REGIONAL CONTEXT)
# =============================================================================
# This script registers a Management Cluster as a consumer with the Regional
# Cluster's Maestro server via the Frontend API.
#
# Prerequisites:
# - AWS credentials configured for REGIONAL account
# - awscurl installed (pip install awscurl)
# - Regional cluster infrastructure provisioned (API Gateway available)
# - Management cluster tfvars with cluster_id defined
#
# Usage:
#   ./scripts/register-management-consumer.sh <path-to-management-cluster-tfvars>
#
# Example:
#   ./scripts/register-management-consumer.sh \
#     terraform/config/management-cluster/terraform.tfvars
#
# =============================================================================

# Color codes for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory and paths
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REGIONAL_TF_DIR="${REPO_ROOT}/terraform/config/regional-cluster"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1" >&2
}

# Extract a variable value from a Terraform tfvars file
extract_tfvar() {
  local file="$1"
  local var="$2"

  grep "^${var}[[:space:]]*=" "$file" | \
    sed -E 's/^[^=]+=[[:space:]]*"([^"]+)".*/\1/' | \
    tr -d '\n'
}

# =============================================================================
# Argument Validation
# =============================================================================

if [ $# -ne 1 ]; then
  log_error "Usage: $0 <path-to-management-cluster-tfvars>"
  log_info "Example: $0 terraform/config/management-cluster/terraform.tfvars"
  exit 1
fi

MGMT_TFVARS="$1"

if [ ! -f "$MGMT_TFVARS" ]; then
  log_error "Management cluster tfvars file not found: ${MGMT_TFVARS}"
  exit 1
fi

# Check for required tools
if ! command -v aws &> /dev/null; then
  log_error "aws CLI is required but not installed"
  log_info "Install from: https://aws.amazon.com/cli/"
  exit 1
fi

if ! command -v awscurl &> /dev/null; then
  log_error "awscurl is required but not installed"
  log_info "Install with: pip install awscurl"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  log_error "jq is required but not installed"
  log_info "Install with: sudo dnf install jq  (or apt-get install jq)"
  exit 1
fi

# =============================================================================
# Verify AWS Context (Regional Account)
# =============================================================================

log_info "Verifying AWS credentials (should be REGIONAL account)..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
AWS_REGION=$(aws configure get region || echo "")

if [ -z "$AWS_ACCOUNT_ID" ]; then
  log_error "Unable to verify AWS credentials. Ensure you're authenticated."
  exit 1
fi

if [ -z "$AWS_REGION" ]; then
  log_error "AWS region not configured. Set it with: aws configure set region <region>"
  exit 1
fi

log_success "AWS credentials verified"
log_info "  Account ID: ${AWS_ACCOUNT_ID}"
log_info "  Region:     ${AWS_REGION}"
log_warning "  ⚠️  Ensure this is your REGIONAL account!"
echo ""

# =============================================================================
# Parse Management Cluster Configuration
# =============================================================================

log_info "Parsing management cluster configuration from: ${MGMT_TFVARS}"

CLUSTER_ID=$(extract_tfvar "$MGMT_TFVARS" "cluster_id")

if [ -z "$CLUSTER_ID" ]; then
  log_error "cluster_id not found in ${MGMT_TFVARS}"
  exit 1
fi

log_success "Configuration parsed: cluster_id=${CLUSTER_ID}"
echo ""

# =============================================================================
# Get API Gateway URL from Regional Terraform State
# =============================================================================

log_info "Retrieving API Gateway URL from regional terraform state..."

if [ ! -d "$REGIONAL_TF_DIR" ]; then
  log_error "Regional terraform directory not found: ${REGIONAL_TF_DIR}"
  exit 1
fi

# Get the API Gateway invoke URL from terraform output
API_GATEWAY_URL=$(cd "$REGIONAL_TF_DIR" && terraform output -raw api_gateway_invoke_url 2>/dev/null || echo "")

if [ -z "$API_GATEWAY_URL" ]; then
  log_error "Could not retrieve api_gateway_invoke_url from terraform output"
  log_info ""
  log_info "Ensure the regional cluster is provisioned and terraform state is available:"
  log_info "  cd ${REGIONAL_TF_DIR} && terraform init && terraform output"
  exit 1
fi

log_success "API Gateway URL: ${API_GATEWAY_URL}"
echo ""

# =============================================================================
# Check if Consumer Already Exists
# =============================================================================

log_info "Checking if consumer '${CLUSTER_ID}' already exists..."

EXISTING_CONSUMERS=$(awscurl --service execute-api --region "$AWS_REGION" \
  "${API_GATEWAY_URL}/api/v0/management_clusters" 2>/dev/null || echo "")

if echo "$EXISTING_CONSUMERS" | jq -e ".items[] | select(.name == \"${CLUSTER_ID}\")" &>/dev/null; then
  log_warning "Consumer '${CLUSTER_ID}' already registered"
  echo ""
  echo "Existing consumer details:"
  echo "$EXISTING_CONSUMERS" | jq ".items[] | select(.name == \"${CLUSTER_ID}\")"
  echo ""
  log_info "If you need to re-register, delete the consumer first via the API"
  exit 0
fi

log_success "Consumer '${CLUSTER_ID}' not found, proceeding with registration"
echo ""

# =============================================================================
# Register Consumer
# =============================================================================

log_info "Registering management cluster consumer..."
log_info "  Name:       ${CLUSTER_ID}"
log_info "  Labels:     cluster_type=management, cluster_id=${CLUSTER_ID}"
echo ""

PAYLOAD=$(cat <<EOF
{
  "name": "${CLUSTER_ID}",
  "labels": {
    "cluster_type": "management",
    "cluster_id": "${CLUSTER_ID}"
  }
}
EOF
)

RESPONSE=$(awscurl -X POST "${API_GATEWAY_URL}/api/v0/management_clusters" \
  --service execute-api \
  --region "$AWS_REGION" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>&1)

# Check if the response indicates success
if echo "$RESPONSE" | jq -e '.name' &>/dev/null; then
  log_success "Consumer registered successfully!"
  echo ""
  echo "Response:"
  echo "$RESPONSE" | jq .
else
  log_error "Failed to register consumer"
  echo ""
  echo "Response:"
  echo "$RESPONSE"
  exit 1
fi

echo ""

# =============================================================================
# Verify Registration
# =============================================================================

log_info "Verifying consumer registration..."

VERIFY_RESPONSE=$(awscurl --service execute-api --region "$AWS_REGION" \
  "${API_GATEWAY_URL}/api/v0/management_clusters" 2>/dev/null || echo "")

if echo "$VERIFY_RESPONSE" | jq -e ".items[] | select(.name == \"${CLUSTER_ID}\")" &>/dev/null; then
  log_success "Consumer '${CLUSTER_ID}' verified in consumer list"
else
  log_warning "Consumer not found in list - registration may still be processing"
fi

echo ""

# =============================================================================
# Display Summary
# =============================================================================

echo "=============================================================================="
echo -e "${GREEN}Consumer Registration Complete!${NC}"
echo "=============================================================================="
echo ""
echo "Management cluster '${CLUSTER_ID}' is now registered as a Maestro consumer."
echo ""
echo "Consumer Details:"
echo "  Name:        ${CLUSTER_ID}"
echo "  API Gateway: ${API_GATEWAY_URL}"
echo "  Region:      ${AWS_REGION}"
echo ""
echo "=============================================================================="
echo "NEXT STEPS"
echo "=============================================================================="
echo ""
echo "1. Verify the management cluster's Maestro agent can connect:"
echo "   kubectl logs -n maestro deployment/maestro-agent -f"
echo ""
echo "2. Test payload distribution (see docs/full-region-provisioning.md Step 7)"
echo ""
echo "=============================================================================="
echo ""
