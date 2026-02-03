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
#
# Usage:
#   ./bootstrap-central-account.sh [GITHUB_REPO_OWNER] [GITHUB_REPO_NAME] [GITHUB_BRANCH]
#
#   Or use environment variables:
#   GITHUB_REPO_OWNER=myorg GITHUB_REPO_NAME=myrepo ./bootstrap-central-account.sh
#
#   Or run interactively (prompts for values)
# =============================================================================

# Show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [GITHUB_REPO_OWNER] [GITHUB_REPO_NAME] [GITHUB_BRANCH]

Bootstrap the central AWS account with pipeline infrastructure.

ARGUMENTS:
    GITHUB_REPO_OWNER    GitHub organization or user (e.g., 'myorg')
    GITHUB_REPO_NAME     Repository name (e.g., 'rosa-regional-platform')
    GITHUB_BRANCH        Branch name (default: 'main')

OPTIONS:
    -h, --help          Show this help message
    -y, --yes           Skip confirmation prompts (non-interactive mode)

ENVIRONMENT VARIABLES:
    AUTO_APPROVE        Set to 'true' to skip confirmation prompts
    GITHUB_REPO_OWNER   GitHub repository owner
    GITHUB_REPO_NAME    GitHub repository name
    GITHUB_BRANCH       Git branch to track (default: main)
    AWS_PROFILE         AWS CLI profile to use

EXAMPLES:
    # Interactive mode (prompts for values)
    $0

    # With command-line arguments
    $0 theautoroboto rosa-regional-platform after-pull

    # With environment variables
    GITHUB_REPO_OWNER=myorg GITHUB_REPO_NAME=myrepo $0

    # Mix of arguments and defaults
    $0 theautoroboto rosa-regional-platform
EOF
}

# Parse flags
AUTO_APPROVE="${AUTO_APPROVE:-false}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit 0
            ;;
        -y|--yes)
            AUTO_APPROVE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
        *)
            # First positional argument found, stop parsing flags
            break
            ;;
    esac
done

# Determine repo root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 ROSA Regional Platform - Central Account Bootstrap"
echo "======================================================"
echo ""
echo "Repository Root: $REPO_ROOT"
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

# Parse command-line arguments or use environment variables with interactive fallback
if [ $# -ge 1 ]; then
    # Command-line arguments provided
    GITHUB_REPO_OWNER="$1"
    GITHUB_REPO_NAME="${2:-}"
    GITHUB_BRANCH="${3:-main}"
else
    # Check environment variables first, then prompt
    if [ -z "${GITHUB_REPO_OWNER:-}" ]; then
        read -p "GitHub Repository Owner (e.g., your-org): " GITHUB_REPO_OWNER
    fi

    if [ -z "${GITHUB_REPO_NAME:-}" ]; then
        read -p "GitHub Repository Name (e.g., rosa-regional-platform): " GITHUB_REPO_NAME
    fi

    if [ -z "${GITHUB_BRANCH:-}" ]; then
        read -p "GitHub Branch [main]: " input_branch
        GITHUB_BRANCH="${input_branch:-main}"
    fi
fi

# Validate inputs
if [ -z "$GITHUB_REPO_OWNER" ]; then
    echo "❌ Error: GitHub Repository Owner is required"
    echo "   Provide via: command-line argument, environment variable, or interactive prompt"
    exit 1
fi

if [ -z "$GITHUB_REPO_NAME" ]; then
    echo "❌ Error: GitHub Repository Name is required"
    echo "   Provide via: command-line argument, environment variable, or interactive prompt"
    exit 1
fi

# Set default branch if not provided
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

echo ""
echo "Configuration:"
echo "  Central Account ID: $ACCOUNT_ID"
echo "  AWS Region:         $REGION"
echo "  GitHub Repo:        $GITHUB_REPO_OWNER/$GITHUB_REPO_NAME"
echo "  GitHub Branch:      $GITHUB_BRANCH"
echo ""

if [ "$AUTO_APPROVE" != "true" ]; then
    read -p "Continue with bootstrap? [y/N]: " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "❌ Bootstrap cancelled."
        exit 1
    fi
else
    echo "✅ Auto-approve enabled, continuing..."
fi

echo ""
echo "==================================================="
echo "Step 1: Creating Terraform State Infrastructure"
echo "==================================================="

# Create state bucket and DynamoDB table
STATE_BUCKET="terraform-state-${ACCOUNT_ID}"
LOCK_TABLE="terraform-locks"

"${REPO_ROOT}/scripts/bootstrap-state.sh" "$REGION"

echo "✅ State infrastructure created:"
echo "   Bucket: $STATE_BUCKET"
echo "   Table:  $LOCK_TABLE"
echo ""

echo "==================================================="
echo "Step 2: Deploying Pipeline Infrastructure"
echo "==================================================="

cd "${REPO_ROOT}/terraform/config/bootstrap-pipeline"

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
if [ "$AUTO_APPROVE" != "true" ]; then
    read -p "Apply this plan? [y/N]: " APPLY_CONFIRM
    if [ "$APPLY_CONFIRM" != "y" ] && [ "$APPLY_CONFIRM" != "Y" ]; then
        echo "❌ Terraform apply cancelled."
        cd "${REPO_ROOT}"
        exit 1
    fi
else
    echo "✅ Auto-approve enabled, applying plan..."
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

cd "${REPO_ROOT}"
