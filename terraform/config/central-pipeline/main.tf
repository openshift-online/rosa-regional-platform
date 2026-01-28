provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

# =============================================================================
# CodeStar Connection to GitHub
# =============================================================================

resource "aws_codestarconnections_connection" "github" {
  name          = "github-connection"
  provider_type = "GitHub"
}

# =============================================================================
# S3 Buckets
# =============================================================================

# Central Pipeline State Bucket (for storing central-pipeline's own state)
resource "aws_s3_bucket" "central_pipeline_state" {
  bucket_prefix = "central-pipeline-state-"
}

resource "aws_s3_bucket_versioning" "central_pipeline_state" {
  bucket = aws_s3_bucket.central_pipeline_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "central_pipeline_state" {
  bucket = aws_s3_bucket.central_pipeline_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "central_pipeline_state" {
  bucket = aws_s3_bucket.central_pipeline_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Artifacts Bucket
resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "pipeline-artifacts-"
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Terraform State Bucket for Regional Clusters
resource "aws_s3_bucket" "tf_state" {
  bucket_prefix = "regional-cluster-tf-state-"
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow Organization Member Accounts to access the State Bucket
resource "aws_s3_bucket_policy" "tf_state_access" {
  bucket = aws_s3_bucket.tf_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowOrganizationAccess"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.tf_state.arn,
          "${aws_s3_bucket.tf_state.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
        }
      }
    ]
  })
}

# =============================================================================
# IAM Roles
# =============================================================================

# CodeBuild Role
resource "aws_iam_role" "codebuild" {
  name                 = "central-pipeline-codebuild-role"
  max_session_duration = 3600 # 1 hour
  description          = "Role for Central Pipeline CodeBuild to mint accounts and deploy Regional Clusters"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeBuildAssumeRole"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:project/regional-platform-deploy"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "central-pipeline-codebuild-role"
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "central-pipeline"
  }
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "central-pipeline-codebuild-policy"
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs (Scoped to pipeline logs)
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/regional-platform-deploy",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/regional-platform-deploy:*"
        ]
      },
      # S3 Access (Scoped to pipeline buckets)
      {
        Sid    = "AllowS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
          aws_s3_bucket.tf_state.arn,
          "${aws_s3_bucket.tf_state.arn}/*"
        ]
      },
      # Organizations Access (Account Minting - High Risk)
      {
        Sid    = "AllowOrganizationsAccountManagement"
        Effect = "Allow"
        Action = [
          "organizations:CreateAccount",
          "organizations:DescribeAccount",
          "organizations:ListAccounts",
          "organizations:ListTagsForResource",
          "organizations:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
        }
      },
      # Move Account (Separate permission with additional restrictions)
      {
        Sid    = "AllowMoveAccountToOU"
        Effect = "Allow"
        Action = [
          "organizations:MoveAccount"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
        }
      },
      # Service Linked Role Creation (Scoped)
      {
        Sid    = "AllowServiceLinkedRoleCreation"
        Effect = "Allow"
        Action = "iam:CreateServiceLinkedRole"
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
        ]
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = [
              "organizations.amazonaws.com",
              "account.amazonaws.com"
            ]
          }
        }
      },
      # Assume Role into Child Accounts (Regional Accounts Only)
      {
        Sid    = "AllowAssumeRoleIntoRegionalAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::*:role/OrganizationAccountAccessRole"
        ]
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
          }
          # Additional security: Require MFA for assume role (optional, can be enabled)
          # Bool = {
          #   "aws:MultiFactorAuthPresent" = "true"
          # }
        }
      },
      # Read-only access to describe organization
      {
        Sid    = "AllowDescribeOrganization"
        Effect = "Allow"
        Action = [
          "organizations:DescribeOrganization",
          "organizations:ListRoots",
          "organizations:ListOrganizationalUnitsForParent"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodePipeline Role
resource "aws_iam_role" "codepipeline" {
  name                 = "central-pipeline-role"
  max_session_duration = 3600 # 1 hour
  description          = "Role for Central Pipeline CodePipeline orchestration"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodePipelineAssumeRole"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:codepipeline:${var.region}:${data.aws_caller_identity.current.account_id}:regional-platform-pipeline"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "central-pipeline-role"
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "central-pipeline"
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "central-pipeline-policy"
  role = aws_iam_role.codepipeline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Access (Artifacts bucket only)
      {
        Sid    = "AllowS3ArtifactsAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetBucketVersioning",
          "s3:PutObjectAcl",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      # CodeBuild Access (Scoped to pipeline project)
      {
        Sid    = "AllowCodeBuildExecution"
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = [
          aws_codebuild_project.deploy.arn
        ]
      },
      # CodeStar Connections (Scoped to GitHub connection)
      {
        Sid      = "AllowCodeStarConnectionUse"
        Effect   = "Allow"
        Action   = "codestar-connections:UseConnection"
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}

# =============================================================================
# CodeBuild Project
# =============================================================================

resource "aws_codebuild_project" "deploy" {
  name          = "regional-platform-deploy"
  description   = "Orchestrates account minting and regional cluster deployment"
  build_timeout = 60 # minutes
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "TF_STATE_BUCKET"
      value = aws_s3_bucket.tf_state.bucket
    }

    environment_variable {
      name  = "TF_BACKEND_REGION"
      value = var.region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec.yml")
  }
}

# =============================================================================
# CodePipeline
# =============================================================================

resource "aws_codepipeline" "pipeline" {
  name     = "regional-platform-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = var.repository_id
        BranchName       = var.branch_name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "OrchestrateDeploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }
}
