# IAM Cross-Account Module for ROSA Pipeline

Creates IAM roles for cross-account access in ROSA Regional Platform CI/CD pipeline.

**IMPORTANT**: Deploy this module manually in each account before running the main pipeline.

## Usage

Deploy roles to each account using the `deployment_target` parameter:

```bash
cd terraform/modules/ci/iam-cross-account
terraform init

# CI Account (deployment_target=ci)
terraform apply -var="deployment_target=ci" -var="ci_account_id=123456789012" -var="regional_account_id=123456789013" -var="management_account_id=123456789014"

# Regional Account (deployment_target=regional)
terraform apply -var="deployment_target=regional" -var="ci_account_id=123456789012" -var="regional_account_id=123456789013" -var="management_account_id=123456789014"

# Management Account (deployment_target=management)
terraform apply -var="deployment_target=management" -var="ci_account_id=123456789012" -var="regional_account_id=123456789013" -var="management_account_id=123456789014"
```

## Roles Created

- **CI Account**: Pipeline execution roles that assume cross-account roles
- **Regional Account**: `rosa-pipeline-regional-access` (AdministratorAccess)
- **Management Account**: `rosa-pipeline-management-access` (AdministratorAccess)

**Note**: Uses broad permissions for PoC. Restrict to least privilege in production.