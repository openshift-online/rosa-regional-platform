# Variables for Pipeline IAM Configuration

variable "deployment_target" {
  description = "Which account type to deploy roles for: 'ci', 'regional', or 'management'"
  type        = string

  validation {
    condition     = contains(["ci", "regional", "management"], var.deployment_target)
    error_message = "Deployment target must be 'ci', 'regional', or 'management'."
  }
}

variable "ci_account_id" {
  description = "AWS account ID for CI/pipeline infrastructure"
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