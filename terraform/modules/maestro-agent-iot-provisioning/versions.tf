# =============================================================================
# Maestro Agent IoT Provisioning Module - Version Constraints
# =============================================================================

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }
}
