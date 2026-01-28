locals {
  region_files = fileset("${path.module}/regions", "*.yaml")
  regions = {
    for f in local.region_files :
    yamldecode(file("${path.module}/regions/${f}")).name => yamldecode(file("${path.module}/regions/${f}"))
  }
}

resource "aws_organizations_account" "account" {
  for_each = local.regions

  name      = each.value.name
  email     = each.value.email
  role_name = "OrganizationAccountAccessRole"
  
  # Ensure we don't close accounts by accident during dev
  close_on_deletion = false
}
