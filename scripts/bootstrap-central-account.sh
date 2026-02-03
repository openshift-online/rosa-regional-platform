#!/bin/bash
set -euo pipefail

# =============================================================================
# Bootstrap Central AWS Account
# =============================================================================
# This script bootstraps the central AWS account with:
# 1. Terraform state infrastructure (S3 bucket + DynamoDB table)
# 2. Regional cluster pipeline infrastructure
# 3. Management cluster pipeline infrastructure
#
# Prerequisites:
# - AWS CLI configured with central account credentials
# - Terraform >= 1.14.3 installed
# - GitHub repository set up
# =============================================================================

echo "🚀 ROSA Regional Platform - Central Account Bootstrap"
echo "======================================================"
echo ""

# Check prerequisites
if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI not found. Please install AWS CLI."
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "❌ Error: Terraform not found. Please install Terraform >= 1.14.3"
    exit 1
fi

# Get current AWS identity
echo "Checking AWS credentials..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

echo "✅ Authenticated as:"
aws sts get-caller-identity
echo ""

# Prompt for GitHub details
read -p "GitHub Repository Owner (e.g., your-org): " GITHUB_REPO_OWNER
read -p "GitHub Repository Name (e.g., rosa-regional-platform): " GITHUB_REPO_NAME
read -p "GitHub Branch [main]: " GITHUB_BRANCH
GITHUB_BRANCH=${GITHUB_BRANCH:-main}

echo ""
echo "Configuration:"
echo "  Central Account ID: $ACCOUNT_ID"
echo "  AWS Region:         $REGION"
echo "  GitHub Repo:        $GITHUB_REPO_OWNER/$GITHUB_REPO_NAME"
echo "  GitHub Branch:      $GITHUB_BRANCH"
echo ""

read -p "Continue with bootstrap? [y/N]: " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "❌ Bootstrap cancelled."
    exit 1
fi

echo ""
echo "==================================================="
echo "Step 1: Creating Terraform State Infrastructure"
echo "==================================================="

# Create state bucket and DynamoDB table
STATE_BUCKET="terraform-state-${ACCOUNT_ID}"
LOCK_TABLE="terraform-locks"

./scripts/bootstrap-state.sh "$REGION"

echo "✅ State infrastructure created:"
echo "   Bucket: $STATE_BUCKET"
echo "   Table:  $LOCK_TABLE"
echo ""

echo "==================================================="
echo "Step 2: Deploying Pipeline Infrastructure"
echo "==================================================="

cd terraform/config/bootstrap-pipeline

# Initialize Terraform
echo "Initializing Terraform..."
terraform init \
    -backend-config="bucket=${STATE_BUCKET}" \
    -backend-config="key=bootstrap-pipeline/terraform.tfstate" \
    -backend-config="region=${REGION}" \
    -backend-config="dynamodb_table=${LOCK_TABLE}"

# Create tfvars file
cat > terraform.tfvars <<EOF
github_repo_owner = "${GITHUB_REPO_OWNER}"
github_repo_name  = "${GITHUB_REPO_NAME}"
github_branch     = "${GITHUB_BRANCH}"
region            = "${REGION}"
EOF

echo "Terraform configuration created:"
cat terraform.tfvars
echo ""

# Run terraform plan
echo "Running Terraform plan..."
terraform plan -var-file=terraform.tfvars -out=tfplan

echo ""
read -p "Apply this plan? [y/N]: " APPLY_CONFIRM
if [ "$APPLY_CONFIRM" != "y" ] && [ "$APPLY_CONFIRM" != "Y" ]; then
    echo "❌ Terraform apply cancelled."
    cd ../../..
    exit 1
fi

# Apply
echo "Applying Terraform configuration..."
terraform apply tfplan

echo ""
echo "==================================================="
echo "✅ Bootstrap Complete!"
echo "==================================================="
echo ""

terraform output -raw next_steps
echo ""
echo ""
echo "🔗 GitHub Connection Authorization:"
echo "   1. Open AWS Console: https://console.aws.amazon.com/codesuite/settings/connections"
echo "   2. Find connections in PENDING state"
echo "   3. Click 'Update pending connection' and authorize with GitHub"
echo ""
echo "📝 To deploy clusters, create YAML files in your repository:"
echo "   - Regional:    deploy/<name>/regional.yaml"
echo "   - Management:  deploy/<name>/management/*.yaml"
echo ""

cd ../../..
