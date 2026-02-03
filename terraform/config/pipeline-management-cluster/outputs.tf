output "github_connection_arn" {
  description = "ARN of the GitHub CodeStar connection"
  value       = aws_codestarconnections_connection.github.arn
}

output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.regional_pipeline.name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline"
  value       = aws_codepipeline.regional_pipeline.arn
}

output "codebuild_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.regional_builder.name
}

output "artifact_bucket" {
  description = "S3 bucket used for pipeline artifacts"
  value       = aws_s3_bucket.pipeline_artifact.id
}

output "management_state_bucket" {
  description = "S3 bucket for management cluster Terraform state"
  value       = aws_s3_bucket.management_state.id
}

output "management_lock_table" {
  description = "DynamoDB table for management cluster state locks"
  value       = aws_dynamodb_table.management_locks.name
}
