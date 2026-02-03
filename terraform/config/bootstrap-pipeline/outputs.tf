# =============================================================================
# Regional Cluster Pipeline Outputs
# =============================================================================

output "regional_pipeline_name" {
  description = "Name of the Regional Cluster CodePipeline"
  value       = module.pipeline_regional_cluster.pipeline_name
}

output "regional_pipeline_arn" {
  description = "ARN of the Regional Cluster CodePipeline"
  value       = module.pipeline_regional_cluster.pipeline_arn
}

output "regional_github_connection_arn" {
  description = "ARN of the GitHub connection for Regional Cluster pipeline"
  value       = module.pipeline_regional_cluster.github_connection_arn
}

output "regional_github_connection_status" {
  description = "Status of the GitHub connection for Regional Cluster pipeline (requires manual authorization)"
  value       = "PENDING - Navigate to AWS Console > Developer Tools > Connections to authorize"
}

# =============================================================================
# Management Cluster Pipeline Outputs
# =============================================================================

output "management_pipeline_name" {
  description = "Name of the Management Cluster CodePipeline"
  value       = module.pipeline_management_cluster.pipeline_name
}

output "management_pipeline_arn" {
  description = "ARN of the Management Cluster CodePipeline"
  value       = module.pipeline_management_cluster.pipeline_arn
}

output "management_github_connection_arn" {
  description = "ARN of the GitHub connection for Management Cluster pipeline"
  value       = module.pipeline_management_cluster.github_connection_arn
}

output "management_github_connection_status" {
  description = "Status of the GitHub connection for Management Cluster pipeline (requires manual authorization)"
  value       = "PENDING - Navigate to AWS Console > Developer Tools > Connections to authorize"
}

# =============================================================================
# General Information
# =============================================================================

output "central_account_id" {
  description = "AWS Account ID where pipelines are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_region" {
  description = "AWS Region where pipelines are deployed"
  value       = data.aws_region.current.name
}

output "next_steps" {
  description = "Next steps after bootstrap"
  value       = <<-EOT
    ✅ Bootstrap Complete!

    Next Steps:
    1. Authorize GitHub Connections in AWS Console:
       - Regional Pipeline: ${module.pipeline_regional_cluster.github_connection_arn}
       - Management Pipeline: ${module.pipeline_management_cluster.github_connection_arn}

    2. The following pipelines are now active:
       - Regional Cluster Pipeline: ${module.pipeline_regional_cluster.pipeline_name}
       - Management Cluster Pipeline: ${module.pipeline_management_cluster.pipeline_name}

    3. To deploy clusters, commit YAML files to your repository:
       - Regional clusters: deploy/<name>/regional.yaml
       - Management clusters: deploy/<name>/management/*.yaml
  EOT
}
