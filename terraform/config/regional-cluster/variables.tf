# =============================================================================
# Regional Cluster Infrastructure Variables
# =============================================================================

variable "app_code" {
  description = "Application code for tagging (CMDB Application ID)"
  type        = string
}

variable "service_phase" {
  description = "Service phase for tagging (development, staging, or production)"
  type        = string
}

variable "cost_center" {
  description = "Cost center for tagging (3-digit cost center code)"
  type        = string
}

# =============================================================================
# Cluster Metadata Variables
# =============================================================================

variable "environment" {
  description = "Environment identifier for the cluster (e.g., development, staging, production)"
  type        = string
}

variable "sector" {
  description = "Sector identifier for the cluster (e.g., dev, test, prod)"
  type        = string
}

# =============================================================================
# ArgoCD Bootstrap Configuration Variables
# =============================================================================

variable "repository_url" {
  description = "Git repository URL for cluster configuration"
  type        = string
}

variable "repository_path" {
  description = "Path within repository containing ArgoCD applications"
  type        = string
}

variable "repository_branch" {
  description = "Git branch to use for cluster configuration"
  type        = string
  default     = "main"
}

# =============================================================================
# Bastion Configuration Variables
# =============================================================================

variable "enable_bastion" {
  description = "Enable ECS Fargate bastion for break-glass/development access to the cluster"
  type        = bool
  default     = false
}