# =============================================================================
# Infrastructure Outputs for Bootstrap Configuration
# =============================================================================

# Cluster identification
output "cluster_name" {
  description = "EKS cluster name"
  value       = module.regional_cluster.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.regional_cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = module.regional_cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for kubectl"
  value       = module.regional_cluster.cluster_certificate_authority_data
  sensitive   = true
}

# Networking
output "vpc_id" {
  description = "VPC ID where cluster is deployed"
  value       = module.regional_cluster.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs where worker nodes are deployed"
  value       = module.regional_cluster.private_subnets
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.regional_cluster.cluster_security_group_id
}

output "node_security_group_id" {
  description = "EKS node/pod security group ID (Auto Mode primary SG)"
  value       = module.regional_cluster.node_security_group_id
}

# Resource naming
output "resource_name_base" {
  description = "Base name for resources (cluster_type-random_suffix)"
  value       = module.regional_cluster.resource_name_base
}

# =============================================================================
# ECS Bootstrap Outputs for External Script Usage
# =============================================================================

output "ecs_cluster_arn" {
  description = "ECS cluster ARN for bootstrap tasks"
  value       = module.ecs_bootstrap.ecs_cluster_arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name for bootstrap tasks"
  value       = module.ecs_bootstrap.ecs_cluster_name
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN for bootstrap execution"
  value       = module.ecs_bootstrap.task_definition_arn
}

output "bootstrap_log_group_name" {
  description = "CloudWatch log group name for bootstrap operations"
  value       = module.ecs_bootstrap.log_group_name
}

output "bootstrap_security_group_id" {
  description = "Security group ID for bootstrap ECS tasks"
  value       = module.ecs_bootstrap.bootstrap_security_group_id
}

# =============================================================================
# ArgoCD Bootstrap Configuration Outputs
# =============================================================================

output "repository_url" {
  description = "Git repository URL for cluster configuration"
  value       = module.ecs_bootstrap.repository_url
}

output "repository_branch" {
  description = "Git branch for cluster configuration"
  value       = module.ecs_bootstrap.repository_branch
}

# =============================================================================
# Bastion Outputs (only available when enable_bastion = true)
# =============================================================================

output "bastion_ecs_cluster_name" {
  description = "ECS cluster name for bastion tasks"
  value       = var.enable_bastion ? module.bastion[0].ecs_cluster_name : null
}

output "bastion_log_group_name" {
  description = "CloudWatch log group name for bastion logs"
  value       = var.enable_bastion ? module.bastion[0].log_group_name : null
}

output "bastion_run_task_command" {
  description = "AWS CLI command to start a bastion task"
  value       = var.enable_bastion ? module.bastion[0].run_task_command : null
}

output "bastion_exec_command_template" {
  description = "AWS CLI command template to connect to a running bastion (replace <TASK_ID>)"
  value       = var.enable_bastion ? module.bastion[0].exec_command_template : null
}

output "bastion_ssm_port_forward_template" {
  description = "AWS CLI command template for SSM port forwarding (replace <TASK_ID> and <RUNTIME_ID>)"
  value       = var.enable_bastion ? module.bastion[0].ssm_port_forward_template : null
}

# =============================================================================
# API Gateway Outputs
# =============================================================================

output "api_gateway_invoke_url" {
  description = "API Gateway invoke URL for testing"
  value       = module.api_gateway.invoke_url
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = module.api_gateway.api_gateway_id
}

output "api_target_group_arn" {
  description = "Target group ARN for TargetGroupBinding in Kubernetes"
  value       = module.api_gateway.target_group_arn
}

output "api_allowed_accounts" {
  description = "Frontend API allowed accounts (comma-separated account IDs, including current account)"
  value       = var.api_additional_allowed_accounts != "" ? "${data.aws_caller_identity.current.account_id},${var.api_additional_allowed_accounts}" : data.aws_caller_identity.current.account_id
}

output "api_alb_dns_name" {
  description = "Internal ALB DNS name"
  value       = module.api_gateway.alb_dns_name
}

output "api_alb_security_group_id" {
  description = "ALB security group ID"
  value       = module.api_gateway.alb_security_group_id
}

output "api_test_command" {
  description = "awscurl command to test the API"
  value       = module.api_gateway.test_command
}

# Maestro Infrastructure Outputs
# =============================================================================

# AWS IoT Core
output "maestro_iot_mqtt_endpoint" {
  description = "AWS IoT Core MQTT endpoint for Maestro broker connection"
  value       = module.maestro_infrastructure.iot_mqtt_endpoint
}

# RDS Database
output "maestro_rds_endpoint" {
  description = "Maestro RDS PostgreSQL endpoint (hostname:port)"
  value       = module.maestro_infrastructure.rds_endpoint
}

output "maestro_rds_address" {
  description = "Maestro RDS PostgreSQL hostname"
  value       = module.maestro_infrastructure.rds_address
}

output "maestro_rds_port" {
  description = "Maestro RDS PostgreSQL port"
  value       = module.maestro_infrastructure.rds_port
}

# Secrets Manager
output "maestro_server_cert_secret_name" {
  description = "Secrets Manager secret name for Maestro Server certificate material"
  value       = module.maestro_infrastructure.maestro_server_cert_secret_name
}

output "maestro_server_config_secret_name" {
  description = "Secrets Manager secret name for Maestro Server MQTT configuration"
  value       = module.maestro_infrastructure.maestro_server_config_secret_name
}

output "maestro_db_credentials_secret_name" {
  description = "Secrets Manager secret name for Maestro database credentials"
  value       = module.maestro_infrastructure.maestro_db_credentials_secret_name
}

# IAM Roles
output "maestro_server_role_arn" {
  description = "IAM role ARN for Maestro Server (Pod Identity)"
  value       = module.maestro_infrastructure.maestro_server_role_arn
}

# Configuration Summary
output "maestro_configuration_summary" {
  description = "Complete Maestro configuration for use in Helm values"
  value       = module.maestro_infrastructure.maestro_configuration_summary
  sensitive   = false
}
