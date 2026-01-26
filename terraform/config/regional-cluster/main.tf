# =============================================================================
# Regional Cluster Infrastructure Configuration
# =============================================================================

# Configure AWS provider
provider "aws" {
  region = var.region_name

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
# API Gateway Module
# =============================================================================

module "api_gateway" {
  source = "../../modules/api-gateway"

  vpc_id                 = module.regional_cluster.vpc_id
  private_subnet_ids     = module.regional_cluster.private_subnets
  resource_name_base     = module.regional_cluster.resource_name_base
  node_security_group_id = module.regional_cluster.node_security_group_id
  cluster_name           = module.regional_cluster.cluster_name
}

# Maestro Infrastructure Module
# =============================================================================

# Call the Maestro infrastructure module for MQTT-based orchestration
module "maestro_infrastructure" {
  source = "../../modules/maestro-infrastructure"

  # Required variables from EKS cluster
  resource_name_base            = module.regional_cluster.resource_name_base
  vpc_id                        = module.regional_cluster.vpc_id
  private_subnets               = module.regional_cluster.private_subnets
  eks_cluster_name              = module.regional_cluster.cluster_name
  eks_cluster_security_group_id = module.regional_cluster.cluster_security_group_id

  # Bastion access (if enabled)
  bastion_security_group_id = var.enable_bastion ? module.bastion[0].security_group_id : null

  # Management cluster configuration
  management_cluster_count       = length(var.management_cluster_ids)
  management_cluster_ids         = var.management_cluster_ids
  management_cluster_account_ids = var.management_cluster_account_ids

  # Database configuration (adjust for production)
  db_instance_class      = var.maestro_db_instance_class
  db_multi_az           = var.maestro_db_multi_az
  db_deletion_protection = var.maestro_db_deletion_protection

  # MQTT topic prefix
  mqtt_topic_prefix = var.maestro_mqtt_topic_prefix
}
