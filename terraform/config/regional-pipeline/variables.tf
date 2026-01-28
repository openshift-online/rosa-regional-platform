variable "region" {
  description = "AWS Region for this Regional Pipeline"
  type        = string
}

variable "repository_id" {
  description = "GitHub repository ID (owner/repo format)"
  type        = string
}

variable "branch_name" {
  description = "Branch to trigger the pipeline"
  type        = string
  default     = "main"
}

variable "central_state_bucket" {
  description = "S3 bucket from Central Pipeline containing management-deploy state"
  type        = string
}
