# Bootstrap Pipeline

This directory contains the Terraform configuration to bootstrap the central AWS account with the pipeline infrastructure needed to deploy regional and management clusters.

## What This Deploys

The bootstrap pipeline creates **two CodePipeline pipelines** in your central AWS account:

1. **Regional Cluster Pipeline** (`pipeline-regional-cluster`)
   - Deploys regional EKS clusters to regional AWS accounts
   - Watches `deploy/*/regional.yaml` files
   - 3-stage pipeline: Validate → Deploy → Bootstrap

2. **Management Cluster Pipeline** (`pipeline-management-cluster`)
   - Deploys management EKS clusters to management AWS accounts
   - Watches `deploy/*/management/*.yaml` files
   - Provisions management cluster infrastructure

## Architecture

```
Central Account (you are here)
├── Regional Cluster Pipeline ──→ Deploys to Regional Accounts
└── Management Cluster Pipeline ──→ Deploys to Management Accounts
```

## Prerequisites

1. **AWS CLI** configured with central account credentials
2. **Terraform** >= 1.14.3 installed
3. **GitHub Repository** with this codebase
4. **AWS IAM Permissions** to create:
   - S3 buckets
   - CodePipeline resources
   - CodeBuild projects
   - IAM roles

## Quick Start

### Option 1: Automated Bootstrap (Recommended)

Run the bootstrap script from the repository root:

```bash
# With positional arguments (non-interactive)
./scripts/bootstrap-central-account.sh openshift-online rosa-regional-platform main

# Or with environment variables
GITHUB_REPO_OWNER=openshift-online GITHUB_REPO_NAME=rosa-regional-platform ./scripts/bootstrap-central-account.sh

# Or run interactively (will prompt for repository details)
./scripts/bootstrap-central-account.sh
```

The script will:
1. Create Terraform state infrastructure (S3 bucket with lockfile-based locking)
2. Deploy both pipeline infrastructures
3. Display next steps for GitHub authorization

### Option 2: Manual Bootstrap

#### Step 1: Create State Infrastructure

```bash
# From repository root
./scripts/bootstrap-state.sh us-east-1
```

This creates:
- S3 bucket: `terraform-state-{ACCOUNT_ID}` (with lockfile-based state locking)

#### Step 2: Deploy Bootstrap Pipeline

```bash
cd terraform/config/bootstrap-pipeline

# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Initialize Terraform
terraform init \
  -backend-config="bucket=terraform-state-${ACCOUNT_ID}" \
  -backend-config="key=bootstrap-pipeline/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
github_repo_owner = "openshift-online"  # Default organization
github_repo_name  = "rosa-regional-platform"
github_branch     = "main"
region            = "us-east-1"
EOF

# Apply
terraform apply -var-file=terraform.tfvars
```

#### Step 3: Authorize GitHub Connections

After Terraform completes:

1. Open AWS Console: [CodeSuite Settings](https://console.aws.amazon.com/codesuite/settings/connections)
2. Find connections in **PENDING** state:
   - `pipeline-provisioner-github` (Provisioner - shared by all pipelines)
   - `rc-gh-*` (Regional cluster pipelines - hash-based names)
   - `mc-gh-*` (Management cluster pipelines - hash-based names)
3. Click **"Update pending connection"** for each
4. Authorize with GitHub

## What Gets Created

### Provisioner Pipeline Resources (Shared)

- **CodePipeline**: `pipeline-provisioner`
- **CodeBuild Project**: `provisioner-build`
- **GitHub Connection**: `pipeline-provisioner-github`
- **S3 Artifact Bucket**: `provisioner-*`
- **IAM Roles**: CodePipeline and CodeBuild service roles

### Regional Cluster Pipeline Resources (Dynamically Created)

- **CodePipeline**: `rc-pipe-{hash}` (12-char hash)
- **CodeBuild Projects**: `rc-val-{hash}`, `rc-app-{hash}`, `rc-boot-{hash}`
- **GitHub Connection**: `rc-gh-{hash}`
- **S3 Artifact Bucket**: `rc-{hash}-{account-suffix}`
- **IAM Roles**: CodePipeline and CodeBuild service roles

### Management Cluster Pipeline Resources (Dynamically Created)

- **CodePipeline**: `mc-pipe-{hash}` (12-char hash)
- **CodeBuild Projects**: `mc-val-{hash}`, `mc-app-{hash}`, `mc-boot-{hash}`
- **GitHub Connection**: `mc-gh-{hash}`
- **S3 Artifact Bucket**: `mc-{hash}-{account-suffix}`
- **IAM Roles**: CodePipeline and CodeBuild service roles

**Note**: State is stored in the central account's `terraform-state-{ACCOUNT_ID}` bucket using lockfile-based locking.

## Using the Pipelines

After bootstrap completes, the pipelines automatically watch your repository for cluster definitions:

### Deploy a Regional Cluster

Create a YAML file at `deploy/<region-name>/regional.yaml`:

```yaml
account_id: "123456789012"  # Regional AWS account
region: "us-east-1"
alias: "regional-us-east-1"
```

Commit and push. The **Regional Cluster Pipeline** will:
1. Validate the configuration
2. Deploy EKS cluster to the regional account
3. Bootstrap ArgoCD

### Deploy a Management Cluster

Create a YAML file at `deploy/<region-name>/management/<cluster-name>.yaml`:

```yaml
account_id: "987654321098"  # Management AWS account
region: "us-east-1"
alias: "management01-us-east-1"
```

Commit and push. The **Management Cluster Pipeline** will:
1. Provision management cluster infrastructure
2. Bootstrap ArgoCD
3. Deploy HyperShift operators

## Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `github_repo_owner` | GitHub organization or user | - | Yes |
| `github_repo_name` | Repository name | - | Yes |
| `github_branch` | Branch to watch | `main` | No |
| `region` | AWS region for pipelines | `us-east-1` | No |
| `regional_target_account_id` | Manual override for regional target | `""` | No |
| `regional_target_region` | Manual override for regional region | `""` | No |
| `regional_target_alias` | Manual override for regional alias | `""` | No |
| `management_target_account_id` | Manual override for management target | `""` | No |
| `management_target_region` | Manual override for management region | `""` | No |
| `management_target_alias` | Manual override for management alias | `""` | No |

## Outputs

After `terraform apply`, you'll see:

- Pipeline names and ARNs
- GitHub connection ARNs (for authorization)
- Account and region information
- Next steps

## Cleanup

To destroy all bootstrap resources:

```bash
cd terraform/config/bootstrap-pipeline
terraform destroy -var-file=terraform.tfvars
```

**Warning**: This will destroy both pipelines. Regional and management clusters will continue running but won't be managed by pipelines anymore.

## Troubleshooting

### GitHub Connection Stuck in PENDING

**Symptom**: Pipeline fails with "Connection is not available"

**Solution**: Authorize the GitHub connection in AWS Console (see Step 3 above)

### State Lock Errors

**Symptom**: "Error acquiring the state lock"

**Solution**: The infrastructure uses S3 lockfile-based locking (Terraform 1.10+). Unlike DynamoDB locks, S3 lockfiles do **not** auto-expire. If you encounter a stale lock:
1. Ensure no other Terraform processes are running
2. Force unlock with:
   ```bash
   terraform force-unlock <LOCK_ID>
   ```
3. Alternatively, manually delete the lockfile object in S3 (located at `s3://terraform-state-{ACCOUNT_ID}/path/to/state.tfstate.tflock`)

### Permission Errors

**Symptom**: "UnauthorizedOperation" or "Access Denied"

**Solution**: Ensure your AWS credentials have permissions to:
- Create CodePipeline and CodeBuild resources
- Create S3 buckets
- Create IAM roles

## Next Steps

After bootstrap:

1. ✅ Authorize GitHub connections
2. 📝 Create cluster definition YAML files
3. 🚀 Commit and push to trigger deployments
4. 📊 Monitor pipeline executions in AWS Console

For detailed architecture documentation, see [docs/README.md](../../../docs/README.md).
