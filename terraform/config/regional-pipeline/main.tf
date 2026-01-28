provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# CodeStar Connection to GitHub
# =============================================================================

resource "aws_codestarconnections_connection" "github" {
  name          = "regional-pipeline-github-connection"
  provider_type = "GitHub"
}

# =============================================================================
# S3 Buckets
# =============================================================================

# Artifacts Bucket for Regional Pipeline
resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "regional-pipeline-artifacts-"
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

# Terraform State Bucket for Management Clusters in this region
resource "aws_s3_bucket" "management_state" {
  bucket_prefix = "management-cluster-tf-state-"
}

resource "aws_s3_bucket_versioning" "management_state" {
  bucket = aws_s3_bucket.management_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "management_state" {
  bucket = aws_s3_bucket.management_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "management_state" {
  bucket = aws_s3_bucket.management_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow Management Accounts in same region to access state bucket
resource "aws_s3_bucket_policy" "management_state_access" {
  bucket = aws_s3_bucket.management_state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowManagementAccountAccess"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.management_state.arn,
          "${aws_s3_bucket.management_state.arn}/*"
        ]
        Condition = {
          StringEquals = {
            # Only allow access from this specific Regional Account
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# IAM Roles for Regional Pipeline
# =============================================================================

# CodeBuild Role for Management Cluster Deployment
resource "aws_iam_role" "codebuild" {
  name                 = "regional-pipeline-codebuild-role"
  max_session_duration = 3600 # 1 hour
  description          = "Role for Regional Pipeline CodeBuild to deploy Management Clusters"

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
            "aws:SourceArn" = "arn:aws:codebuild:${var.region}:${data.aws_caller_identity.current.account_id}:project/management-cluster-deploy"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "regional-pipeline-codebuild-role"
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "regional-pipeline"
    Region      = var.region
  }
}

# CodeBuild Policy - More restrictive than Central Pipeline
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "regional-pipeline-codebuild-policy"
  role = aws_iam_role.codebuild.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs (Scoped to regional pipeline logs)
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/management-cluster-deploy",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/management-cluster-deploy:*"
        ]
      },
      # S3 Access (Regional buckets only)
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
          aws_s3_bucket.management_state.arn,
          "${aws_s3_bucket.management_state.arn}/*"
        ]
      },
      # Access to Central State Bucket (Read management-deploy state)
      {
        Sid    = "AllowReadCentralStateBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.central_state_bucket}",
          "arn:aws:s3:::${var.central_state_bucket}/management-deploy/*"
        ]
      },
      # AssumeRole into Management Accounts (Region-scoped)
      {
        Sid    = "AllowAssumeRoleIntoManagementAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::*:role/OrganizationAccountAccessRole"
        ]
        Condition = {
          StringEquals = {
            # Only this Regional Account can assume
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
          StringLike = {
            # Only Management accounts (naming convention enforcement)
            "aws:RequestedRegion" = var.region
          }
        }
      },
      # EC2 Describe for Terraform (Read-only)
      {
        Sid    = "AllowEC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:Get*"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodePipeline Role
resource "aws_iam_role" "codepipeline" {
  name                 = "regional-pipeline-role"
  max_session_duration = 3600
  description          = "Role for Regional Pipeline CodePipeline orchestration"

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
            "aws:SourceArn" = "arn:aws:codepipeline:${var.region}:${data.aws_caller_identity.current.account_id}:management-cluster-pipeline"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "regional-pipeline-role"
    Environment = "production"
    ManagedBy   = "terraform"
    Purpose     = "regional-pipeline"
    Region      = var.region
  }
}

# CodePipeline Policy
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "regional-pipeline-policy"
  role = aws_iam_role.codepipeline.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 Access (Artifacts only)
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
      # CodeBuild Access (Scoped to Management cluster project)
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
      # CodeStar Connection
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
# IAM Role for Management Accounts to trust Regional Pipeline
# =============================================================================

# This role will be created in Management Accounts by the Regional Pipeline
# It has more restrictive permissions than OrganizationAccountAccessRole
resource "aws_iam_role" "management_cluster_deploy_role" {
  name                 = "ManagementClusterDeployRole"
  max_session_duration = 3600
  description          = "Role for Regional Pipeline to deploy Management Cluster infrastructure"

  # This role trusts the Regional Account's CodeBuild role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRegionalPipelineAssumeRole"
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.codebuild.arn
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "regional-pipeline-${var.region}"
          }
        }
      }
    ]
  })

  # This role will be created in Management accounts
  # For now, we define it here as a template
  # It will be deployed via Terraform when Management account is created

  tags = {
    Name        = "ManagementClusterDeployRole"
    Environment = "production"
    ManagedBy   = "regional-pipeline"
    Purpose     = "management-cluster-deployment"
  }
}

# Permissions for the Management Cluster Deploy Role
# This is more restrictive than full admin access
resource "aws_iam_role_policy" "management_cluster_deploy_policy" {
  name = "ManagementClusterDeployPolicy"
  role = aws_iam_role.management_cluster_deploy_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # EKS Full Access (needed for cluster creation)
      {
        Sid      = "AllowEKSFullAccess"
        Effect   = "Allow"
        Action   = "eks:*"
        Resource = "*"
      },
      # EC2 Access for VPC and networking
      {
        Sid    = "AllowEC2NetworkingAccess"
        Effect = "Allow"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      },
      # IAM Access (limited to service roles)
      {
        Sid    = "AllowIAMServiceRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:ListRoles",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:CreateServiceLinkedRole",
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/*"
        ]
      },
      # CloudWatch Logs
      {
        Sid      = "AllowCloudWatchLogs"
        Effect   = "Allow"
        Action   = "logs:*"
        Resource = "*"
      },
      # Auto Scaling
      {
        Sid      = "AllowAutoScaling"
        Effect   = "Allow"
        Action   = "autoscaling:*"
        Resource = "*"
      },
      # ECS (for bootstrap tasks)
      {
        Sid      = "AllowECSAccess"
        Effect   = "Allow"
        Action   = "ecs:*"
        Resource = "*"
      }
    ]
  })
}

# =============================================================================
# CodeBuild Project
# =============================================================================

resource "aws_codebuild_project" "deploy" {
  name          = "management-cluster-deploy"
  description   = "Deploys Management Clusters in ${var.region}"
  build_timeout = 60
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
      name  = "MANAGEMENT_STATE_BUCKET"
      value = aws_s3_bucket.management_state.bucket
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.region
    }

    environment_variable {
      name  = "CENTRAL_STATE_BUCKET"
      value = var.central_state_bucket
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspec.yml")
  }

  tags = {
    Name        = "management-cluster-deploy"
    Environment = "production"
    ManagedBy   = "terraform"
    Region      = var.region
  }
}

# =============================================================================
# CodePipeline
# =============================================================================

resource "aws_codepipeline" "pipeline" {
  name     = "management-cluster-pipeline"
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
      name            = "DeployManagementClusters"
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

  tags = {
    Name        = "management-cluster-pipeline"
    Environment = "production"
    ManagedBy   = "terraform"
    Region      = var.region
  }
}
