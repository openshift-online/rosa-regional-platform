# Outputs for Pipeline Configuration

# Pipeline Information
output "pipeline_name" {
  description = "Name of the deployed CodePipeline"
  value       = module.codepipeline.pipeline_name
}

output "pipeline_arn" {
  description = "ARN of the deployed CodePipeline"
  value       = module.codepipeline.pipeline_arn
}

output "pipeline_url" {
  description = "AWS Console URL to view the CodePipeline"
  value       = module.codepipeline.pipeline_url
}

output "pipeline_role_arn" {
  description = "ARN of the CodePipeline service role"
  value       = module.codepipeline.pipeline_role_arn
}

# Cross-Account Role ARNs (auto-constructed)
output "cross_account_roles" {
  description = "ARNs of cross-account roles (must be deployed manually in each account)"
  value = {
    regional_role_arn   = local.regional_role_arn
    management_role_arn = local.management_role_arn
  }
}

# CodeBuild Projects
output "codebuild_projects" {
  description = "Map of CodeBuild project names and ARNs"
  value       = module.codepipeline.codebuild_projects
}

# Artifact Storage
output "artifacts_bucket_name" {
  description = "Name of the S3 bucket storing pipeline artifacts"
  value       = module.codepipeline.artifacts_bucket_name
}

output "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket storing pipeline artifacts"
  value       = module.codepipeline.artifacts_bucket_arn
}

output "artifacts_kms_key_arn" {
  description = "ARN of the KMS key encrypting pipeline artifacts"
  value       = module.codepipeline.artifacts_kms_key_arn
}


# Account Configuration
output "account_configuration" {
  description = "Summary of account configuration"
  value = {
    ci_account_id         = data.aws_caller_identity.current.account_id
    regional_account_id   = var.regional_account_id
    management_account_id = var.management_account_id
    aws_region           = var.aws_region
    environment          = var.environment
  }
}

# Pipeline Configuration Summary
output "pipeline_configuration" {
  description = "Summary of pipeline configuration"
  value = {
    name                    = module.codepipeline.pipeline_name
    environment            = var.environment
    region                 = var.aws_region
    source_type            = "manual-trigger"
    artifacts_bucket       = module.codepipeline.artifacts_bucket_name
    kms_key_alias         = var.kms_key_alias
    codebuild_compute_type = var.codebuild_compute_type
    codebuild_image       = var.codebuild_image
  }
  sensitive = false
}

# Pipeline Management Commands
output "pipeline_management" {
  description = "AWS CLI commands to manage the pipeline"
  value = {
    start_execution = "aws codepipeline start-pipeline-execution --name ${module.codepipeline.pipeline_name} --region ${var.aws_region}"
    get_state      = "aws codepipeline get-pipeline-state --name ${module.codepipeline.pipeline_name} --region ${var.aws_region}"
    list_executions = "aws codepipeline list-pipeline-executions --pipeline-name ${module.codepipeline.pipeline_name} --region ${var.aws_region}"
    view_logs = {
      regional_cluster     = "aws logs tail /aws/codebuild/${module.codepipeline.regional_cluster_project_name} --region ${var.aws_region}"
      management_cluster   = "aws logs tail /aws/codebuild/${module.codepipeline.management_cluster_project_name} --region ${var.aws_region}"
    }
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Instructions for deploying cross-account roles"
  value = {
    description = "Deploy the following modules in each account to complete the setup"
    regional_account = {
      description = "Deploy this module in the regional account (${var.regional_account_id})"
      command = "terraform apply -var=\"deployment_target=regional\" -var=\"ci_account_id=${data.aws_caller_identity.current.account_id}\" -var=\"regional_account_id=${var.regional_account_id}\" -var=\"management_account_id=${var.management_account_id}\""
    }
    management_account = {
      description = "Deploy this module in the management account (${var.management_account_id})"
      command = "terraform apply -var=\"deployment_target=management\" -var=\"ci_account_id=${data.aws_caller_identity.current.account_id}\" -var=\"regional_account_id=${var.regional_account_id}\" -var=\"management_account_id=${var.management_account_id}\""
    }
  }
}

