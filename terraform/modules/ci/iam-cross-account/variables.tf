# Variables for IAM Cross-Account Module

variable "ci_account_id" {
  description = "AWS account ID where CodePipeline runs"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.ci_account_id))
    error_message = "CI account ID must be a 12-digit AWS account ID."
  }
}

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

variable "environment" {
  description = "Environment name (e.g., integration, staging, production)"
  type        = string
  default     = "integration"
}

variable "aws_regions" {
  description = "List of AWS regions where pipeline can operate"
  type        = list(string)
  default     = ["us-east-1", "us-east-2", "us-west-2", "eu-west-1"]
}

variable "deployment_target" {
  description = "Which account type to deploy roles for: 'ci', 'regional', or 'management'"
  type        = string
  default     = "ci"

  validation {
    condition     = contains(["ci", "regional", "management"], var.deployment_target)
    error_message = "Deployment target must be 'ci', 'regional', or 'management'."
  }
}

variable "create_ci_roles" {
  description = "Whether to create CI account roles (set false when deploying to target accounts)"
  type        = bool
  default     = null
}

variable "create_regional_role" {
  description = "Whether to create regional account role (set true only in regional account)"
  type        = bool
  default     = null
}

variable "create_management_role" {
  description = "Whether to create management account role (set true only in management account)"
  type        = bool
  default     = null
}

variable "role_name_prefix" {
  description = "Prefix for IAM role names"
  type        = string
  default     = "rosa-pipeline"
}

variable "max_session_duration" {
  description = "Maximum CLI/API session duration in seconds for assumed roles"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 43200
    error_message = "Session duration must be between 900 seconds (15 minutes) and 43200 seconds (12 hours)."
  }
}