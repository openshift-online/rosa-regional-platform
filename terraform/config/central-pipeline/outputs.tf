output "pipeline_url" {
  value = "https://${var.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.pipeline.name}/view?region=${var.region}"
}

output "tf_state_bucket" {
  value = aws_s3_bucket.tf_state.bucket
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar connection to GitHub"
  value       = aws_codestarconnections_connection.github.arn
}

output "codestar_connection_status" {
  description = "Status of the CodeStar connection (needs manual activation in AWS Console)"
  value       = aws_codestarconnections_connection.github.connection_status
}
