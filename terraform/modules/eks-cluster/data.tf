# =============================================================================
# Data Sources
#
# Fetches AWS environment information needed for resource configuration.
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Environment Information
# -----------------------------------------------------------------------------

# Fetches available AZs for the current region
data "aws_availability_zones" "available" {
  state = "available"
}

# Current AWS account information
data "aws_caller_identity" "current" {}

# Current AWS partition (aws, aws-us-gov, aws-cn)
data "aws_partition" "current" {}

# Current AWS region
data "aws_region" "current" {}