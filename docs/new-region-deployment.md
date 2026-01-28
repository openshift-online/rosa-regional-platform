# New Region Deployment Guide

This guide explains how to provision a complete new region with Regional and Management clusters using the `make new-region` target.

## Overview

The `make new-region` target provides an interactive, automated workflow for deploying a new region to the platform. It orchestrates account creation, infrastructure provisioning, and cluster deployment in a single command.

## What It Does

The target performs the following steps:

1. **Creates Region Definitions**: Generates two YAML files in `terraform/config/region-deploy/regions/`:
   - `{region}-regional.yaml` - Definition for the Regional Cluster account
   - `{region}-management.yaml` - Definition for the Management Cluster account

2. **Mints AWS Accounts**: Runs `terraform apply` in the `region-deploy` directory to create new AWS accounts via AWS Organizations

3. **Deploys Clusters**: For each newly minted account:
   - Assumes the `OrganizationAccountAccessRole`
   - Initializes Terraform backend with central state bucket
   - Calls `make pipeline-provision-regional` or `make pipeline-provision-management`
   - Provisions cluster infrastructure and bootstraps ArgoCD

## Prerequisites

### Required Environment Variables

```bash
export TF_STATE_BUCKET="regional-cluster-tf-state-xxxxx"  # From central-pipeline outputs
export TF_BACKEND_REGION="us-east-1"                      # Where state bucket lives
```

### Required Permissions

Your AWS credentials must have:
- `organizations:CreateAccount`
- `organizations:DescribeAccount`
- `organizations:ListAccounts`
- `sts:AssumeRole` on `arn:aws:iam::*:role/OrganizationAccountAccessRole`
- Full permissions in child accounts (via assumed role)

### Required Tools

- Terraform (>= 1.14)
- Python 3.11+
- boto3 (`pip install boto3`)
- AWS CLI configured

## Usage

### Interactive Mode

Run the target and follow the prompts:

```bash
make new-region
```

You'll be prompted for:

1. **Region name**: AWS region code (e.g., `us-west-2`)
2. **Base email**: Email prefix for account root emails (e.g., `aws-test`)
3. **Email domain**: Domain for emails (e.g., `example.com`)

### Example Session

```bash
$ make new-region

🌍 Testing Account Minting & Deployment Process
================================================

This target simulates the full pipeline workflow:
  1. Creates example region definition YAML files
  2. Mints AWS accounts via AWS Organizations
  3. Deploys Regional and Management clusters to new accounts

🔑 Current AWS Identity:
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/admin"
}

Enter test region name (e.g., us-west-2): us-west-2
Enter base email for accounts (e.g., aws-test): rosa-test
Enter email domain (e.g., example.com): example.com

📝 Configuration:
   Region: us-west-2
   Regional Account Email: rosa-test+regional-us-west-2@example.com
   Management Account Email: rosa-test+management-us-west-2@example.com

Proceed with account minting? [y/N]: y

📄 Creating region definition files...
✅ Created: terraform/config/region-deploy/regions/us-west-2-regional.yaml
✅ Created: terraform/config/region-deploy/regions/us-west-2-management.yaml

🏗️  Step 1: Minting AWS Accounts...
================================================
[Terraform output...]

✅ Accounts minted successfully!

📊 Reading account information...

🚀 Step 2: Deploying Clusters to New Accounts...
================================================

Found 2 accounts to provision

========================================
Processing: rosa-regional-us-west-2 (regional)
Account ID: 234567890123
Region: us-west-2
========================================

🔐 Assuming role: arn:aws:iam::234567890123:role/OrganizationAccountAccessRole
📦 Initializing Terraform backend...

🚀 Running make pipeline-provision-regional...
[Cluster deployment output...]

✅ regional cluster deployed successfully!

========================================
Processing: rosa-management-us-west-2 (management)
Account ID: 345678901234
Region: us-west-2
========================================

🔐 Assuming role: arn:aws:iam::345678901234:role/OrganizationAccountAccessRole
📦 Initializing Terraform backend...

🚀 Running make pipeline-provision-management...
[Cluster deployment output...]

✅ management cluster deployed successfully!

🎉 All clusters deployed successfully!

================================================
✅ Account Minting & Deployment Complete!
================================================

📋 Summary:
   Region: us-west-2
   Regional Cluster: Deployed
   Management Cluster: Deployed

🗑️  To clean up, run:
   rm terraform/config/region-deploy/regions/us-west-2-*.yaml
   cd terraform/config/region-deploy && terraform apply
```

## What Gets Created

### AWS Accounts

Two new AWS accounts are created in your Organization:

1. **Regional Cluster Account** (`rosa-regional-{region}`)
   - Contains EKS cluster for Regional Cluster
   - Runs core platform services (CLM, Maestro, Frontend API)

2. **Management Cluster Account** (`rosa-management-{region}`)
   - Contains EKS cluster for Management Cluster
   - Hosts customer control planes via HyperShift

### Infrastructure Components

In each account:

- **EKS Cluster** (fully private)
- **VPC** with private subnets
- **RDS Database** (Regional Cluster only - for CLM state)
- **ECS Bootstrap Tasks** (for private cluster initialization)
- **ArgoCD** (self-managing via GitOps)
- **IAM Roles** and security policies

### Terraform State

State for each cluster is stored in the central state bucket:

```
s3://{TF_STATE_BUCKET}/rosa-regional-{region}/terraform.tfstate
s3://{TF_STATE_BUCKET}/rosa-management-{region}/terraform.tfstate
```

## Cleanup

To remove the test deployment:

### 1. Delete the YAML Files

```bash
rm terraform/config/region-deploy/regions/{region}-*.yaml
```

### 2. Apply Region Deploy (Removes Accounts)

```bash
cd terraform/config/region-deploy
terraform apply
```

**Note**: Due to `close_on_deletion = false`, accounts will be removed from Terraform state but **not** closed in AWS. You must manually close accounts through the AWS Console if desired.

### 3. Clean Up Terraform State

Optionally remove state files from the central bucket:

```bash
aws s3 rm s3://${TF_STATE_BUCKET}/rosa-regional-{region}/ --recursive
aws s3 rm s3://${TF_STATE_BUCKET}/rosa-management-{region}/ --recursive
```

## Troubleshooting

### Account Creation Fails

**Problem**: AWS Organizations account creation fails

**Solutions**:
- Verify you're running in the Organization management account
- Check email addresses are unique (AWS requires globally unique account emails)
- Ensure you haven't hit AWS account limits

### Role Assumption Fails

**Problem**: Cannot assume `OrganizationAccountAccessRole`

**Solutions**:
- Wait 1-2 minutes after account creation for role to be available
- Verify the role exists in the child account
- Check your credentials have `sts:AssumeRole` permission

### Terraform Backend Issues

**Problem**: Cannot initialize Terraform backend

**Solutions**:
- Verify `TF_STATE_BUCKET` environment variable is set
- Check bucket policy allows organization-wide access
- Ensure credentials have S3 access to the state bucket

### boto3 Not Available

**Problem**: Warning about boto3 not being available

**Solution**: Install boto3:
```bash
pip install boto3
```

## How It Compares to Production Pipeline

This provisioning target is designed for operational use and follows the same workflow as the production CodePipeline:

**Core Components (Identical)**:
- Account minting process (`aws_organizations_account`)
- Role assumption pattern
- Terraform backend configuration
- Make targets (`pipeline-provision-*`)

**Execution Differences**:
1. **Interactive**: Prompts for region and email configuration vs. reading from YAML files in Git
2. **Local Execution**: Runs on your machine vs. CodeBuild environment
3. **Credentials**: Uses your AWS CLI credentials vs. CodeBuild service role
4. **Deployment**: Sequential cluster deployment vs. potentially parallel

**When to Use**:
- **`make new-region`**: For quick region provisioning, one-off deployments, or when you don't want to commit to Git yet
- **CodePipeline**: For GitOps-driven deployments, automated workflows, and production environments

## Related Documentation

- [Account Minting Process](account-minting-process.md)
- [Central Pipeline Configuration](../terraform/config/central-pipeline/README.md)
- [Region Deploy Configuration](../terraform/config/region-deploy/README.md)
- [Orchestration Script](../terraform/config/region-deploy/scripts/README.md)
