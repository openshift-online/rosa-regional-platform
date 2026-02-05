# CodeBuild Projects for ROSA Regional Platform Pipeline
#
# Creates CodeBuild projects for each pipeline stage with appropriate
# cross-account role configurations and build specifications.

# Common CodeBuild environment configuration
locals {
  common_environment = {
    compute_type = var.codebuild_compute_type
    image        = var.codebuild_image
    type         = "LINUX_CONTAINER"
  }
}

# Regional Cluster Provisioning Project
resource "aws_codebuild_project" "regional_cluster" {
  name         = "rosa-provision-regional-cluster-${var.environment}"
  description  = "Provision ROSA regional cluster infrastructure in regional account"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "regional-cluster"
    }

    environment_variable {
      name  = "REGIONAL_ROLE_ARN"
      value = var.regional_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.regional_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/provision-regional-cluster.yml"
  }

}

# Regional ArgoCD Bootstrap Project
resource "aws_codebuild_project" "regional_argocd_bootstrap" {
  name         = "rosa-bootstrap-regional-argocd-${var.environment}"
  description  = "Bootstrap ArgoCD on ROSA regional cluster"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "regional-argocd-bootstrap"
    }

    environment_variable {
      name  = "REGIONAL_ROLE_ARN"
      value = var.regional_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.regional_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/bootstrap-regional-argocd.yml"
  }

}

# Management Cluster Provisioning Project
resource "aws_codebuild_project" "management_cluster" {
  name         = "rosa-provision-management-cluster-${var.environment}"
  description  = "Provision ROSA management cluster infrastructure in management account"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "management-cluster"
    }

    environment_variable {
      name  = "MANAGEMENT_ROLE_ARN"
      value = var.management_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.management_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/provision-management-cluster.yml"
  }

}

# Management ArgoCD Bootstrap Project
resource "aws_codebuild_project" "management_argocd_bootstrap" {
  name         = "rosa-bootstrap-management-argocd-${var.environment}"
  description  = "Bootstrap ArgoCD on ROSA management cluster"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "management-argocd-bootstrap"
    }

    environment_variable {
      name  = "MANAGEMENT_ROLE_ARN"
      value = var.management_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.management_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/bootstrap-management-argocd.yml"
  }

}

# Regional IoT Setup Project
resource "aws_codebuild_project" "regional_iot" {
  name         = "rosa-setup-regional-iot-${var.environment}"
  description  = "Setup IoT Core infrastructure and certificates in regional account"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "regional-iot"
    }

    environment_variable {
      name  = "REGIONAL_ROLE_ARN"
      value = var.regional_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.regional_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/setup-regional-iot.yml"
  }

}

# Management IoT Setup Project
resource "aws_codebuild_project" "management_iot" {
  name         = "rosa-setup-management-iot-${var.environment}"
  description  = "Setup IoT certificates and secrets in management account"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "management-iot"
    }

    environment_variable {
      name  = "MANAGEMENT_ROLE_ARN"
      value = var.management_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.management_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/setup-management-iot.yml"
  }

}

# Maestro Consumer Registration Project
resource "aws_codebuild_project" "consumer_registration" {
  name         = "rosa-register-maestro-consumer-${var.environment}"
  description  = "Register management cluster as Maestro consumer via HTTP API"
  service_role = data.aws_iam_role.pipeline_execution.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = local.common_environment.compute_type
    image        = local.common_environment.image
    type         = local.common_environment.type

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PIPELINE_STAGE"
      value = "consumer-registration"
    }

    environment_variable {
      name  = "REGIONAL_ROLE_ARN"
      value = var.regional_role_arn
    }

    environment_variable {
      name  = "MANAGEMENT_ROLE_ARN"
      value = var.management_role_arn
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = var.regional_account_id
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "terraform/modules/ci/codepipeline/buildspecs/register-maestro-consumer.yml"
  }

}

