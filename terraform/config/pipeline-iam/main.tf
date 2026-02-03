# ROSA Pipeline IAM Roles Configuration
# Deploy this in each account with the appropriate deployment_target

# Configure AWS provider to use current CLI profile/credentials
provider "aws" {
}

module "pipeline_iam" {
  source = "../../modules/ci/iam-cross-account"

  # Which account type to deploy roles for: "ci", "regional", or "management"
  deployment_target = var.deployment_target

  ci_account_id         = var.ci_account_id
  regional_account_id   = var.regional_account_id
  management_account_id = var.management_account_id
}