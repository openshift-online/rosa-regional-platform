# =============================================================================
# Local Values
# =============================================================================

# Random suffix for resource naming (only used if cluster_name_override is not set)
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  # Use cluster_name_override if provided, otherwise generate with random suffix
  resource_name_base = var.cluster_name_override != null ? var.cluster_name_override : "${var.cluster_type}-${random_string.suffix.result}"

  # Availability zone selection
  # Use provided AZs if given, otherwise auto-detect the first 3 available AZs
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
}