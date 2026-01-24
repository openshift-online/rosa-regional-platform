# =============================================================================
# Required Variables
# =============================================================================

variable "vpc_id" {
  description = "VPC ID where the ALB and VPC Link will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ALB and VPC Link placement"
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least 2 private subnets are required for ALB high availability."
  }
}

variable "resource_name_base" {
  description = "Base name for resources (e.g., 'regional-x8k2')"
  type        = string
}

variable "region_name" {
  description = "AWS region name for constructing API URLs (e.g., 'us-west-2')"
  type        = string
}

variable "node_security_group_id" {
  description = "EKS node/pod security group ID - ALB needs to send traffic to pods via this SG. For EKS Auto Mode, use the cluster_primary_security_group_id."
  type        = string
}

# =============================================================================
# ALB and Target Group Configuration
# =============================================================================

variable "target_port" {
  description = "Port on which the backend service receives traffic"
  type        = number
  default     = 8080

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "Target port must be between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Path for ALB health checks on the backend service"
  type        = string
  default     = "/v0/live"
}

variable "health_check_interval" {
  description = "Interval in seconds between health checks"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Timeout in seconds for health check response"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

# =============================================================================
# API Gateway Configuration
# =============================================================================

variable "stage_name" {
  description = "API Gateway stage name"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.stage_name))
    error_message = "Stage name can only contain alphanumeric characters, hyphens, and underscores."
  }
}

variable "api_description" {
  description = "Description for the API Gateway REST API"
  type        = string
  default     = "ROSA Regional Frontend API"
}
