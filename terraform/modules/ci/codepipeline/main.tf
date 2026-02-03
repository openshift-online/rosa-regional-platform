# AWS CodePipeline Module for ROSA Regional Platform
#
# Creates a 7-stage pipeline for cross-account ROSA cluster provisioning:
# 1. Source - GitHub source via CodeStar connection
# 2. RegionalInfrastructure - Provision regional cluster in regional account
# 3. RegionalArgoCD - Bootstrap ArgoCD on regional cluster
# 4. MaestroConnectivity - Setup IoT connectivity between accounts
# 5. ManagementInfrastructure - Provision management cluster in management account
# 6. ManagementArgoCD - Bootstrap ArgoCD on management cluster
# 7. ConsumerRegistration - Register management cluster as Maestro consumer
#
# Uses CodeStar connection for GitHub integration

locals {
  # Pipeline configuration
  pipeline_name = "${var.pipeline_name_prefix}-${var.environment}"

  # Extract GitHub repo information from URL
  github_url_parts = split("/", trimprefix(var.github_repo_url, "https://github.com/"))
  github_owner     = local.github_url_parts[0]
  github_repo      = local.github_url_parts[1]

  # Use provided connection or create new one
  codestar_connection_arn = var.codestar_connection_arn != null ? var.codestar_connection_arn : aws_codestarconnections_connection.github[0].arn

  # Common tags
  common_tags = {
    Project     = "rosa-regional-platform"
    Component   = "ci-pipeline"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# CodeStar connection for GitHub integration
resource "aws_codestarconnections_connection" "github" {
  count         = var.codestar_connection_arn == null ? 1 : 0
  name          = "rrp-${var.environment}-gh-conn"
  provider_type = "GitHub"

  tags = local.common_tags
}

# CodePipeline definition
resource "aws_codepipeline" "rosa_provisioning" {
  name     = local.pipeline_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"

    encryption_key {
      id   = aws_kms_key.artifacts.arn
      type = "KMS"
    }
  }

  # Stage 1: Source (GitHub via CodeStar)
  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn    = local.codestar_connection_arn
        FullRepositoryId = "${local.github_owner}/${local.github_repo}"
        BranchName       = var.github_branch
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  # Stage 2: Regional Infrastructure
  stage {
    name = "RegionalInfrastructure"

    action {
      name             = "ProvisionRegionalCluster"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["RegionalOutputs"]

      configuration = {
        ProjectName = aws_codebuild_project.regional_cluster.name
        EnvironmentVariables = jsonencode([
          {
            name  = "REGIONAL_ROLE_ARN"
            value = var.regional_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }
  }

  # Stage 3: Regional ArgoCD Bootstrap
  stage {
    name = "RegionalArgoCD"

    action {
      name             = "BootstrapRegionalArgoCD"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["RegionalArgoCDOutputs"]

      configuration = {
        ProjectName = aws_codebuild_project.regional_argocd_bootstrap.name
        EnvironmentVariables = jsonencode([
          {
            name  = "REGIONAL_ROLE_ARN"
            value = var.regional_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }
  }

  # Stage 4: Maestro Connectivity (sequential IoT setup)
  stage {
    name = "MaestroConnectivity"

    action {
      name             = "SetupRegionalIoT"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["IoTCertificates"]
      run_order        = 1

      configuration = {
        ProjectName = aws_codebuild_project.regional_iot.name
        EnvironmentVariables = jsonencode([
          {
            name  = "REGIONAL_ROLE_ARN"
            value = var.regional_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }

    action {
      name             = "SetupManagementIoT"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      run_order        = 2

      configuration = {
        ProjectName = aws_codebuild_project.management_iot.name
        EnvironmentVariables = jsonencode([
          {
            name  = "MANAGEMENT_ROLE_ARN"
            value = var.management_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }
  }

  # Stage 5: Management Infrastructure
  stage {
    name = "ManagementInfrastructure"

    action {
      name             = "ProvisionManagementCluster"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["ManagementOutputs"]

      configuration = {
        ProjectName = aws_codebuild_project.management_cluster.name
        EnvironmentVariables = jsonencode([
          {
            name  = "MANAGEMENT_ROLE_ARN"
            value = var.management_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }
  }

  # Stage 6: Management ArgoCD Bootstrap
  stage {
    name = "ManagementArgoCD"

    action {
      name             = "BootstrapManagementArgoCD"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["ManagementArgoCDOutputs"]

      configuration = {
        ProjectName = aws_codebuild_project.management_argocd_bootstrap.name
        EnvironmentVariables = jsonencode([
          {
            name  = "MANAGEMENT_ROLE_ARN"
            value = var.management_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }
  }

  # Stage 7: Consumer Registration
  stage {
    name = "ConsumerRegistration"

    action {
      name            = "RegisterMaestroConsumer"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.consumer_registration.name
        EnvironmentVariables = jsonencode([
          {
            name  = "REGIONAL_ROLE_ARN"
            value = var.regional_role_arn
          },
          {
            name  = "TARGET_REGION"
            value = var.aws_region
          },
          {
            name  = "ENVIRONMENT"
            value = var.environment
          }
        ])
      }
    }
  }

}