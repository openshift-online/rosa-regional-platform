# =============================================================================
# Regional Cluster Infrastructure Configuration
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
  region_name            = var.region_name
  node_security_group_id = module.regional_cluster.node_security_group_id
}

# =============================================================================
# AWS Load Balancer Controller - IAM Resources
# Required for TargetGroupBinding to work with API Gateway
#
# NOTE: The EKS addon for aws-load-balancer-controller is NOT available for
# Kubernetes 1.34. Install the controller via Helm from the bastion:
#   ./scripts/install-aws-load-balancer-controller-helm.sh \
#     --cluster-name <cluster-name> \
#     --vpc-id <vpc-id> \
#     --region <region>
# =============================================================================

# IAM Role for AWS Load Balancer Controller with Pod Identity trust
resource "aws_iam_role" "aws_lbc" {
  name = "${module.regional_cluster.resource_name_base}-aws-lbc"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = {
    Purpose        = "AWS-Load-Balancer-Controller"
    Environment    = var.service_phase
    ManagedBy      = "terraform"
  }
}

# IAM Policy for AWS Load Balancer Controller
# Based on: https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json
resource "aws_iam_policy" "aws_lbc" {
  name        = "${module.regional_cluster.resource_name_base}-aws-lbc"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = file("${path.module}/policies/aws-load-balancer-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  role       = aws_iam_role.aws_lbc.name
  policy_arn = aws_iam_policy.aws_lbc.arn
}

# Pod Identity Association - Links the Kubernetes service account to the IAM role
# This allows the controller pods to assume the IAM role
resource "aws_eks_pod_identity_association" "aws_lbc" {
  cluster_name    = module.regional_cluster.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lbc.arn

  tags = {
    Purpose     = "AWS-Load-Balancer-Controller"
    Environment = var.service_phase
  }
}