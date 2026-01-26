# =============================================================================
# Maestro Agent Module - Input Variables
# =============================================================================

variable "cluster_id" {
  description = "Management cluster identifier (e.g., 'management-01')"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_id))
    error_message = "cluster_id must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "regional_aws_account_id" {
  description = "AWS account ID where the regional cluster and IoT Core are hosted"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.regional_aws_account_id))
    error_message = "regional_aws_account_id must be a 12-digit AWS account ID"
  }
}

variable "eks_cluster_name" {
  description = "Name of the EKS management cluster"
  type        = string
}

variable "mqtt_cert_secret_name" {
  description = "Name of the AWS Secrets Manager secret containing MQTT certificate (must be created manually via AWS CLI)"
  type        = string
  default     = ""

  validation {
    condition     = var.mqtt_cert_secret_name == "" || can(regex("^[a-zA-Z0-9/_+=.@-]+$", var.mqtt_cert_secret_name))
    error_message = "mqtt_cert_secret_name must be a valid Secrets Manager secret name"
  }
}

variable "mqtt_topic_prefix" {
  description = "MQTT topic prefix used in regional IoT Core"
  type        = string
  default     = "sources/maestro/consumers"
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
