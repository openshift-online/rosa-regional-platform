provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Pipeline Provisioner Infrastructure
# =============================================================================
# This creates a meta-pipeline that watches the pipelines/ directory in the
# repository. When pipeline configuration files are added/updated, the
# provisioner dynamically creates the corresponding CodePipelines.
#
# Pipeline configurations are defined in YAML files:
# - pipelines/regional-<name>.yaml - Regional cluster pipelines
# - pipelines/management-<name>.yaml - Management cluster pipelines
# =============================================================================

module "pipeline_provisioner" {
  source = "../pipeline-provisioner"

  github_repo_owner = var.github_repo_owner
  github_repo_name  = var.github_repo_name
  github_branch     = var.github_branch
  region            = var.region
}
