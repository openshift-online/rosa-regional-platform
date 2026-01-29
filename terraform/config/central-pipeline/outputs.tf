output "codebuild_project_name" {
  description = "The name of the CodeBuild project"
  value       = aws_codebuild_project.cross_account_test.name
}

output "codebuild_project_arn" {
  description = "The ARN of the CodeBuild project"
  value       = aws_codebuild_project.cross_account_test.arn
}

output "codebuild_service_role_arn" {
  description = "The ARN of the IAM role used by CodeBuild"
  value       = aws_iam_role.codebuild_role.arn
}
