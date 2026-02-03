# IAM Pipeline Roles for CI Account
#
# These roles are created in the CI account and used by CodePipeline and CodeBuild

# Policy allowing pipeline to assume cross-account roles
resource "aws_iam_role_policy" "pipeline_cross_account" {
  count = local.create_ci_roles ? 1 : 0
  name  = "CrossAccountAssumeRole"
  role  = aws_iam_role.pipeline_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${var.regional_account_id}:role/${var.role_name_prefix}-regional-access",
          "arn:aws:iam::${var.management_account_id}:role/${var.role_name_prefix}-management-access"
        ]
      }
    ]
  })
}

# Policy for CodePipeline service operations
resource "aws_iam_role_policy" "pipeline_service" {
  count = local.create_ci_roles ? 1 : 0
  name  = "CodePipelineService"
  role  = aws_iam_role.pipeline_execution[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:BatchGetProjects"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::rosa-pipeline-artifacts-*",
          "arn:aws:s3:::rosa-pipeline-artifacts-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [
          "arn:aws:kms:*:${var.ci_account_id}:key/*"
        ]
        Condition = {
          StringEquals = {
            "kms:via" = ["s3.*.amazonaws.com"]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:*:${var.ci_account_id}:log-group:/aws/codebuild/rosa-*",
          "arn:aws:logs:*:${var.ci_account_id}:log-group:/aws/codebuild/rosa-*:*"
        ]
      }
    ]
  })
}

# Create CodeBuild service roles for cross-account access
resource "aws_iam_role" "codebuild_regional" {
  count = local.create_ci_roles ? 1 : 0
  name  = "rosa-codebuild-regional-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "codebuild_management" {
  count = local.create_ci_roles ? 1 : 0
  name  = "rosa-codebuild-management-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Policy for CodeBuild to assume regional account role
resource "aws_iam_role_policy" "codebuild_regional_assume" {
  count = local.create_ci_roles ? 1 : 0
  name  = "AssumeRegionalRole"
  role  = aws_iam_role.codebuild_regional[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.regional_account_id}:role/${var.role_name_prefix}-regional-access"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${var.ci_account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::rosa-pipeline-artifacts-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          "arn:aws:kms:*:${var.ci_account_id}:key/*"
        ]
      }
    ]
  })
}

# Policy for CodeBuild to assume management account role
resource "aws_iam_role_policy" "codebuild_management_assume" {
  count = local.create_ci_roles ? 1 : 0
  name  = "AssumeManagementRole"
  role  = aws_iam_role.codebuild_management[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::${var.management_account_id}:role/${var.role_name_prefix}-management-access"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${var.ci_account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          "arn:aws:s3:::rosa-pipeline-artifacts-*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          "arn:aws:kms:*:${var.ci_account_id}:key/*"
        ]
      }
    ]
  })
}