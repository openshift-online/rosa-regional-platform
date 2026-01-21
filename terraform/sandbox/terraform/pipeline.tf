resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = "${var.artifacts_bucket_name}-${random_id.bucket_suffix.hex}"
}

# --- CodeStar Connection ---
resource "aws_codestarconnections_connection" "github" {
  name          = var.codestar_connection_name
  provider_type = "GitHub"
}

# --- CodeBuild Role ---
resource "aws_iam_role" "codebuild_role" {
  name = "SandboxCodeBuildRole"

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
  name = "SandboxCodeBuildPolicy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.account_pool.arn
      },
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [for id in var.account_ids : "arn:aws:iam::${id}:role/OrganizationAccountAccessRole"]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:RetryBuild"
        ]
        Resource = aws_codebuild_project.sandbox_project.arn
      }
    ]
  })
}

# --- CodePipeline Role ---
resource "aws_iam_role" "codepipeline_role" {
  name = "SandboxCodePipelineRole"

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
  name = "SandboxCodePipelinePolicy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codebuild:StartBuildBatch",
          "codebuild:StopBuildBatch",
          "codebuild:RetryBuildBatch",
          "codebuild:BatchGetBuildBatches"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "codestar-connections:UseConnection"
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}

# --- CodeBuild Project ---
resource "aws_codebuild_project" "sandbox_project" {
  name          = "Sandbox-EKS-Test"
  description   = "EKS Testing Sandbox Project"
  build_timeout = 300 # minutes
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    # Environment variables are defined in buildspec, but we can override or add here if needed.
    # DYNAMODB_TABLE_NAME is in buildspec env block.
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/sandbox/pipeline/buildspec-batch.yml"
  }

  build_batch_config {
    service_role    = aws_iam_role.codebuild_role.arn
    timeout_in_mins = 300
  }
}

resource "aws_codebuild_project" "janitor_project" {
  name          = "Sandbox-Janitor"
  description   = "Cleanup failed sandbox accounts"
  build_timeout = 20 # minutes
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "DYNAMODB_TABLE_NAME"
      value = aws_dynamodb_table.account_pool.name
    }
    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_owner}/${var.github_repo}.git"
    git_clone_depth = 1
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        install = {
          commands = [
            "pip install -r terraform/sandbox/scripts/requirements.txt",
            # Ensure setup_env.sh logic for tools if needed, or just install cloud-nuke here directly
            "curl -L https://github.com/gruntwork-io/cloud-nuke/releases/download/v0.37.1/cloud-nuke_linux_amd64 -o cloud-nuke",
            "chmod +x cloud-nuke",
            "mv cloud-nuke /usr/local/bin/"
          ]
        }
        build = {
          commands = [
            "python3 terraform/sandbox/scripts/janitor.py"
          ]
        }
      }
    })
  }
}

# --- CodePipeline ---
resource "aws_codepipeline" "sandbox_pipeline" {
  name     = "Sandbox-EKS-Pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
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
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.sandbox_project.name
        BatchEnabled = "true"
      }
    }
  }
}

# --- Schedule ---
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "Sandbox-EKS-Schedule"
  description         = "Schedule for running EKS Sandbox tests"
  schedule_expression = var.schedule_expression
}

resource "aws_iam_role" "event_role" {
  name = "SandboxEventBridgeRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "event_policy" {
  name = "SandboxEventBridgePolicy"
  role = aws_iam_role.event_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "codepipeline:StartPipelineExecution"
        Resource = aws_codepipeline.sandbox_pipeline.arn
      },
      {
        Effect = "Allow"
        Action = "codebuild:StartBuild"
        Resource = aws_codebuild_project.janitor_project.arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_target" "pipeline" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "CodePipeline"
  arn       = aws_codepipeline.sandbox_pipeline.arn
  role_arn  = aws_iam_role.event_role.arn
}

resource "aws_cloudwatch_event_rule" "janitor_schedule" {
  name                = "Sandbox-Janitor-Schedule"
  description         = "Schedule for cleaning up failed sandbox accounts"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "janitor" {
  rule      = aws_cloudwatch_event_rule.janitor_schedule.name
  target_id = "JanitorBuild"
  arn       = aws_codebuild_project.janitor_project.arn
  role_arn  = aws_iam_role.event_role.arn
}

# --- Outputs ---
output "codestar_connection_arn" {
  value = aws_codestarconnections_connection.github.arn
  description = "The ARN of the CodeStar connection. You must complete the handshake in the AWS Console."
}
