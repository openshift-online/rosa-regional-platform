# =============================================================================
# Regional Cluster Infrastructure Configuration
# =============================================================================

# Get current AWS region for auto-detection
data "aws_region" "current" {}

# Configure AWS provider
provider "aws" {
  default_tags {
    tags = {
      app-code      = var.app_code
      service-phase = var.service_phase
      cost-center   = var.cost_center
    }
  }
}

# Call the EKS cluster module for regional cluster infrastructure
module "regional_cluster" {
  source = "../../modules/eks-cluster"

  # Required variables
  cluster_type = "regional"
}

# Call the ECS bootstrap module for external bootstrap execution
module "ecs_bootstrap" {
  source = "../../modules/ecs-bootstrap"

  vpc_id                        = module.regional_cluster.vpc_id
  private_subnets               = module.regional_cluster.private_subnets
  eks_cluster_arn               = module.regional_cluster.cluster_arn
  eks_cluster_name              = module.regional_cluster.cluster_name
  eks_cluster_security_group_id = module.regional_cluster.cluster_security_group_id
  resource_name_base            = module.regional_cluster.resource_name_base

  # ArgoCD bootstrap configuration
  repository_url    = var.repository_url
  repository_path   = var.repository_path
  repository_branch = var.repository_branch

  # Cluster metadata for template rendering
  environment  = var.environment
  sector       = var.sector
  region       = data.aws_region.current.name
  cluster_type = "regional"
}

# =============================================================================
# Bastion Module (Optional)
# =============================================================================

module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../modules/bastion"

  resource_name_base        = module.regional_cluster.resource_name_base
  cluster_name              = module.regional_cluster.cluster_name
  cluster_endpoint          = module.regional_cluster.cluster_endpoint
  cluster_security_group_id = module.regional_cluster.cluster_security_group_id
  vpc_id                    = module.regional_cluster.vpc_id
  private_subnet_ids        = module.regional_cluster.private_subnets
}

# =============================================================================
# Outputs for Bootstrap Value Injection
# =============================================================================

output "environment" {
  description = "Environment identifier for the cluster"
  value       = var.environment
}

output "sector" {
  description = "Sector identifier for the cluster"
  value       = var.sector
}

output "region" {
  description = "AWS region (auto-detected from provider)"
  value       = data.aws_region.current.name
}

output "cluster_type" {
  description = "Type of cluster (regional or management)"
  value       = "regional"
}