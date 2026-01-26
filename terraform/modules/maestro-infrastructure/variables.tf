# =============================================================================
# Maestro Infrastructure Module - Variables
#
# This module creates AWS resources for Maestro MQTT-based orchestration:
# - AWS IoT Core (MQTT broker, Things, certificates, policies)
# - RDS PostgreSQL (Maestro Server state storage)
# - Secrets Manager (MQTT certificates, DB credentials)
# - IAM roles (Pod Identity for Maestro components and External Secrets)
# =============================================================================

variable "resource_name_base" {
  description = "Base name for all resources (e.g., regional-x8k2)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for RDS deployment"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "EKS cluster name for Pod Identity associations"
  type        = string
}

variable "eks_cluster_security_group_id" {
  description = "EKS cluster security group ID for RDS access"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Optional bastion security group ID for RDS access (if bastion is enabled)"
  type        = string
  default     = null
}

# Database configuration
variable "db_instance_class" {
  description = "RDS instance class for Maestro PostgreSQL database"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.4"
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "maestro"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "maestro_admin"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS (production use)"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for RDS instance"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when deleting RDS instance"
  type        = bool
  default     = true
}

# Management cluster configuration
variable "management_cluster_count" {
  description = "Number of management clusters to create IoT Things/certs for"
  type        = number
  default     = 1
}

variable "management_cluster_ids" {
  description = "List of management cluster IDs for creating IoT Things and certificates"
  type        = list(string)
  default     = ["management-01"]
}

variable "management_cluster_account_ids" {
  description = "List of AWS account IDs where management clusters run (for cross-account IAM trust and Secrets Manager access). If empty, uses current account only."
  type        = list(string)
  default     = []
}

# MQTT/IoT configuration
variable "mqtt_topic_prefix" {
  description = "Prefix for MQTT topics (e.g., maestro/consumers)"
  type        = string
  default     = "maestro/consumers"
}

# Tagging
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
