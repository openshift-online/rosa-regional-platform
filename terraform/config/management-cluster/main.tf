# =============================================================================
# Management Cluster Infrastructure Configuration
# =============================================================================

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

# Call the EKS cluster module for management cluster infrastructure
module "management_cluster" {
  source = "../../modules/eks-cluster"

  # Required variables
  cluster_type = "management"

  # Management cluster sizing
  node_group_min_size     = 1
  node_group_max_size     = 2
  node_group_desired_size = 1
}

# Call the ECS bootstrap module for external bootstrap execution
module "ecs_bootstrap" {
  source = "../../modules/ecs-bootstrap"

  vpc_id                        = module.management_cluster.vpc_id
  private_subnets               = module.management_cluster.private_subnets
  eks_cluster_arn               = module.management_cluster.cluster_arn
  eks_cluster_name              = module.management_cluster.cluster_name
  eks_cluster_security_group_id = module.management_cluster.cluster_security_group_id
  resource_name_base            = module.management_cluster.resource_name_base

  # ArgoCD bootstrap configuration
  repository_url    = var.repository_url
  repository_path   = var.repository_path
  repository_branch = var.repository_branch
}

# =============================================================================
# Bastion Module (Optional)
# =============================================================================

module "bastion" {
  count  = var.enable_bastion ? 1 : 0
  source = "../../modules/bastion"

  resource_name_base        = module.management_cluster.resource_name_base
  cluster_name              = module.management_cluster.cluster_name
  cluster_endpoint          = module.management_cluster.cluster_endpoint
  cluster_security_group_id = module.management_cluster.cluster_security_group_id
  vpc_id                    = module.management_cluster.vpc_id
  private_subnet_ids        = module.management_cluster.private_subnets
}

module "maestro_agent" {                                                                                                                                                                    
  source = "../../modules/maestro-agent"                                                                                                                                                    
                                                                                                                                                                                            
  cluster_id              = var.cluster_id                                                                                                                                                  
  regional_aws_account_id = var.regional_aws_account_id                                                                                                                                     
  eks_cluster_name        = module.management_cluster.cluster_name                                                                                                                          
}