# =============================================================================
# Maestro Infrastructure Module - Main Configuration
# =============================================================================

# =============================================================================
# Data Sources
# =============================================================================

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  common_tags = merge(
    var.tags,
    {
      Module    = "maestro-infrastructure"
      ManagedBy = "terraform"
    }
  )
}
