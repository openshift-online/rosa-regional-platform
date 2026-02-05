# Pipeline Configuration for ROSA Regional Platform
#
# This configuration deploys the ROSA Regional Platform CodePipeline.
# IAM cross-account roles must be deployed manually in each account first.

# Configure the AWS provider
provider "aws" {
  region = var.aws_region

  # Default tags for all resources
  default_tags {
    tags = {
      Project     = "rosa-regional-platform"
      Component   = "ci-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "rosa-regional-platform"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for configuration
locals {
  # Account configuration
  ci_account_id         = data.aws_caller_identity.current.account_id
  regional_account_id   = var.regional_account_id
  management_account_id = var.management_account_id

  # Pipeline naming
  pipeline_name = "${var.pipeline_name_prefix}-${var.environment}"

  # Construct role ARNs
  regional_role_arn    = "arn:aws:iam::${local.regional_account_id}:role/rosa-pipeline-regional-access"
  management_role_arn  = "arn:aws:iam::${local.management_account_id}:role/rosa-pipeline-management-access"

  # Bucket naming with uniqueness
  artifacts_bucket_name = "${var.artifacts_bucket_prefix}-${var.environment}-${substr(sha256(local.ci_account_id), 0, 8)}"

  # Common tags
  common_tags = {
    Project     = "rosa-regional-platform"
    Component   = "ci-pipeline"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Deploy CodePipeline
# Note: Cross-account IAM roles must be deployed manually in each account before running this
module "codepipeline" {
  source = "../../modules/ci/codepipeline"

  # Pipeline configuration
  pipeline_name_prefix = var.pipeline_name_prefix
  environment         = var.environment
  aws_region          = var.aws_region

  # Cross-account configuration
  regional_account_id   = local.regional_account_id
  management_account_id = local.management_account_id
  regional_role_arn     = local.regional_role_arn
  management_role_arn   = local.management_role_arn

  # No GitHub configuration - pipeline runs manually

  # Artifact storage configuration
  artifacts_bucket_name    = local.artifacts_bucket_name
  kms_key_alias           = var.kms_key_alias
  artifacts_retention_days = var.artifacts_retention_days

  # CodeBuild configuration
  codebuild_compute_type     = var.codebuild_compute_type
  codebuild_image           = var.codebuild_image
  codebuild_timeout_minutes = var.codebuild_timeout_minutes

  # VPC, monitoring, and additional tags removed for simplicity
}