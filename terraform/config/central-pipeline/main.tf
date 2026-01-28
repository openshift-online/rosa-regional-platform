provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

# =============================================================================
# S3 Buckets
# =============================================================================

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

# Allow Organization Member Accounts to access the State Bucket
resource "aws_s3_bucket_policy" "tf_state_access" {
  bucket = aws_s3_bucket.tf_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowOrganizationAccess"
        Effect = "Allow"
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
  name = "central-pipeline-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      # S3 Access
      {
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
          "${aws_s3_bucket.artifacts.arn}/*",
          aws_s3_bucket.tf_state.arn,
          "${aws_s3_bucket.tf_state.arn}/*"
        ]
      },
      # Organizations Access (Minting Accounts)
      {
        Effect = "Allow"
        Action = [
          "organizations:CreateAccount",
          "organizations:DescribeAccount",
          "organizations:ListAccounts",
          "organizations:ListTagsForResource",
          "organizations:TagResource",
          "organizations:MoveAccount"
        ]
        Resource = "*"
      },
      # Service Linked Role creation (needed for Org account creation sometimes)
      {
        Effect = "Allow"
        Action = "iam:CreateServiceLinkedRole"
        Resource = "*"
      },
      # Assume Role into Child Accounts
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = "arn:aws:iam::*:role/OrganizationAccountAccessRole"
      }
    ]
  })
}

# CodePipeline Role
resource "aws_iam_role" "codepipeline" {
  name = "central-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  role = aws_iam_role.codepipeline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
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
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "codestar-connections:UseConnection"
        Resource = var.codestar_connection_arn
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
        ConnectionArn    = var.codestar_connection_arn
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
