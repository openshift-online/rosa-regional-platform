# IAM Roles and Policies for CodePipeline Module
#
# Creates service roles for CodePipeline and CodeBuild projects with
# appropriate permissions for cross-account operations.

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Reference the pipeline execution role created by iam-cross-account module
data "aws_iam_role" "pipeline_execution" {
  name = "rosa-pipeline-execution"
}

# CodePipeline service role
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.pipeline_name_prefix}-pipeline-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# CodePipeline service policy
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "CodePipelineServicePolicy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = [
          aws_codebuild_project.regional_cluster.arn,
          aws_codebuild_project.regional_argocd_bootstrap.arn,
          aws_codebuild_project.management_cluster.arn,
          aws_codebuild_project.management_argocd_bootstrap.arn,
          aws_codebuild_project.regional_iot.arn,
          aws_codebuild_project.management_iot.arn,
          aws_codebuild_project.consumer_registration.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetBucketAcl"
        ]
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetObjectTagging"
        ]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:ReEncrypt*",
          "kms:CreateGrant"
        ]
        Resource = aws_kms_key.artifacts.arn
      },
      # CodeStar connections permissions
      {
        Effect = "Allow"
        Action = "codestar-connections:UseConnection"
        Resource = var.codestar_connection_arn != null ? var.codestar_connection_arn : aws_codestarconnections_connection.github[0].arn
      }
    ]
  })
}

# Individual CodeBuild roles removed - all projects now use data.aws_iam_role.pipeline_execution

# VPC policies removed for simplicity - CodeBuild runs in AWS-managed infrastructure

# IAM policy for the user running Terraform to execute the pipeline
resource "aws_iam_policy" "terraform_user_pipeline_access" {
  name        = "${var.pipeline_name_prefix}-terraform-user-pipeline-access-${var.environment}"
  description = "Allows the user running Terraform to trigger and monitor pipeline executions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codepipeline:StartPipelineExecution",
          "codepipeline:GetPipelineState",
          "codepipeline:GetPipelineExecution",
          "codepipeline:ListPipelineExecutions",
          "codepipeline:StopPipelineExecution",
          "codepipeline:GetPipeline"
        ]
        Resource = aws_codepipeline.rosa_provisioning.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Conditionally attach policy to user (only if caller is a user, not a role)
resource "aws_iam_user_policy_attachment" "terraform_user_pipeline_access" {
  count      = can(regex("^arn:aws:iam::[0-9]+:user/", data.aws_caller_identity.current.arn)) ? 1 : 0
  user       = split("/", data.aws_caller_identity.current.arn)[1]
  policy_arn = aws_iam_policy.terraform_user_pipeline_access.arn
}