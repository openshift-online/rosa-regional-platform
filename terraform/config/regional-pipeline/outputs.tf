output "pipeline_url" {
  description = "AWS Console URL for the Regional Pipeline"
  value       = "https://${var.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.pipeline.name}/view?region=${var.region}"
}

output "management_state_bucket" {
  description = "S3 bucket for storing Management Cluster Terraform state"
  value       = aws_s3_bucket.management_state.bucket
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar connection to GitHub"
  value       = aws_codestarconnections_connection.github.arn
}

output "codestar_connection_status" {
  description = "Status of the CodeStar connection (needs manual activation)"
  value       = aws_codestarconnections_connection.github.connection_status
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild role (for Management accounts to trust)"
  value       = aws_iam_role.codebuild.arn
}

output "management_deploy_role_name" {
  description = "Name of the role to create in Management accounts"
  value       = aws_iam_role.management_cluster_deploy_role.name
}
