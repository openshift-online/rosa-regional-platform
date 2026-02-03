#!/bin/bash
set -e

# Usage: ./scripts/destroy-region.sh <ACCOUNT_ID> <REGION> <ALIAS>
# Example: ./scripts/destroy-region.sh 123456789012 us-east-1 prod-cluster

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <ACCOUNT_ID> <REGION> <ALIAS>"
    echo "Example: $0 123456789012 us-east-1 prod-cluster"
    exit 1
fi

ACCOUNT_ID=$1
REGION=$2
ALIAS=$3

# Determine Repo Root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "WARNING: You are about to DESTROY the Regional Deployment for:"
echo "  Account: $ACCOUNT_ID"
echo "  Region:  $REGION"
echo "  Alias:   $ALIAS"
echo "This includes the Regional Cluster (EKS) and Regional Infrastructure (Pipeline)."
echo ""
read -p "Are you sure you want to proceed? (Type 'destroy' to confirm): " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
    echo "Operation cancelled."
    exit 1
fi

# 1. Setup Environment & Credentials
# We assume the user is running this with credentials for the CENTRAL account (where state lives).
CENTRAL_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TF_STATE_BUCKET="terraform-state-${CENTRAL_ACCOUNT_ID}"

# Detect Bucket Region
if ! BUCKET_REGION=$(aws s3api get-bucket-location --bucket $TF_STATE_BUCKET --query LocationConstraint --output text 2>/dev/null); then
    echo "❌ Error: Could not find state bucket '$TF_STATE_BUCKET'."
    echo "   Current Account ID: $CENTRAL_ACCOUNT_ID"
    echo "   Please ensure you are authenticated to the CENTRAL Account where the state bucket resides."
    exit 1
fi

if [ "$BUCKET_REGION" == "None" ] || [ -z "$BUCKET_REGION" ]; then BUCKET_REGION="us-east-1"; fi
TF_STATE_REGION=$BUCKET_REGION

echo "Using State Bucket: $TF_STATE_BUCKET (Region: $TF_STATE_REGION)"

# Role to assume in the TARGET (Regional) account for provisioning/destroying resources
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole"

# Repository Info (needed for variable validation)
GITHUB_REPO_OWNER="placeholder-owner"
GITHUB_REPO_NAME="placeholder-repo"
# Try to detect if inside a git repo
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    REPO_URL=$(git config --get remote.origin.url)
    # Extract owner/name from URL if possible, otherwise keep placeholders
    # This is a best-effort to make variables look real
    export TF_VAR_repository_url="$REPO_URL"
else
    export TF_VAR_repository_url="https://github.com/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}.git"
fi

export TF_VAR_repository_branch="main"
export TF_VAR_github_repo_owner=$GITHUB_REPO_OWNER
export TF_VAR_github_repo_name=$GITHUB_REPO_NAME
export TF_VAR_github_branch="main"
export TF_VAR_region=$REGION
export TF_VAR_region_name=$REGION
export TF_VAR_assume_role_arn=$ROLE_ARN

# Dummy variables for validation
export TF_VAR_app_code="infra"
export TF_VAR_service_phase="prod"
export TF_VAR_cost_center="000"


# ==============================================================================
# PHASE 1: Destroy Regional Cluster
# ==============================================================================
echo "----------------------------------------------------------------"
echo "Phase 1: Destroying Regional Cluster..."
echo "----------------------------------------------------------------"

cd "${REPO_ROOT}/terraform/config/regional-cluster"

TF_STATE_KEY="regional-cluster/${ALIAS}.tfstate"

echo "Initializing Terraform (Regional Cluster)..."
terraform init \
    -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="key=$TF_STATE_KEY" \
    -backend-config="region=$TF_STATE_REGION" \
    -backend-config="use_lockfile=true"

echo "Destroying Regional Cluster Resources..."
terraform destroy -auto-approve

rm -rf .terraform .terraform.lock.hcl
cd - > /dev/null

# ==============================================================================
# PHASE 2: Destroy Regional Infra (Pipeline)
# ==============================================================================
echo "----------------------------------------------------------------"
echo "Phase 2: Destroying Regional Infrastructure..."
echo "----------------------------------------------------------------"

cd "${REPO_ROOT}/terraform/config/pipeline-management-cluster"

TF_STATE_KEY_INFRA="pipeline-management-cluster/${ALIAS}.tfstate"

# Cleanup Pipeline Artifacts Bucket (to avoid destroy failure if not empty)
echo "Cleaning up Pipeline Artifacts in Regional Account..."
CREDS=$(aws sts assume-role --role-arn $ROLE_ARN --role-session-name RegionalCleanup --output json)
export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)

# Find buckets starting with regional-pipeline-artifacts-
BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'regional-pipeline-artifacts-')].Name" --output text)
for BUCKET in $BUCKETS; do
    if [ "$BUCKET" == "None" ]; then continue; fi
    # Check region
    LOC=$(aws s3api get-bucket-location --bucket $BUCKET --query LocationConstraint --output text 2>/dev/null)
    if [ "$LOC" == "None" ]; then LOC="us-east-1"; fi
    
    if [ "$LOC" == "$REGION" ]; then
        echo "Emptying bucket: $BUCKET"
        aws s3 rm "s3://${BUCKET}" --recursive
    fi
done

# Revert to Central Account credentials for Terraform Backend access
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

echo "Initializing Terraform (Regional Infra)..."
terraform init \
    -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="key=$TF_STATE_KEY_INFRA" \
    -backend-config="region=$TF_STATE_REGION" \
    -backend-config="use_lockfile=true"

echo "Destroying Regional Infra Resources..."
terraform destroy -auto-approve

rm -rf .terraform .terraform.lock.hcl
cd - > /dev/null

echo "----------------------------------------------------------------"
echo "✅ Destruction Complete."
echo "----------------------------------------------------------------"
