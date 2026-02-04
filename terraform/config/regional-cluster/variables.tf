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
# ArgoCD Bootstrap Configuration Variables
# =============================================================================

variable "repository_url" {
  description = "Git repository URL for cluster configuration"
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

# =============================================================================
# Frontend API Variables
# =============================================================================

variable "api_additional_allowed_accounts" {
  description = "Additional AWS account IDs allowed to access the Frontend API (comma-separated). The current account is automatically included."
  type        = string
  default     = ""
}

# Maestro Configuration Variables
# =============================================================================

variable "maestro_db_instance_class" {
  description = "RDS instance class for Maestro PostgreSQL database"
  type        = string
  default     = "db.t4g.micro"
}

variable "maestro_db_multi_az" {
  description = "Enable Multi-AZ deployment for Maestro RDS (recommended for production)"
  type        = bool
  default     = false
}

variable "maestro_db_deletion_protection" {
  description = "Enable deletion protection for Maestro RDS instance (recommended for production)"
  type        = bool
  default     = false
}

variable "maestro_mqtt_topic_prefix" {
  description = "Prefix for MQTT topics used by Maestro"
  type        = string
  default     = "maestro/consumers"
}

# =============================================================================
# Authorization Configuration Variables
# =============================================================================

variable "authz_billing_mode" {
  description = "DynamoDB billing mode for authz tables"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "authz_enable_pitr" {
  description = "Enable point-in-time recovery for authz DynamoDB tables (recommended for production)"
  type        = bool
  default     = false
}

variable "authz_deletion_protection" {
  description = "Enable deletion protection for authz DynamoDB tables (recommended for production)"
  type        = bool
  default     = false
}

variable "authz_frontend_api_namespace" {
  description = "Kubernetes namespace for Frontend API (used for Pod Identity)"
  type        = string
  default     = "rosa-frontend-api"
}

variable "authz_frontend_api_service_account" {
  description = "Kubernetes service account name for Frontend API (used for Pod Identity)"
  type        = string
  default     = "rosa-frontend-api"
}
