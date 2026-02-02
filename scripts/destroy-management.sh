#!/bin/bash
set -e

# Usage: ./scripts/destroy-management.sh <MANAGEMENT_ACCOUNT_ID> <REGION> <ALIAS>
# Example: ./scripts/destroy-management.sh 123456789012 us-east-1 prod-mgmt

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <MANAGEMENT_ACCOUNT_ID> <REGION> <ALIAS>"
    echo "Example: $0 123456789012 us-east-1 prod-mgmt"
    exit 1
fi

MANAGEMENT_ACCOUNT_ID=$1
REGION=$2
ALIAS=$3

# Determine Repo Root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Directory for Management Cluster config
TF_DIR="${REPO_ROOT}/terraform/config/management-cluster"
OVERRIDE_FILE="${TF_DIR}/override.tf"

if [ ! -d "$TF_DIR" ]; then
    echo "❌ Error: Terraform directory not found at:"
    echo "   $TF_DIR"
    exit 1
fi

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    rm -f "$OVERRIDE_FILE"
}
trap cleanup EXIT

echo "WARNING: You are about to DESTROY the Management Cluster for:"
echo "  Management Account: $MANAGEMENT_ACCOUNT_ID"
echo "  Region:             $REGION"
echo "  Alias:              $ALIAS"
echo ""
echo "Ensure you are authenticated to the REGIONAL Account (where the state bucket resides)."
echo ""
read -p "Are you sure you want to proceed? (Type 'destroy' to confirm): " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
    echo "Operation cancelled."
    exit 1
fi

# 1. Setup Environment & Backend Info
# We assume the user is running this with credentials for the REGIONAL account.
REGIONAL_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TF_STATE_BUCKET="terraform-state-management-${REGIONAL_ACCOUNT_ID}"
TF_STATE_DYNAMODB_TABLE="terraform-locks-management"
TF_STATE_KEY="management-cluster/${ALIAS}.tfstate"

# Detect Bucket Region
echo "Detecting State Bucket Region..."
if ! BUCKET_REGION=$(aws s3api get-bucket-location --bucket $TF_STATE_BUCKET --query LocationConstraint --output text 2>/dev/null); then
    echo "❌ Error: Could not find state bucket '$TF_STATE_BUCKET'."
    echo "   Current Account ID: $REGIONAL_ACCOUNT_ID"
    echo "   Please ensure you are authenticated to the REGIONAL Account where the infrastructure was provisioned."
    exit 1
fi

if [ "$BUCKET_REGION" == "None" ] || [ -z "$BUCKET_REGION" ]; then BUCKET_REGION="us-east-1"; fi
TF_STATE_REGION=$BUCKET_REGION

echo "Using State Bucket: $TF_STATE_BUCKET (Region: $TF_STATE_REGION)"

# 2. Generate override.tf for Cross-Account Assumption
# The management-cluster/main.tf does not support assume_role variable, so we override the provider.
echo "Generating override.tf for cross-account access..."
cat <<EOF > "$OVERRIDE_FILE"
provider "aws" {
  assume_role {
    role_arn = "arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:role/OrganizationAccountAccessRole"
  }
}
EOF

# 3. Initialize and Destroy
echo "----------------------------------------------------------------"
echo "Phase 1: Destroying Management Cluster..."
echo "----------------------------------------------------------------"

cd "$TF_DIR"

echo "Initializing Terraform..."
terraform init \
    -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="key=$TF_STATE_KEY" \
    -backend-config="region=$TF_STATE_REGION" \
    -backend-config="dynamodb_table=$TF_STATE_DYNAMODB_TABLE"

# Set required variables for validation (values don't matter for destroy, but must be present)
export TF_VAR_cluster_id="$ALIAS"
export TF_VAR_regional_aws_account_id="$REGIONAL_ACCOUNT_ID"
export TF_VAR_repository_url="https://github.com/placeholder/repo"
export TF_VAR_repository_branch="main"
export TF_VAR_app_code="infra"
export TF_VAR_service_phase="prod"
export TF_VAR_cost_center="000"
# Some modules might require these
export TF_VAR_region="$REGION"

echo "Destroying Management Cluster Resources..."
terraform destroy -auto-approve

rm -rf .terraform .terraform.lock.hcl
cd - > /dev/null

echo "----------------------------------------------------------------"
echo "✅ Destruction Complete."
echo "----------------------------------------------------------------"
