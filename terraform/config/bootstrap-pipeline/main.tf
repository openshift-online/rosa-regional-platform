provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Regional Cluster Pipeline Infrastructure
# =============================================================================

module "pipeline_regional_cluster" {
  source = "../pipeline-regional-cluster"

  github_repo_owner = var.github_repo_owner
  github_repo_name  = var.github_repo_name
  github_branch     = var.github_branch
  region            = var.region

  # Optional manual override variables
  target_account_id = var.regional_target_account_id
  target_region     = var.regional_target_region
  target_alias      = var.regional_target_alias
}

# =============================================================================
# Management Cluster Pipeline Infrastructure
# =============================================================================

module "pipeline_management_cluster" {
  source = "../pipeline-management-cluster"

  github_repo_owner = var.github_repo_owner
  github_repo_name  = var.github_repo_name
  github_branch     = var.github_branch
  region            = var.region

  # Optional manual override variables
  target_account_id = var.management_target_account_id
  target_region     = var.management_target_region
  target_alias      = var.management_target_alias
}
