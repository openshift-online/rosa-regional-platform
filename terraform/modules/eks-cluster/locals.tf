locals {
  # Cluster type to purpose mapping
  cluster_type_to_purpose = {
    regional   = "workload-cluster"
    management = "control-plane-cluster"
  }

  # Availability zone selection
  # Use provided AZs if given, otherwise auto-detect the first 3 available AZs
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)

  # Common tags applied to all resources
  common_tags = merge(
    var.tags,
    {
      "managed-by"   = "terraform"
      "cluster-type" = var.cluster_type
    }
  )
}