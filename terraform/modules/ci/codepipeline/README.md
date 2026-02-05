# ROSA Regional Platform Pipeline - Quick Setup Guide

Complete proof-of-concept setup in 3 commands per account.

## Prerequisites

- 3 AWS accounts (CI, Regional, Management)
- AWS CLI configured with profiles for each account
- Terraform installed

## Quick Setup

### Step 1: Set Your Account IDs

```bash
export CI_ACCOUNT_ID="123456789012"
export REGIONAL_ACCOUNT_ID="123456789013"
export MANAGEMENT_ACCOUNT_ID="123456789014"
export AWS_REGION="us-east-1"
```

### Step 2: Deploy IAM Roles (one config, three targets)

**Setup once:**
```bash
cd terraform/config/pipeline-iam
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your account IDs
terraform init
```

**Deploy in each account:**
```bash
# CI Account
aws configure --profile ci-account
terraform apply -var="deployment_target=ci" -auto-approve

# Regional Account
terraform apply -var="deployment_target=regional" -auto-approve

# Management Account
terraform apply -var="deployment_target=management" -auto-approve
```

### Step 3: Deploy Pipeline (CI account only)

```bash
aws configure --profile ci-account
cd ../../../config/pipeline
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars - only need to set account IDs (ARNs auto-generated):
cat > terraform.tfvars <<EOF
regional_account_id = "$REGIONAL_ACCOUNT_ID"
management_account_id = "$MANAGEMENT_ACCOUNT_ID"
aws_region = "$AWS_REGION"
EOF

terraform init
terraform apply -auto-approve
```

### Step 4: Run Pipeline

```bash
aws codepipeline start-pipeline-execution \
  --name rosa-regional-platform-provisioning-integration \
  --region $AWS_REGION
```

### Step 5: Monitor Pipeline

```bash
# Check pipeline status
aws codepipeline get-pipeline-state \
  --name rosa-regional-platform-provisioning-integration \
  --region $AWS_REGION

# View in AWS Console
echo "Pipeline URL: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/rosa-regional-platform-provisioning-integration/view?region=$AWS_REGION"
```

## Verification

All pipeline stages should show echo commands with AWS account context verification. Check CloudWatch logs for each CodeBuild project to see cross-account role assumption working.

## Cleanup

```bash
# Delete pipeline (CI account)
cd terraform/config/pipeline
terraform destroy -auto-approve

# Delete IAM roles (each account)
cd ../../modules/ci/iam-cross-account
terraform destroy -var="deployment_target=TARGET" -var="ci_account_id=$CI_ACCOUNT_ID" -var="regional_account_id=$REGIONAL_ACCOUNT_ID" -var="management_account_id=$MANAGEMENT_ACCOUNT_ID" -auto-approve
```