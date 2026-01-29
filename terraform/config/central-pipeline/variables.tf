variable "target_account_ids" {
  description = "List of AWS Account IDs that the CodeBuild role is allowed to assume roles in"
  type        = list(string)
  default     = ["109342711269", "507041536644"]
}

variable "target_role_name" {
  description = "Name of the IAM role to assume in target accounts"
  type        = string
  default     = "OrganizationAccountAccessRole"
}

variable "region" {
  description = "The AWS region to deploy the pipeline into"
  type        = string
  default     = "us-east-2"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (e.g., 'rate(1 hour)' or 'cron(0 * * * ? *)')"
  type        = string
  default     = "cron(30 * * * ? *)"
}

