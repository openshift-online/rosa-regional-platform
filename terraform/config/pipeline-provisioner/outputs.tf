# =============================================================================
# Pipeline Provisioner Outputs
# =============================================================================

output "provisioner_pipeline_name" {
  description = "Name of the Pipeline Provisioner CodePipeline"
  value       = aws_codepipeline.provisioner.name
}

output "provisioner_pipeline_arn" {
  description = "ARN of the Pipeline Provisioner CodePipeline"
  value       = aws_codepipeline.provisioner.arn
}

output "github_connection_arn" {
  description = "ARN of the GitHub connection for Pipeline Provisioner"
  value       = aws_codestarconnections_connection.github.arn
}

output "github_connection_status" {
  description = "Status of the GitHub connection (requires manual authorization)"
  value       = "PENDING - Navigate to AWS Console > Developer Tools > Connections to authorize"
}

output "provisioner_role_arn" {
  description = "ARN of the IAM role used by the provisioner CodeBuild project"
  value       = aws_iam_role.codebuild_role.arn
}

# =============================================================================
# General Information
# =============================================================================

output "central_account_id" {
  description = "AWS Account ID where pipeline provisioner is deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "deployment_region" {
  description = "AWS Region where pipeline provisioner is deployed"
  value       = data.aws_region.current.id
}

output "next_steps" {
  description = "Next steps after pipeline provisioner deployment"
  value       = <<-EOT
    ✅ Pipeline Provisioner Deployed!

    Next Steps:
    1. Authorize GitHub Connection in AWS Console:
       - Connection ARN: ${aws_codestarconnections_connection.github.arn}
       - Navigate to: AWS Console > Developer Tools > Connections
       - Click "Update pending connection" and authorize with GitHub

    2. The Pipeline Provisioner is now active:
       - Pipeline: ${aws_codepipeline.provisioner.name}
       - Watches: deploy/**

    3. To create new pipelines, commit YAML files to your repository:
       - Regional clusters: deploy/<region-name>/regional.yaml
       - Management clusters: deploy/<region-name>/management/<cluster-name>.yaml

    4. See deploy/README.md for detailed configuration instructions

    5. Example configuration files are available in:
       - deploy/us-east-1/
  EOT
}
