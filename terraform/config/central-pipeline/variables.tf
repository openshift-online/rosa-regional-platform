variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "repository_id" {
  description = "GitHub repository ID (owner/repo format, e.g., owner/repo-name)"
  type        = string
}

variable "branch_name" {
  description = "Branch to trigger the pipeline"
  type        = string
  default     = "main"
}
