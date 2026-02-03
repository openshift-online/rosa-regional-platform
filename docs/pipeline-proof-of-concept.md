# AWS CodePipeline Proof-of-Concept

## Overview

Cross-account CodePipeline demonstrating ROSA Regional Platform infrastructure orchestration with 7-stage pipeline across CI, Regional, and Management AWS accounts.

## Quick Start

### 1. Deploy IAM Roles

```bash
cd terraform/config/pipeline-iam

# Edit with your account IDs
cp terraform.tfvars.example terraform.tfvars

# Create workspaces for separate state files
terraform init
terraform workspace new ci
terraform workspace new regional
terraform workspace new management

# Deploy to each account
# In your CI account
terraform workspace select ci
terraform apply -var="deployment_target=ci" -auto-approve

# In your Regional account
terraform workspace select regional
terraform apply -var="deployment_target=regional" -auto-approve

# In your Management account
terraform workspace select management
terraform apply -var="deployment_target=management" -auto-approve
```

### 2. Deploy Pipeline

```bash
cd terraform/config/pipeline

# In your CI account
terraform init
terraform apply
```

### 3. Activate CodeStar Connection (First Time Only)

1. Go to AWS Console → Developer Tools → CodePipeline → Settings → Connections
2. Find the newly created connection (status: PENDING)
3. Click "Update pending connection" and authorize GitHub access

### 4. Run Pipeline

```bash
aws codepipeline start-pipeline-execution \
  --name rosa-regional-platform-provisioning-integration \
  --region us-east-1
```

Pipeline will also trigger automatically on pushes to the branch of your repository provided through terraform variables of the pipeline.
