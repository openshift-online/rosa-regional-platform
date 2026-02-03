# Variables for CodePipeline Module

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

# Cross-Account Configuration
variable "regional_account_id" {
  description = "AWS account ID for the regional account"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.regional_account_id))
    error_message = "Regional account ID must be a 12-digit AWS account ID."
  }
}

variable "management_account_id" {
  description = "AWS account ID for the management account"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.management_account_id))
    error_message = "Management account ID must be a 12-digit AWS account ID."
  }
}

variable "regional_role_arn" {
  description = "ARN of the role to assume in the regional account"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.regional_role_arn))
    error_message = "Regional role ARN must be a valid IAM role ARN."
  }
}

variable "management_role_arn" {
  description = "ARN of the role to assume in the management account"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.management_role_arn))
    error_message = "Management role ARN must be a valid IAM role ARN."
  }
}

# GitHub configuration
variable "github_repo_url" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/typeid/rosa-regional-platform"
}

variable "github_branch" {
  description = "GitHub branch to monitor"
  type        = string
  default     = "stub_pipeline"
}

variable "codestar_connection_arn" {
  description = "ARN of the CodeStar connection to GitHub (optional - will create one if not provided)"
  type        = string
  default     = null
}

# Artifact Storage Configuration
variable "artifacts_bucket_name" {
  description = "Name for the S3 bucket to store pipeline artifacts"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.artifacts_bucket_name))
    error_message = "Bucket name must be between 3 and 63 characters, start and end with lowercase letter or number, and contain only lowercase letters, numbers, and hyphens."
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

# Monitoring Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alarms for the pipeline"
  type        = bool
  default     = false
}

variable "sns_notification_topic_arn" {
  description = "SNS topic ARN for pipeline notifications (optional)"
  type        = string
  default     = null
}

# Configuration Complete - VPC and additional tags removed for simplicity