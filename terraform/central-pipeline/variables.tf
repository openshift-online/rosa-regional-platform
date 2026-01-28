variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "codestar_connection_arn" {
  description = "The ARN of the CodeStar connection to GitHub"
  type        = string
}

variable "repository_id" {
  description = "GitHub repository ID (owner/repo)"
  type        = string
  default     = "openshift-online/rosa-regional-platform"
}

variable "branch_name" {
  description = "Branch to trigger the pipeline"
  type        = string
  default     = "main"
}
