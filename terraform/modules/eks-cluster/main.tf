# =============================================================================
# EKS Cluster Module
#
# This module creates a private EKS cluster as a base for both management 
# and regional clusters with security-first configuration.
# The EKS cluster will contain resources for Kubernetes workloads, including:
# - Fully private EKS control plane
# - Managed node groups in private subnets
# - VPC with multi-AZ deployment
# - Pod Identity for workload authentication
# - EKS managed addons (CoreDNS, VPC CNI, EBS CSI, etc.)
# =============================================================================

# =============================================================================
# Data Sources
# =============================================================================

# Availability zones for high availability deployment
data "aws_availability_zones" "available" {
  state = "available"
}

# Current AWS account information
data "aws_caller_identity" "current" {}

# Current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# =============================================================================
# EKS Cluster Configuration
# =============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.14"

  # Cluster configuration
  name               = local.resource_name_base
  kubernetes_version = var.cluster_version

  # VPC and networking
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # Auto Mode nodes use private subnets with NAT gateway

  # EKS Auto Mode - Automatic compute provisioning and scaling
  # https://docs.aws.amazon.com/eks/latest/userguide/create-node-pool.html
  # To look at how to construct our own pools
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  # Fully private endpoint for security
  endpoint_public_access  = false
  endpoint_private_access = true

  # Control plane logging for audit and compliance
  enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  # Essential EKS managed addons
  addons = {
    coredns = {}

    kube-proxy = {}

    vpc-cni = {
      before_compute              = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }

    eks-pod-identity-agent = {}

    aws-ebs-csi-driver = {}

    metrics-server = {}

    # AWS Secrets Store CSI Driver Provider for Maestro agent secret mounting
    aws-secrets-store-csi-driver-provider = {
      service_account_role_arn        = null
    }
  }

  # IAM configuration
  enable_irsa = false
}

