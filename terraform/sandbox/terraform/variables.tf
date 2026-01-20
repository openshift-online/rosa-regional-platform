variable "account_ids" {
  description = "List of AWS Account IDs to populate in the pool"
  type        = list(string)
  default     = ["109342711269", "114594328247", "095279701323", "507041536644"]
}

variable "aws_region" {
  description = "AWS Region for resources and cleanup"
  type        = string
  default     = "us-east-2"
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_branch" {
  description = "GitHub repository branch"
  type        = string
  default     = "main"
}

variable "codestar_connection_name" {
  description = "Name of the CodeStar connection to create"
  type        = string
  default     = "sandbox-github-connection"
}

variable "schedule_expression" {
  description = "Schedule expression for the pipeline (e.g., cron(0 12 * * ? *))"
  type        = string
  default     = "cron(0 12 * * ? *)"
}

variable "artifacts_bucket_name" {
  description = "Name of the S3 bucket for CodePipeline artifacts"
  type        = string
  default     = "sandbox-codepipeline-artifacts"
}
