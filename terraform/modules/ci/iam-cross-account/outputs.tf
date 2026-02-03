# Outputs for IAM Cross-Account Module

# CI Account Role Outputs
output "pipeline_execution_role_arn" {
  description = "ARN of the CI account pipeline execution role"
  value       = local.create_ci_roles ? aws_iam_role.pipeline_execution[0].arn : null
}

output "pipeline_execution_role_name" {
  description = "Name of the CI account pipeline execution role"
  value       = local.create_ci_roles ? aws_iam_role.pipeline_execution[0].name : null
}

# Regional Account Role Outputs
output "regional_access_role_arn" {
  description = "ARN of the regional account access role"
  value       = local.create_regional_role ? aws_iam_role.regional_access[0].arn : null
}

output "regional_access_role_name" {
  description = "Name of the regional account access role"
  value       = local.create_regional_role ? aws_iam_role.regional_access[0].name : null
}

# Management Account Role Outputs
output "management_access_role_arn" {
  description = "ARN of the management account access role"
  value       = local.create_management_role ? aws_iam_role.management_access[0].arn : null
}

output "management_access_role_name" {
  description = "Name of the management account access role"
  value       = local.create_management_role ? aws_iam_role.management_access[0].name : null
}

# Cross-Account Role ARNs (for pipeline configuration)
output "regional_role_arn" {
  description = "Complete ARN for regional account access (for pipeline configuration)"
  value       = "arn:aws:iam::${var.regional_account_id}:role/${var.role_name_prefix}-regional-access"
}

output "management_role_arn" {
  description = "Complete ARN for management account access (for pipeline configuration)"
  value       = "arn:aws:iam::${var.management_account_id}:role/${var.role_name_prefix}-management-access"
}

# Account Configuration
output "account_configuration" {
  description = "Account configuration for reference"
  value = {
    ci_account_id         = var.ci_account_id
    regional_account_id   = var.regional_account_id
    management_account_id = var.management_account_id
    environment          = var.environment
  }
}