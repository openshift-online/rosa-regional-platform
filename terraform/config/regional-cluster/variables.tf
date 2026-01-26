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

# =============================================================================
# API Gateway Configuration Variables
# =============================================================================

variable "region_name" {
  description = "AWS region name for API Gateway URL construction (e.g., 'us-west-2')"
  type        = string
}

# Maestro Configuration Variables
# =============================================================================

variable "management_cluster_ids" {
  description = "List of management cluster IDs that will connect to this regional cluster via Maestro"
  type        = list(string)
  default     = ["management-01"]
}

variable "management_cluster_account_ids" {
  description = "List of AWS account IDs where management clusters run (CRITICAL for cross-account access). If management clusters are in different AWS accounts, add those account IDs here to enable cross-account IAM trust and Secrets Manager access. Leave empty if management clusters are in the same account as regional cluster."
  type        = list(string)
  default     = []
}

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
