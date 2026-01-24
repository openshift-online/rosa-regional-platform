# Variables for ECS Bootstrap Module

variable "resource_name_base" {
  description = "Base name for all resources created by this module"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ECS bootstrap tasks will run"
  type        = string
}

variable "private_subnets" {
  description = "List of private subnet IDs for ECS task execution"
  type        = list(string)
}

variable "eks_cluster_arn" {
  description = "ARN of the EKS cluster that bootstrap tasks will configure"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster that bootstrap tasks will configure"
  type        = string
}

variable "eks_cluster_security_group_id" {
  description = "Security group ID of the EKS cluster control plane"
  type        = string
}

variable "repository_url" {
  description = "Git repository URL for cluster configuration"
  type        = string
  default     = "https://github.com/openshift-online/rosa-regional-platform"
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

# Cluster metadata variables for template rendering
variable "environment" {
  description = "Environment identifier for the cluster (e.g., development, staging, production)"
  type        = string
}

variable "sector" {
  description = "Sector identifier for the cluster (e.g., dev, test, prod)"
  type        = string
}

variable "region" {
  description = "AWS region for the cluster"
  type        = string
}

variable "cluster_type" {
  description = "Type of cluster (regional or management)"
  type        = string
}