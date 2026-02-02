# =============================================================================
# Required variables
# =============================================================================

variable "cluster_type" {
  description = "Type of cluster: 'regional-cluster' for workload clusters or 'management-cluster' for control plane clusters"
  type        = string

  validation {
    condition     = contains(["regional-cluster", "management-cluster"], var.cluster_type)
    error_message = "Cluster type must be either 'regional-cluster' or 'management-cluster'."
  }
}

variable "cluster_name_override" {
  description = "Optional override for cluster name. If not set, uses auto-generated name (cluster_type-random). Use this to specify a deterministic cluster name."
  type        = string
  default     = null
}

# =============================================================================
# Kubernetes configuration
# =============================================================================

variable "cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.34"

  validation {
    condition     = can(regex("^1\\.(2[89]|3[0-9])$", var.cluster_version))
    error_message = "Cluster version must be more modern."
  }
}

# =============================================================================
# VPC and networking configuration
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Choose non-overlapping range for your environment."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones. If empty, will auto-detect first 3 AZs in the region."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) == 0 || length(var.availability_zones) >= 2
    error_message = "If specified, must provide at least 2 availability zones for EKS high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets where EKS worker nodes will be deployed (secure, no direct internet)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Must provide at least 2 private subnets for EKS high availability."
  }

  validation {
    condition = length(var.availability_zones) > 0 ? (
      length(var.private_subnet_cidrs) <= length(var.availability_zones)
      ) : (
      length(var.private_subnet_cidrs) <= 3
    )
    error_message = "Number of private subnet CIDRs cannot exceed available availability zones. When availability_zones is specified, subnet count must not exceed the number of specified AZs. When using auto-detected AZs (default), provide at most 3 subnets."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (used only for NAT gateway - no worker nodes)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "Must provide at least 1 public subnet for NAT gateway."
  }

  validation {
    condition = length(var.availability_zones) > 0 ? (
      length(var.public_subnet_cidrs) <= length(var.availability_zones)
      ) : (
      length(var.public_subnet_cidrs) <= 3
    )
    error_message = "Number of public subnet CIDRs cannot exceed available availability zones. When availability_zones is specified, subnet count must not exceed the number of specified AZs. When using auto-detected AZs (default), provide at most 3 subnets."
  }
}


# =============================================================================
# EKS node group configuration
# =============================================================================

variable "node_instance_types" {
  description = "List of EC2 instance types for worker nodes. Multiple types enable spot instances and better availability."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "Must specify at least one instance type."
  }
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes in the node group"
  type        = number
  default     = 2

  validation {
    condition     = var.node_group_desired_size >= 1 && var.node_group_desired_size <= 100
    error_message = "Node group desired size must be between 1 and 100."
  }
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes in the node group"
  type        = number
  default     = 1

  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "Node group minimum size must be at least 1."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes in the node group"
  type        = number
  default     = 4

  validation {
    condition     = var.node_group_max_size >= 1
    error_message = "Node group maximum size must be at least 1."
  }
}

variable "node_disk_size" {
  description = "Disk size in GiB for worker nodes. Includes OS and container image storage."
  type        = number
  default     = 20

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 1000
    error_message = "Node disk size must be between 20 and 1000 GiB."
  }
}


# =============================================================================
# Advanced security configuration options
# =============================================================================

variable "enable_pod_security_standards" {
  description = "Enable Kubernetes Pod Security Standards for enhanced security"
  type        = bool
  default     = true
}

# =============================================================================
# Validation Rules
# =============================================================================

# Ensure private and public subnet counts match
locals {
  subnet_count_validation = length(var.private_subnet_cidrs) == length(var.public_subnet_cidrs) ? true : tobool("Private and public subnet counts must match")
}

# Ensure desired size is between min and max
locals {
  node_size_validation = var.node_group_desired_size >= var.node_group_min_size && var.node_group_desired_size <= var.node_group_max_size ? true : tobool("Node group desired size must be between min_size and max_size")
}