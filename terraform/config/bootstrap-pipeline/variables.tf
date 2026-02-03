# =============================================================================
# GitHub Repository Configuration
# =============================================================================

variable "github_repo_owner" {
  type        = string
  description = "GitHub Repository Owner"
}

variable "github_repo_name" {
  type        = string
  description = "GitHub Repository Name"
}

variable "github_branch" {
  type        = string
  description = "GitHub Branch to track"
  default     = "main"
}

# =============================================================================
# AWS Configuration
# =============================================================================

variable "region" {
  type        = string
  description = "AWS Region for the Pipeline Infrastructure"
  default     = "us-east-1"
}

# =============================================================================
# Optional Regional Cluster Pipeline Overrides
# =============================================================================

variable "regional_target_account_id" {
  type        = string
  description = "Regional target AWS Account ID (Optional override)"
  default     = ""
}

variable "regional_target_region" {
  type        = string
  description = "Regional target AWS Region (Optional override)"
  default     = ""
}

variable "regional_target_alias" {
  type        = string
  description = "Regional target Alias (Optional override)"
  default     = ""
}

# =============================================================================
# Optional Management Cluster Pipeline Overrides
# =============================================================================

variable "management_target_account_id" {
  type        = string
  description = "Management target AWS Account ID (Optional override)"
  default     = ""
}

variable "management_target_region" {
  type        = string
  description = "Management target AWS Region (Optional override)"
  default     = ""
}

variable "management_target_alias" {
  type        = string
  description = "Management target Alias (Optional override)"
  default     = ""
}
