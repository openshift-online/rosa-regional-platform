# IAM Cross-Account Module for ROSA Regional Platform CodePipeline
#
# This module creates the necessary IAM roles and policies for cross-account
# CodePipeline operations between CI, Regional, and Management accounts.
#
# Architecture:
# - CI Account: Contains CodePipeline and CodeBuild projects
# - Regional Account: Runs Regional Cluster infrastructure
# - Management Account: Runs Management Cluster infrastructure

locals {
  # Automatically set role creation flags based on deployment_target
  create_ci_roles        = var.create_ci_roles != null ? var.create_ci_roles : var.deployment_target == "ci"
  create_regional_role   = var.create_regional_role != null ? var.create_regional_role : var.deployment_target == "regional"
  create_management_role = var.create_management_role != null ? var.create_management_role : var.deployment_target == "management"

  common_tags = {
    Project     = "rosa-regional-platform"
    Component   = "ci-pipeline"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Create CI account pipeline execution role
resource "aws_iam_role" "pipeline_execution" {
  count = local.create_ci_roles ? 1 : 0
  name  = "rosa-pipeline-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "codepipeline.amazonaws.com",
            "codebuild.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Policy for pipeline execution role to handle CodeBuild operations
resource "aws_iam_role_policy" "pipeline_execution_policy" {
  count = local.create_ci_roles ? 1 : 0
  name  = "PipelineExecutionPolicy"
  role  = aws_iam_role.pipeline_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Cross-account role assumption
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${var.regional_account_id}:role/rosa-pipeline-regional-access",
          "arn:aws:iam::${var.management_account_id}:role/rosa-pipeline-management-access"
        ]
      },
      # CloudWatch Logs for CodeBuild
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:*:${var.ci_account_id}:log-group:/aws/codebuild/rosa-*",
          "arn:aws:logs:*:${var.ci_account_id}:log-group:/aws/codebuild/rosa-*:*"
        ]
      },
      # CodeBuild project management
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "arn:aws:codebuild:*:${var.ci_account_id}:project/rosa-*"
      },
      # CodePipeline operations
      {
        Effect = "Allow"
        Action = [
          "codepipeline:GetPipelineState",
          "codepipeline:GetPipelineExecution",
          "codepipeline:ListPipelineExecutions",
          "codepipeline:StartPipelineExecution",
          "codepipeline:StopPipelineExecution"
        ]
        Resource = "arn:aws:codepipeline:*:${var.ci_account_id}:pipeline/rosa-*"
      },
      # S3 artifact access
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetBucketAcl",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetObjectTagging"
        ]
        Resource = [
          "arn:aws:s3:::*rosa*",
          "arn:aws:s3:::*rosa*/*"
        ]
      },
      # KMS for artifact encryption/decryption
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
        Resource = "arn:aws:kms:*:${var.ci_account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.*.amazonaws.com"
          }
        }
      },
      # CodeStar connections for GitHub
      {
        Effect = "Allow"
        Action = "codestar-connections:UseConnection"
        Resource = "arn:aws:codestar-connections:*:${var.ci_account_id}:connection/*"
      }
    ]
  })
}

# Create regional account access role
resource "aws_iam_role" "regional_access" {
  count                = local.create_regional_role ? 1 : 0
  name                 = "rosa-pipeline-regional-access"
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.ci_account_id}:role/rosa-pipeline-execution"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_regions
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Create management account access role
resource "aws_iam_role" "management_access" {
  count                = local.create_management_role ? 1 : 0
  name                 = "rosa-pipeline-management-access"
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.ci_account_id}:role/rosa-pipeline-execution"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_regions
          }
        }
      }
    ]
  })

  tags = local.common_tags
}