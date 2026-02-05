# Variables for CodePipeline Module

# Account Configuration
variable "regional_account_id" {
  description = "AWS account ID for regional cluster infrastructure"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.regional_account_id))
    error_message = "Regional account ID must be a 12-digit AWS account ID."
  }
}

variable "management_account_id" {
  description = "AWS account ID for management cluster infrastructure"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "Management account ID must be a 12-digit AWS account ID."
  }
}

# Pipeline Configuration
variable "pipeline_name_prefix" {
  description = "Prefix for the CodePipeline name"
  type        = string
  default     = "rosa-regional-platform-provisioning"
}

variable "environment" {
  description = "Environment name (e.g., integration, staging, production)"
  type        = string
  default     = "integration"
}

variable "aws_region" {
  description = "AWS region where the pipeline will run"
  type        = string
}



# GitHub configuration removed - pipeline runs without source for simplicity

# Artifact Storage Configuration
variable "artifacts_bucket_prefix" {
  description = "Prefix for the S3 bucket name storing pipeline artifacts (will be made unique with account ID hash)"
  type        = string
  default     = "rosa-pipeline-artifacts"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.artifacts_bucket_prefix))
    error_message = "Bucket prefix must start and end with lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "kms_key_alias" {
  description = "Alias for the KMS key used to encrypt pipeline artifacts"
  type        = string
  default     = "alias/rosa-pipeline-artifacts"
}

variable "artifacts_retention_days" {
  description = "Number of days to retain pipeline artifacts in S3"
  type        = number
  default     = 30

  validation {
    condition     = var.artifacts_retention_days >= 1 && var.artifacts_retention_days <= 365
    error_message = "Artifacts retention days must be between 1 and 365."
  }
}

# CodeBuild Configuration
variable "codebuild_compute_type" {
  description = "Compute type for CodeBuild projects"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"

  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM",
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.codebuild_compute_type)
    error_message = "Invalid CodeBuild compute type."
  }
}

variable "codebuild_image" {
  description = "Docker image for CodeBuild projects"
  type        = string
  default     = "aws/codebuild/standard:7.0"
}

variable "codebuild_timeout_minutes" {
  description = "Timeout in minutes for CodeBuild projects"
  type        = number
  default     = 60

  validation {
    condition     = var.codebuild_timeout_minutes >= 5 && var.codebuild_timeout_minutes <= 480
    error_message = "CodeBuild timeout must be between 5 and 480 minutes."
  }
}

