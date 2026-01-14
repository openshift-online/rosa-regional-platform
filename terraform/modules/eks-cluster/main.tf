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
  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  # VPC and networking
  vpc_id     = module.vpc.vpc_id
  subnet_ids = concat(module.vpc.private_subnets, module.vpc.public_subnets)

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

  # EKS managed node groups in private subnets
  eks_managed_node_groups = {
    main = {
      account_id = data.aws_caller_identity.current.account_id
      partition  = data.aws_partition.current.partition

      # Node group configuration
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      disk_size      = var.node_disk_size
      disk_type      = "gp3"

      subnet_ids = module.vpc.private_subnets

      enable_irsa = false
      update_config = {
        max_unavailable_percentage = 25
      }

      tags = {
        "Name" = "${var.cluster_name}-main-node-group"
      }
    }
  }


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
  }

  # IAM configuration - using newer Pod Identity instead of IRSA
  enable_irsa = false

  tags = local.common_tags
}

