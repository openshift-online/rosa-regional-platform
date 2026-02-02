# =============================================================================
# Core cluster outputs
# =============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for kubectl"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

# =============================================================================
# Security outputs
# =============================================================================

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "node_security_group_id" {
  description = "EKS node security group ID (for Auto Mode, this is the cluster primary SG)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for EKS secrets encryption"
  value       = aws_kms_key.eks_secrets.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for EKS secrets encryption"
  value       = aws_kms_alias.eks_secrets.name
}

# =============================================================================
# Network outputs
# =============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways for high availability"
  value       = aws_nat_gateway.main[*].id
}

# Legacy compatibility outputs
output "private_subnets" {
  description = "Private subnet IDs where worker nodes are deployed (legacy compatibility)"
  value       = aws_subnet.private[*].id
}

# =============================================================================
# IAM outputs
# =============================================================================

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = aws_iam_role.eks_cluster.arn
}

output "node_iam_role_arn" {
  description = "IAM role ARN of the EKS Auto Mode nodes"
  value       = aws_iam_role.eks_auto_mode_node.arn
}

# =============================================================================
# Resource naming outputs
# =============================================================================

output "resource_name_base" {
  description = "Base name for resources (cluster_type-random_suffix)"
  value       = local.resource_name_base
}