# =============================================================================
# VPC and Networking Configuration
#
# This creates a dedicated VPC optimized for fully private EKS clusters.
# The VPC includes private subnets for worker nodes and public subnets
# for NAT gateways to provide controlled outbound internet access.
#
# Security design:
# - Private API endpoint only (no public API access)
# - Worker nodes in private subnets (no direct internet access)
# - Outbound internet via NAT gateway for updates and image pulls
# - Multi-AZ deployment for high availability
# =============================================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # Use auto-detected AZs if not provided, ensuring 3 AZs for proper EKS distribution
  azs             = local.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs # Minimal public subnets for NAT gateway only

  # NAT Gateway Configuration for Secure Outbound Access
  # - Required for EKS worker nodes to pull container images and receive updates
  # - Provides secure one-way internet access (outbound only)
  # - Single NAT gateway reduces costs while maintaining security
  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = false

  # DNS Configuration - Required for private EKS cluster communication
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Security: Do NOT auto-assign public IPs in public subnets
  # Public subnets are only for NAT gateway infrastructure
  map_public_ip_on_launch = false

  # EKS-specific subnet tags for INTERNAL load balancer discovery only
  # Note: NO external load balancer tags - this ensures only internal LBs are created
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    # Explicitly NOT setting "kubernetes.io/role/elb" to prevent external load balancers
  }

  # Private subnets: Worker nodes and internal load balancers only
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1" # Internal load balancers only
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = merge(
    var.tags,
    {
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}