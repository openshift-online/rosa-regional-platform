# =============================================================================
# VPC and Networking Configuration
#
# Creates a fully private EKS networking environment with:
# - Multi-AZ private/public subnets for high availability
# - Per-AZ NAT Gateways for fault-tolerant egress
# - VPC endpoints for AWS service access without internet routing
# - Security groups with least-privilege access controls
# =============================================================================

# -----------------------------------------------------------------------------
# VPC and Internet Gateway
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr # Recommended: 10.0.0.0/16
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.resource_name_base}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.resource_name_base}-igw" }
}

# -----------------------------------------------------------------------------
# Subnets
#
# Public subnets: Small /24s for NAT gateways and load balancer entry points
# Private subnets: Worker nodes and pods (no direct internet access)
# -----------------------------------------------------------------------------

# Public Subnets (Small /24s - Only for NAT and Entry Points)
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                     = "${local.resource_name_base}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets (/19s - 8,187 IPs each for High Pod Density)
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                                                = "${local.resource_name_base}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${local.resource_name_base}" = "owned"
  }
}

# -----------------------------------------------------------------------------
# NAT Gateways for Internet Egress
#
# Multi-AZ deployment provides high availability for external connectivity.
# Each AZ has its own NAT Gateway to eliminate single points of failure.
# Used for container image pulls from external registries.
# -----------------------------------------------------------------------------

# Create one NAT Gateway per Availability Zone for high availability
resource "aws_eip" "nat" {
  count  = length(aws_subnet.public)
  domain = "vpc"
  tags = {
    Name = "${local.resource_name_base}-nat-eip-${local.azs[count.index]}"
  }
}

resource "aws_nat_gateway" "main" {
  count         = length(aws_subnet.public)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]
  tags = {
    Name = "${local.resource_name_base}-nat-gw-${local.azs[count.index]}"
  }
}

# -----------------------------------------------------------------------------
# VPC Endpoints for AWS Services
#
# Keeps AWS API traffic within the VPC, reducing costs and improving security:
# - S3 Gateway Endpoint: Free, optimizes S3 access for container images
# - Interface Endpoints: EKS, ECR, STS for cluster operations
# All use dedicated security group for least-privilege access.
# -----------------------------------------------------------------------------

# S3 Gateway Endpoint (Free - Bypasses NAT for image layers/S3 data)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  tags              = { Name = "${local.resource_name_base}-s3-endpoint" }
}

# Interface Endpoints (Keep EKS, ECR, and STS traffic off the NAT)
locals {
  services = ["ecr.api", "ecr.dkr", "sts", "logs", "ec2"]
}

resource "aws_vpc_endpoint" "interfaces" {
  for_each            = toset(local.services)
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "${local.resource_name_base}-${each.value}-endpoint" }
}

# -----------------------------------------------------------------------------
# Routing Tables
#
# Public routes: Direct traffic through Internet Gateway
# Private routes: Per-AZ tables route traffic through local NAT Gateway
# S3 Gateway Endpoint routes are automatically added to private tables
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.resource_name_base}-public-rt" }
}

# Create separate route table for each AZ to route to its local NAT Gateway
resource "aws_route_table" "private" {
  count  = length(aws_subnet.private)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${local.resource_name_base}-private-rt-${local.azs[count.index]}"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# Security Groups
#
# Network access controls following least-privilege principles:
# - EKS Cluster SG: Limited egress for registries and VPC internal traffic
# - VPC Endpoints SG: Dedicated security group for AWS service access (port 443 only)
# Provides network segmentation and audit trail for all traffic flows.
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.resource_name_base}-cluster-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.resource_name_base}-cluster-sg" }
}

# Dedicated security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${local.resource_name_base}-vpc-endpoints-sg"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.resource_name_base}-vpc-endpoints-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "Allow HTTPS from VPC CIDR for AWS service access"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "cluster_https" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow VPC to communicate with API Server"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

# Allow HTTPS for container image pulls (Quay.io, Red Hat registries)
resource "aws_vpc_security_group_egress_rule" "cluster_https_registries" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow HTTPS for container registries (Quay.io, Red Hat)"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Allow all traffic within VPC for internal service communication
resource "aws_vpc_security_group_egress_rule" "cluster_vpc_internal" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow all internal VPC communication"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}