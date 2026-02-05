# Outputs for CodePipeline Module

# Pipeline Outputs
output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.rosa_provisioning.name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.rosa_provisioning.arn
}

output "pipeline_url" {
  description = "AWS Console URL for the CodePipeline"
  value       = "https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.rosa_provisioning.name}/view?region=${var.aws_region}"
}

output "pipeline_role_arn" {
  description = "ARN of the CodePipeline service role"
  value       = aws_iam_role.codepipeline_role.arn
}

# CodeBuild Project Outputs
output "codebuild_projects" {
  description = "Map of CodeBuild project names and ARNs"
  value = {
    regional_cluster          = aws_codebuild_project.regional_cluster.arn
    regional_argocd_bootstrap = aws_codebuild_project.regional_argocd_bootstrap.arn
    management_cluster        = aws_codebuild_project.management_cluster.arn
    management_argocd_bootstrap = aws_codebuild_project.management_argocd_bootstrap.arn
    regional_iot             = aws_codebuild_project.regional_iot.arn
    management_iot           = aws_codebuild_project.management_iot.arn
    consumer_registration    = aws_codebuild_project.consumer_registration.arn
  }
}

output "regional_cluster_project_name" {
  description = "Name of the regional cluster CodeBuild project"
  value       = aws_codebuild_project.regional_cluster.name
}

output "management_cluster_project_name" {
  description = "Name of the management cluster CodeBuild project"
  value       = aws_codebuild_project.management_cluster.name
}

# S3 Artifact Storage Outputs
output "artifacts_bucket_name" {
  description = "Name of the S3 bucket storing pipeline artifacts"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket storing pipeline artifacts"
  value       = aws_s3_bucket.artifacts.arn
}

output "artifacts_kms_key_arn" {
  description = "ARN of the KMS key encrypting pipeline artifacts"
  value       = aws_kms_key.artifacts.arn
}

output "artifacts_kms_key_id" {
  description = "ID of the KMS key encrypting pipeline artifacts"
  value       = aws_kms_key.artifacts.key_id
}

# Source configuration (GitHub via CodeStar)
output "github_repository" {
  description = "GitHub repository being monitored"
  value       = "${local.github_owner}/${local.github_repo}"
}

output "github_branch" {
  description = "GitHub branch being monitored"
  value       = var.github_branch
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar connection used for GitHub integration"
  value       = local.codestar_connection_arn
}

output "codestar_connection_status" {
  description = "Status of the CodeStar connection (if created by this module)"
  value       = var.codestar_connection_arn == null ? "PENDING - Activate in AWS Console before first pipeline run" : "EXTERNAL - Using provided connection"
}

# CloudWatch Log Groups removed for simplicity

# Configuration Summary
output "pipeline_configuration" {
  description = "Summary of pipeline configuration"
  value = {
    name                    = aws_codepipeline.rosa_provisioning.name
    environment            = var.environment
    region                 = var.aws_region
    source_type            = "github"
    github_repository      = "${local.github_owner}/${local.github_repo}"
    github_branch          = var.github_branch
    regional_role_arn      = var.regional_role_arn
    management_role_arn    = var.management_role_arn
    artifacts_bucket       = aws_s3_bucket.artifacts.bucket
    kms_key_alias         = var.kms_key_alias
    codebuild_compute_type = var.codebuild_compute_type
    codebuild_image       = var.codebuild_image
  }
  sensitive = false
}

# Monitoring outputs removed for simplicity

# Pipeline Execution Guidance
output "pipeline_execution_commands" {
  description = "AWS CLI commands to manage the pipeline"
  value = {
    start_execution = "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.rosa_provisioning.name} --region ${var.aws_region}"
    get_execution   = "aws codepipeline list-pipeline-executions --pipeline-name ${aws_codepipeline.rosa_provisioning.name} --region ${var.aws_region}"
    get_state      = "aws codepipeline get-pipeline-state --name ${aws_codepipeline.rosa_provisioning.name} --region ${var.aws_region}"
  }
}

# Setup Instructions
output "setup_instructions" {
  description = "Instructions to run the pipeline"
  value = {
    step_1 = "Pipeline monitors GitHub repository: ${local.github_owner}/${local.github_repo} (${var.github_branch} branch)"
    step_2 = "CodeStar connection ARN: ${local.codestar_connection_arn}"
    step_3 = "Activate the CodeStar connection in AWS Console if newly created"
    step_4 = "Pipeline will trigger automatically on Git pushes, or run manually: aws codepipeline start-pipeline-execution --name ${aws_codepipeline.rosa_provisioning.name} --region ${var.aws_region}"
  }
}

# Terraform User Access Information
output "terraform_user_access" {
  description = "Access information for the user running Terraform"
  value = {
    caller_identity = data.aws_caller_identity.current.arn
    pipeline_policy = can(regex("^arn:aws:iam::[0-9]+:user/", data.aws_caller_identity.current.arn)) ? aws_iam_policy.terraform_user_pipeline_access.arn : "N/A (caller is not an IAM user)"
    note = "If caller is an IAM user, pipeline execution permissions have been automatically attached. No S3/KMS access needed for GitHub source."
  }
}