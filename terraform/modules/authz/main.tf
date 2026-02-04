# =============================================================================
# ROSA Authorization Module - Main Configuration
#
# This module creates AWS resources for ROSA Cedar/AVP-based authorization:
# - DynamoDB tables for accounts, admins, groups, policies, attachments
# - IAM roles for Pod Identity access to DynamoDB and AVP
# =============================================================================

# =============================================================================
# Data Sources
# =============================================================================

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  common_tags = merge(
    var.tags,
    {
      Module    = "authz"
      ManagedBy = "terraform"
    }
  )

  # Table names following the pattern: ${resource_name_base}-authz-${purpose}
  table_names = {
    accounts    = "${var.resource_name_base}-authz-accounts"
    admins      = "${var.resource_name_base}-authz-admins"
    groups      = "${var.resource_name_base}-authz-groups"
    members     = "${var.resource_name_base}-authz-group-members"
    policies    = "${var.resource_name_base}-authz-policies"
    attachments = "${var.resource_name_base}-authz-attachments"
  }
}
